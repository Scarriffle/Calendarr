package com.scarriffle.calendarr.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.data.CredentialStore
import com.scarriffle.calendarr.data.OidcAuthenticator
import com.scarriffle.calendarr.data.SettingsStore
import com.scarriffle.calendarr.data.remote.ApiProvider
import com.scarriffle.calendarr.domain.model.AppSettings
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class AppRoute { SETUP, LOGIN, MAIN }

@HiltViewModel
class MainViewModel @Inject constructor(
    private val credentialStore: CredentialStore,
    private val settingsStore: SettingsStore,
    private val repository: CalendarRepository,
    private val apiProvider: ApiProvider,
    private val oidc: OidcAuthenticator,
) : ViewModel() {

    private val _route = MutableStateFlow(computeRoute())
    val route: StateFlow<AppRoute> = _route.asStateFlow()

    private val _settings = MutableStateFlow(settingsStore.loadSettings())
    val settings: StateFlow<AppSettings> = _settings.asStateFlow()

    val serverUrl: String get() = credentialStore.serverUrl ?: ""
    val username: String get() = credentialStore.username ?: ""
    val isAdmin: Boolean get() = credentialStore.isAdmin

    init {
        if (_route.value == AppRoute.MAIN) {
            refreshSettings()
            renewSsoSessionIfNeeded()
        }
    }

    /**
     * Keep an SSO session alive without another trip through the browser.
     *
     * Calendarr's own token simply expires; what `offline_access` buys is a
     * refresh token at the *provider*. So renewal means: fresh ID token from
     * the provider, then trade it for a fresh Calendarr token.
     *
     * Best effort — on any failure the existing token stays in place and the
     * user notices nothing until it genuinely expires.
     */
    private fun renewSsoSessionIfNeeded() {
        val state = credentialStore.oidcState ?: return
        val providerKey = credentialStore.oidcProvider ?: return
        val clientId = credentialStore.oidcClientId ?: return
        val base = credentialStore.serverUrl ?: return
        val token = credentialStore.token ?: return
        if (!expiresSoon(token)) return

        viewModelScope.launch {
            runCatching {
                val renewed = oidc.renewIdToken(state) ?: return@runCatching
                repository.exchangeOidc(
                    baseUrl = base,
                    provider = providerKey,
                    clientId = clientId,
                    idToken = renewed.idToken,
                    accessToken = renewed.accessToken,
                    nonce = renewed.nonce,
                )
                credentialStore.saveOidcSession(renewed.serialisedState, providerKey, clientId)
            }
        }
    }

    private fun computeRoute(): AppRoute = when {
        !credentialStore.isConfigured -> AppRoute.SETUP
        !credentialStore.isLoggedIn -> AppRoute.LOGIN
        else -> AppRoute.MAIN
    }

    fun onServerConfigured() { _route.value = computeRoute() }

    fun onLoggedIn() {
        _route.value = AppRoute.MAIN
        refreshSettings()
    }

    fun logout() {
        credentialStore.clearToken()
        _route.value = computeRoute()
    }

    fun switchServer() {
        credentialStore.clearAll()
        apiProvider.invalidate()
        _route.value = computeRoute()
    }

    /** Pull settings from the server and merge them with local values honouring
     *  each setting's sync flag (synced keys take the server value). */
    fun refreshSettings() {
        viewModelScope.launch {
            runCatching { repository.getSettings() }.onSuccess { s ->
                _settings.value = settingsStore.applyServerPull(s)
            }
        }
    }

    fun applyLocalSettings(s: AppSettings) {
        settingsStore.saveSettings(s)
        _settings.value = s
    }

    /**
     * True when the Calendarr JWT expires within [RENEW_WITHIN_MS].
     *
     * The payload is read without verifying the signature — this only decides
     * *whether* to renew, and the server validates the token on every request
     * regardless. A token we cannot parse is left alone.
     */
    private fun expiresSoon(jwt: String): Boolean {
        val parts = jwt.split(".")
        if (parts.size != 3) return false
        return runCatching {
            val payload = android.util.Base64.decode(
                parts[1],
                android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or
                    android.util.Base64.NO_WRAP,
            )
            val exp = org.json.JSONObject(String(payload)).optLong("exp", 0L)
            exp > 0L && (exp * 1000L) - System.currentTimeMillis() < RENEW_WITHIN_MS
        }.getOrDefault(false)
    }

    private companion object {
        /** Renew when less than a day of the Calendarr token's life is left. */
        const val RENEW_WITHIN_MS = 24L * 60 * 60 * 1000
    }
}
