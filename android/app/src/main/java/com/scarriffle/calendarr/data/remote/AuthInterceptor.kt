package com.scarriffle.calendarr.data.remote

import com.scarriffle.calendarr.data.CredentialStore
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject

/**
 * Attaches the current bearer token (read dynamically from the
 * [CredentialStore]) to every request. Requests made before login simply
 * carry no Authorization header.
 */
class AuthInterceptor @Inject constructor(
    private val credentialStore: CredentialStore,
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val token = credentialStore.token
        val request = if (!token.isNullOrBlank()) {
            chain.request().newBuilder()
                .header("Authorization", "Bearer $token")
                .build()
        } else {
            chain.request()
        }
        return chain.proceed(request)
    }
}
