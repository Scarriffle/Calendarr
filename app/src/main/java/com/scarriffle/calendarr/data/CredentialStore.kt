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

    /** Clear the token (logout) but keep the server URL. */
    fun clearToken() {
        prefs.edit()
            .remove(KEY_TOKEN)
            .remove(KEY_USERNAME)
            .remove(KEY_IS_ADMIN)
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
    }
}
