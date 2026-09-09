package com.scarriffle.calendarr.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Securely stores the server URL and auth token in EncryptedSharedPreferences
 * (Android's equivalent of the iOS Keychain). The iOS app keeps these in
 * UserDefaults; on Android we encrypt them at rest.
 */
@Singleton
class CredentialStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs: SharedPreferences = run {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "calendarr_secure_prefs",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    var serverUrl: String?
        get() = prefs.getString(KEY_SERVER_URL, null)
        set(value) = prefs.edit().putString(KEY_SERVER_URL, value).apply()

    var token: String?
        get() = prefs.getString(KEY_TOKEN, null)
        set(value) = prefs.edit().putString(KEY_TOKEN, value).apply()

    var username: String?
        get() = prefs.getString(KEY_USERNAME, null)
        set(value) = prefs.edit().putString(KEY_USERNAME, value).apply()

    var isAdmin: Boolean
        get() = prefs.getBoolean(KEY_IS_ADMIN, false)
        set(value) = prefs.edit().putBoolean(KEY_IS_ADMIN, value).apply()

    var userId: Int
        get() = prefs.getInt(KEY_USER_ID, 0)
        set(value) = prefs.edit().putInt(KEY_USER_ID, value).apply()

    var displayName: String?
        get() = prefs.getString(KEY_DISPLAY_NAME, null)
        set(value) = prefs.edit().putString(KEY_DISPLAY_NAME, value).apply()

    /**
     * Serialised AppAuth [net.openid.appauth.AuthState] for the SSO session —
     * holds the provider's refresh token, so it must stay in the encrypted
     * store and never in plain preferences.
     */
    var oidcState: String?
        get() = prefs.getString(KEY_OIDC_STATE, null)
        set(value) = prefs.edit().putString(KEY_OIDC_STATE, value).apply()

    /** Provider key and client id the current SSO session was obtained with. */
    var oidcProvider: String?
        get() = prefs.getString(KEY_OIDC_PROVIDER, null)
        set(value) = prefs.edit().putString(KEY_OIDC_PROVIDER, value).apply()

    var oidcClientId: String?
        get() = prefs.getString(KEY_OIDC_CLIENT_ID, null)
        set(value) = prefs.edit().putString(KEY_OIDC_CLIENT_ID, value).apply()

    /** True once a server URL has been entered (setup step complete). */
    val isConfigured: Boolean get() = !serverUrl.isNullOrBlank()

    /** True once we hold an auth token (logged in). */
    val isLoggedIn: Boolean get() = !token.isNullOrBlank()

    fun saveLogin(token: String, username: String, isAdmin: Boolean, userId: Int = 0, displayName: String? = null) {
        prefs.edit()
            .putString(KEY_TOKEN, token)
            .putString(KEY_USERNAME, username)
            .putBoolean(KEY_IS_ADMIN, isAdmin)
            .putInt(KEY_USER_ID, userId)
            .putString(KEY_DISPLAY_NAME, displayName ?: username)
            .apply()
    }

    /** Persist the SSO session alongside the Calendarr token. */
    fun saveOidcSession(state: String, provider: String, clientId: String) {
        prefs.edit()
            .putString(KEY_OIDC_STATE, state)
            .putString(KEY_OIDC_PROVIDER, provider)
            .putString(KEY_OIDC_CLIENT_ID, clientId)
            .apply()
    }

    /** Clear the token (logout) but keep the server URL. */
    fun clearToken() {
        prefs.edit()
            .remove(KEY_TOKEN)
            .remove(KEY_USERNAME)
            .remove(KEY_IS_ADMIN)
            .remove(KEY_OIDC_STATE)
            .remove(KEY_OIDC_PROVIDER)
            .remove(KEY_OIDC_CLIENT_ID)
            .apply()
    }

    /** Full reset, including the server URL ("switch server"). */
    fun clearAll() {
        prefs.edit().clear().apply()
    }

    private companion object {
        const val KEY_SERVER_URL = "server_url"
        const val KEY_TOKEN = "auth_token"
        const val KEY_USERNAME = "username"
        const val KEY_IS_ADMIN = "is_admin"
        const val KEY_USER_ID = "user_id"
        const val KEY_DISPLAY_NAME = "display_name"
        const val KEY_OIDC_STATE = "oidc_state"
        const val KEY_OIDC_PROVIDER = "oidc_provider"
        const val KEY_OIDC_CLIENT_ID = "oidc_client_id"
    }
}
