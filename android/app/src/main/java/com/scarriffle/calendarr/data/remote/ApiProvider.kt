package com.scarriffle.calendarr.data.remote

import com.scarriffle.calendarr.data.CredentialStore
import com.squareup.moshi.Moshi
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Builds [CalendarrApi] instances. The base URL is dynamic (the user's server),
 * so the cached instance is rebuilt whenever the stored server URL changes.
 */
@Singleton
class ApiProvider @Inject constructor(
    private val credentialStore: CredentialStore,
    private val moshi: Moshi,
    private val authInterceptor: AuthInterceptor,
) {
    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .addInterceptor(authInterceptor)
            .addInterceptor(
                HttpLoggingInterceptor().apply { level = HttpLoggingInterceptor.Level.BASIC }
            )
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .build()
    }

    @Volatile private var cached: Pair<String, CalendarrApi>? = null

    /** API bound to the currently stored server URL. Requires a configured server. */
    fun api(): CalendarrApi {
        val base = normalize(credentialStore.serverUrl ?: error("No server URL configured"))
        cached?.let { (url, api) -> if (url == base) return api }
        val api = build(base)
        cached = base to api
        return api
    }

    /** API for an explicit base URL (used during server setup / login). */
    fun apiFor(baseUrl: String): CalendarrApi = build(normalize(baseUrl))

    /** Force the cached instance to be rebuilt (e.g. after switching servers). */
    fun invalidate() { cached = null }

    private fun build(baseUrl: String): CalendarrApi =
        Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(CalendarrApi::class.java)

    companion object {
        /** Ensure https:// prefix, strip trailing slashes, then add exactly one. */
        fun normalize(raw: String): String {
            var url = raw.trim()
            if (url.isEmpty()) return url
            if (!url.startsWith("http://") && !url.startsWith("https://")) {
                url = "https://$url"
            }
            url = url.trimEnd('/')
            return "$url/"
        }
    }
}
