package com.scarriffle.calendarr.data

import android.content.Context
import android.content.Intent
import com.scarriffle.calendarr.domain.model.OidcProvider
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.suspendCancellableCoroutine
import net.openid.appauth.AuthState
import net.openid.appauth.AuthorizationException
import net.openid.appauth.AuthorizationRequest
import net.openid.appauth.AuthorizationResponse
import net.openid.appauth.AuthorizationService
import net.openid.appauth.AuthorizationServiceConfiguration
import net.openid.appauth.ResponseTypeValues
import net.openid.appauth.TokenResponse
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** The app is registered as a *public* client — no secret is ever sent. */
private const val REDIRECT_URI = "com.scarriffle.calendarr:/oauth2redirect"

/**
 * Drives the OpenID Connect Authorization Code Flow with PKCE against the
 * identity provider, using AppAuth and a Chrome Custom Tab.
 *
 * Deliberately never uses a WebView: a custom tab keeps the credentials in the
 * browser's own security context and lets the provider's session cookies work.
 */
@Singleton
class OidcAuthenticator @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    @Volatile
    private var service: AuthorizationService? = null

    private fun service(): AuthorizationService =
        service ?: synchronized(this) {
            service ?: AuthorizationService(context).also { service = it }
        }

    /** Fetch the provider's OpenID configuration from its issuer URL. */
    suspend fun discover(provider: OidcProvider): AuthorizationServiceConfiguration =
        suspendCancellableCoroutine { cont ->
            AuthorizationServiceConfiguration.fetchFromIssuer(
                android.net.Uri.parse(provider.issuer)
            ) { config, ex ->
                when {
                    config != null -> cont.resume(config)
                    else -> cont.resumeWithException(ex ?: AuthorizationException.GeneralErrors.NETWORK_ERROR)
                }
            }
        }

    /**
     * Build the authorization request. AppAuth generates the PKCE verifier and
     * the nonce itself; both are carried on the returned request, and the nonce
     * has to travel to our server later so it can verify the ID token.
     */
    fun buildRequest(
        config: AuthorizationServiceConfiguration,
        provider: OidcProvider,
    ): AuthorizationRequest {
        // Exactly what the server asked for — including offline_access when it
        // configured that. A scope the provider does not know would make it
        // reject the whole authorization request.
        val scopes = buildSet {
            addAll(provider.scopes.split(" ").filter { it.isNotBlank() })
            add("openid")
        }
        return AuthorizationRequest.Builder(
            config,
            requireNotNull(provider.mobileClientId) { "provider has no mobile client id" },
            ResponseTypeValues.CODE,
            android.net.Uri.parse(REDIRECT_URI),
        )
            .setScopes(scopes)
            .build()
    }

    /** Intent that opens the provider's login page in a Custom Tab. */
    fun authorizationIntent(request: AuthorizationRequest): Intent =
        service().getAuthorizationRequestIntent(request)

    /**
     * Complete the code exchange with the provider.
     *
     * PKCE means no client secret is involved: the verifier AppAuth kept from
     * [buildRequest] is what proves this is the same app that started the flow.
     */
    suspend fun exchangeCode(data: Intent): Pair<AuthorizationResponse, TokenResponse> {
        val response = AuthorizationResponse.fromIntent(data)
        val error = AuthorizationException.fromIntent(data)
        if (response == null) throw error ?: AuthorizationException.GeneralErrors.NETWORK_ERROR

        val tokens: TokenResponse = suspendCancellableCoroutine { cont ->
            service().performTokenRequest(response.createTokenExchangeRequest()) { tokens, ex ->
                when {
                    tokens != null -> cont.resume(tokens)
                    else -> cont.resumeWithException(ex ?: AuthorizationException.GeneralErrors.NETWORK_ERROR)
                }
            }
        }
        return response to tokens
    }

    /**
     * Serialised AuthState (including the refresh token) for secure storage.
     *
     * Both arguments are non-null on purpose: `AuthState.update` asserts that
     * exactly one of (response, exception) is set and throws otherwise.
     */
    fun stateFor(response: AuthorizationResponse, tokens: TokenResponse): String =
        AuthState().apply {
            update(response, null)
            update(tokens, null)
        }.jsonSerializeString()
}
