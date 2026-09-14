package com.scarriffle.calendarr.ui.auth

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.data.CredentialStore
import com.scarriffle.calendarr.data.OidcAuthenticator
import com.scarriffle.calendarr.data.remote.ApiProvider
import com.scarriffle.calendarr.data.remote.OidcException
import com.scarriffle.calendarr.data.remote.TwoFactorRequiredException
import com.scarriffle.calendarr.domain.model.OidcProvider
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import net.openid.appauth.AuthorizationException
import javax.inject.Inject

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val repository: CalendarRepository,
    private val credentialStore: CredentialStore,
    private val oidc: OidcAuthenticator,
) : ViewModel() {

    // Server setup
    var serverUrl by mutableStateOf(credentialStore.serverUrl ?: "")
        private set
    var checking by mutableStateOf(false)
        private set
    var setupError by mutableStateOf<String?>(null)
        private set

    // Login
    var username by mutableStateOf("")
        private set
    var password by mutableStateOf("")
        private set
    var totpCode by mutableStateOf("")
        private set
    var showTotp by mutableStateOf(false)
        private set
    var rememberMe by mutableStateOf(true)
        private set
    var loggingIn by mutableStateOf(false)
        private set
    var loginError by mutableStateOf<String?>(null)
        private set

    // Single sign-on
    var ssoProviders by mutableStateOf<List<OidcProvider>>(emptyList())
        private set
    /** Key of the provider whose flow is running, or null. Per-provider so a
     *  second button does not also show a spinner. */
    var ssoBusyKey by mutableStateOf<String?>(null)
        private set

    /** Stable server error slug (e.g. `oidc_account_not_linked`). The screen
     *  turns it into a message; the ViewModel cannot call the translator. */
    var ssoErrorSlug by mutableStateOf<String?>(null)
        private set

    private var loadingProviders = false


    fun onServerUrlChange(v: String) { serverUrl = v; setupError = null }
    fun onUsernameChange(v: String) { username = v; loginError = null; ssoErrorSlug = null }
    fun onPasswordChange(v: String) { password = v; loginError = null; ssoErrorSlug = null }
    fun onTotpChange(v: String) { totpCode = v; loginError = null; ssoErrorSlug = null }
    fun onRememberChange(v: Boolean) { rememberMe = v }

    fun checkServer(onConfigured: () -> Unit) {
        val url = serverUrl.trim()
        if (url.isEmpty()) { setupError = "URL erforderlich"; return }
        viewModelScope.launch {
            checking = true
            setupError = null
            runCatching { repository.setupRequired(url) }
                .onSuccess {
                    credentialStore.serverUrl = ApiProvider.normalize(url)
                    onConfigured()
                }
                .onFailure { setupError = it.message ?: "Verbindung fehlgeschlagen" }
            checking = false
        }
    }

    /** Load the configured providers. Silently yields an empty list when SSO
     *  is off or the server is older — the password form stays as it is. */
    fun loadSsoProviders() {
        val base = credentialStore.serverUrl ?: return
        if (ssoProviders.isNotEmpty() || loadingProviders) return
        loadingProviders = true
        viewModelScope.launch {
            runCatching { repository.oidcProviders(base) }
                .onSuccess { ssoProviders = it }
            loadingProviders = false
        }
    }

    /**
     * Start an SSO login: fetch the provider's configuration, build the PKCE
     * request and open the Custom Tab.
     *
     * The provider key and client id are persisted before launching, because
     * the browser runs in its own task and this process may well be killed
     * while it is in the foreground.
     */
    fun startSso(provider: OidcProvider, launch: (Intent) -> Unit) {
        val clientId = provider.mobileClientId
        if (clientId == null) { ssoErrorSlug = "oidc_unknown_client"; return }
        viewModelScope.launch {
            ssoBusyKey = provider.key
            loginError = null
            ssoErrorSlug = null
            // `launch` has to stay inside runCatching: the result launcher is
            // unregistered if the user leaves the screen while discovery is in
            // flight, and the resulting IllegalStateException would otherwise
            // escape viewModelScope and take the app down.
            runCatching {
                val config = oidc.discover(provider)
                val request = oidc.buildRequest(config, provider)
                credentialStore.oidcProvider = provider.key
                credentialStore.oidcClientId = clientId
                launch(oidc.authorizationIntent(request))
            }.onFailure { e ->
                ssoBusyKey = null
                ssoErrorSlug = when (e) {
                    // No browser at all needs a different remedy than "the
                    // login service is down".
                    is ActivityNotFoundException -> "oidc_no_browser"
                    else -> "oidc_provider_unreachable"
                }
            }
        }
    }

    /** Handle the browser's return: exchange the code, then trade the ID token. */
    fun finishSso(data: Intent?, onSuccess: () -> Unit) {
        if (data == null) { ssoBusyKey = null; return }

        // AppAuth reports a user-cancelled flow as a normal result carrying
        // USER_CANCELED_AUTH_FLOW — backing out of the browser is not an error.
        val failure = AuthorizationException.fromIntent(data)
        if (failure == AuthorizationException.GeneralErrors.USER_CANCELED_AUTH_FLOW) {
            ssoBusyKey = null
            return
        }

        val providerKey = credentialStore.oidcProvider
        val clientId = credentialStore.oidcClientId
        if (providerKey == null || clientId == null) {
            ssoBusyKey = null
            ssoErrorSlug = "oidc_failed"
            return
        }

        viewModelScope.launch {
            runCatching {
                val (response, tokens) = oidc.exchangeCode(data)
                val idToken = tokens.idToken ?: throw OidcException("oidc_no_id_token")
                val result = repository.exchangeOidc(
                    baseUrl = credentialStore.serverUrl ?: error("no server"),
                    provider = providerKey,
                    clientId = clientId,
                    idToken = idToken,
                    accessToken = tokens.accessToken,
                    // AppAuth round-trips the original request through the
                    // redirect, so the nonce survives process death.
                    nonce = response.request.nonce,
                )
                // Keep the provider's refresh token so the session can be
                // renewed later without another trip through the browser.
                credentialStore.saveOidcSession(
                    state = oidc.stateFor(response, tokens),
                    provider = providerKey,
                    clientId = clientId,
                )
                result
            }.onSuccess {
                ssoBusyKey = null
                onSuccess()
            }.onFailure { e ->
                ssoBusyKey = null
                ssoErrorSlug = if (e is OidcException) e.slug else "oidc_failed"
            }
        }
    }

    fun login(onSuccess: () -> Unit) {
        val base = credentialStore.serverUrl ?: return
        if (username.isBlank() || password.isBlank()) {
            loginError = "Benutzername und Passwort erforderlich"
            return
        }
        viewModelScope.launch {
            loggingIn = true
            loginError = null
            runCatching {
                repository.login(
                    baseUrl = base,
                    username = username.trim(),
                    password = password,
                    totpCode = totpCode.trim().takeIf { it.isNotEmpty() },
                    rememberMe = rememberMe,
                )
            }.onSuccess { onSuccess() }
                .onFailure { e ->
                    if (e is TwoFactorRequiredException) {
                        showTotp = true
                        loginError = null
                    } else {
                        loginError = e.message ?: "Anmeldung fehlgeschlagen"
                    }
                }
            loggingIn = false
        }
    }
}
