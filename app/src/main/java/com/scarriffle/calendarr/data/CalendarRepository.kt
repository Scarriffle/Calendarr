package com.scarriffle.calendarr.data

import com.scarriffle.calendarr.data.remote.ApiException
import com.scarriffle.calendarr.data.remote.ApiProvider
import com.scarriffle.calendarr.data.remote.TwoFactorRequiredException
import com.scarriffle.calendarr.data.remote.UnauthorizedException
import com.scarriffle.calendarr.data.remote.ensureSuccess
import com.scarriffle.calendarr.data.remote.errorDetail
import com.scarriffle.calendarr.data.remote.jsonBody
import com.scarriffle.calendarr.domain.model.AppSettings
import com.scarriffle.calendarr.domain.model.CalDAVAccount
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.domain.model.GoogleAccount
import com.scarriffle.calendarr.domain.model.HomeAssistantAccount
import com.scarriffle.calendarr.domain.model.ICalSubscription
import com.scarriffle.calendarr.domain.model.LocalCalendar
import com.scarriffle.calendarr.domain.model.UserProfile
import com.scarriffle.calendarr.domain.model.WritableCalendar
import com.scarriffle.calendarr.util.Dates
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import retrofit2.HttpException
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

data class LoginResult(val token: String, val username: String, val isAdmin: Boolean)

data class TotpSetup(val secret: String, val qrUrl: String)

/**
 * Single entry point for all server interaction. Wraps [com.scarriffle.calendarr.data.remote.CalendarrApi],
 * converts HTTP failures into [ApiException]s carrying the server's `detail`
 * message, and parses the mixed-type event payloads with org.json.
 */
@Singleton
class CalendarRepository @Inject constructor(
    private val apiProvider: ApiProvider,
    private val credentialStore: CredentialStore,
    private val settingsStore: SettingsStore,
) {
    private val api get() = apiProvider.api()

    private suspend fun <T> guarded(block: suspend () -> T): T = withContext(Dispatchers.IO) {
        try {
            block()
        } catch (e: HttpException) {
            if (e.code() == 401) throw UnauthorizedException()
            throw ApiException(errorDetail(e.response()?.errorBody(), e.code()))
        }
    }

    // ---- Auth ----

    suspend fun setupRequired(baseUrl: String): Boolean = withContext(Dispatchers.IO) {
        val resp = apiProvider.apiFor(baseUrl).setupRequired()
        if (!resp.isSuccessful) return@withContext false
        val raw = resp.body()?.string() ?: return@withContext false
        runCatching { JSONObject(raw).optBoolean("required", false) }.getOrDefault(false)
    }

    suspend fun login(
        baseUrl: String,
        username: String,
        password: String,
        totpCode: String?,
        rememberMe: Boolean,
    ): LoginResult = withContext(Dispatchers.IO) {
        val body = jsonBody(
            "username" to username,
            "password" to password,
            "remember_me" to rememberMe,
            "totp_code" to totpCode,
        )
        val resp = apiProvider.apiFor(baseUrl).login(body)
        if (resp.code() == 401) {
            val detail = runCatching {
                JSONObject(resp.errorBody()?.string() ?: "").optString("detail")
            }.getOrNull()
            if (detail == "2fa_required") throw TwoFactorRequiredException()
            throw UnauthorizedException(detail?.takeIf { it.isNotBlank() } ?: "Benutzername oder Passwort falsch")
        }
        if (!resp.isSuccessful) throw ApiException(errorDetail(resp.errorBody(), resp.code()))

        val json = JSONObject(resp.body()?.string() ?: throw ApiException("Leere Antwort"))
        val token = json.optString("access_token").takeIf { it.isNotBlank() }
            ?: throw ApiException("Antwort konnte nicht verarbeitet werden")
        val user = json.optJSONObject("user")
        val uname = user?.optString("username") ?: username
        val isAdmin = user?.optBoolean("is_admin", false) ?: false

        credentialStore.serverUrl = ApiProvider.normalize(baseUrl)
        credentialStore.saveLogin(token, uname, isAdmin)
        apiProvider.invalidate()
        LoginResult(token, uname, isAdmin)
    }

    // ---- Settings / profile ----

    suspend fun getSettings(): AppSettings = guarded { api.getSettings() }

    suspend fun updateSettings(s: AppSettings) = guarded {
        api.updateSettings(
            jsonBody(
                "default_view" to s.defaultView,
                "week_start_day" to s.weekStartDay,
                "primary_color" to s.primaryColor,
                "accent_color" to s.accentColor,
                "today_color" to s.todayColor,
                "dim_past_events" to s.dimPastEvents,
                "text_contrast" to s.textContrast,
                "line_contrast" to s.lineContrast,
                "hour_height" to s.hourHeight,
                "language" to s.language,
                "month_divider_color" to s.monthDividerColor,
                "month_label_color" to s.monthLabelColor,
            )
        ).ensureSuccess()
    }

    suspend fun getProfile(): UserProfile = guarded { api.getProfile() }

    suspend fun updateEmail(email: String) = guarded {
        api.updateEmail(jsonBody("email" to email)).ensureSuccess()
    }

    suspend fun changePassword(current: String, new: String) = guarded {
        api.changePassword(
            jsonBody("current_password" to current, "new_password" to new)
        ).ensureSuccess()
    }

    suspend fun setup2fa(): TotpSetup = guarded {
        val resp = api.setup2fa()
        resp.ensureSuccess()
        val json = JSONObject(resp.body()?.string() ?: "{}")
        TotpSetup(json.optString("secret"), json.optString("qr_url"))
    }

    suspend fun enable2fa(code: String) = guarded {
        api.enable2fa(jsonBody("code" to code)).ensureSuccess()
    }

    suspend fun disable2fa(password: String) = guarded {
        api.disable2fa(jsonBody("password" to password)).ensureSuccess()
    }

    // ---- Accounts ----

    suspend fun getCalDAVAccounts(): List<CalDAVAccount> = guarded { api.getCalDAVAccounts() }

    suspend fun addCalDAVAccount(name: String, url: String, username: String, password: String, color: String) =
        guarded {
            api.addCalDAVAccount(
                jsonBody(
                    "name" to name, "url" to url, "username" to username,
                    "password" to password, "color" to color,
                )
            )
        }

    suspend fun deleteCalDAVAccount(id: Int) = guarded { api.deleteCalDAVAccount(id).ensureSuccess() }

    suspend fun getLocalCalendars(): List<LocalCalendar> = guarded { api.getLocalCalendars() }

    suspend fun addLocalCalendar(name: String, color: String) =
        guarded { api.addLocalCalendar(jsonBody("name" to name, "color" to color)) }

    suspend fun deleteLocalCalendar(id: Int) = guarded { api.deleteLocalCalendar(id).ensureSuccess() }

    suspend fun getICalSubscriptions(): List<ICalSubscription> = guarded { api.getICalSubscriptions() }

    suspend fun addICalSubscription(name: String, url: String, color: String, refreshMinutes: Int) =
        guarded {
            api.addICalSubscription(
                jsonBody(
                    "name" to name, "url" to url, "color" to color,
                    "refresh_minutes" to refreshMinutes,
                )
            )
        }

    suspend fun deleteICalSubscription(id: Int) = guarded { api.deleteICalSubscription(id).ensureSuccess() }

    suspend fun getGoogleAccounts(): List<GoogleAccount> = guarded { api.getGoogleAccounts() }

    suspend fun deleteGoogleAccount(id: Int) = guarded { api.deleteGoogleAccount(id).ensureSuccess() }

    suspend fun getHomeAssistantAccounts(): List<HomeAssistantAccount> =
        guarded { api.getHomeAssistantAccounts() }

    suspend fun addHomeAssistantAccount(name: String, url: String, token: String) =
        guarded {
            api.addHomeAssistantAccount(
                jsonBody("name" to name, "url" to url, "token" to token, "auth_method" to "token")
            )
        }

    suspend fun deleteHomeAssistantAccount(id: Int) =
        guarded { api.deleteHomeAssistantAccount(id).ensureSuccess() }

    /** Toggle a calendar's server-side visibility (caldav/google/homeassistant only). */
    suspend fun setCalendarSidebarHidden(source: String, calendarId: Int, hidden: Boolean) = guarded {
        val body = jsonBody("enabled" to !hidden, "sidebar_hidden" to hidden)
        when (source) {
            "caldav" -> api.updateCalDAVCalendar(calendarId, body).ensureSuccess()
            "google" -> api.updateGoogleCalendar(calendarId, body).ensureSuccess()
            "homeassistant" -> api.updateHACalendar(calendarId, body).ensureSuccess()
            else -> Unit
        }
    }

    /** Resolve all calendars the user can create events in. */
    suspend fun getWritableCalendars(): List<WritableCalendar> = withContext(Dispatchers.IO) {
        val result = mutableListOf<WritableCalendar>()
        runCatching { api.getLocalCalendars() }.getOrDefault(emptyList()).forEach { cal ->
            result += WritableCalendar("local-${cal.id}", cal.name, cal.color, "local", cal.id)
        }
        runCatching { api.getCalDAVAccounts() }.getOrDefault(emptyList())
            .filter { it.enabled }
            .forEach { acc ->
                acc.calendars.orEmpty().filter { it.enabled }.forEach { cal ->
                    result += WritableCalendar(
                        "caldav-${cal.id}", "${acc.name} – ${cal.name}",
                        cal.color ?: acc.color, "caldav", cal.id,
                    )
                }
            }
        runCatching { api.getGoogleAccounts() }.getOrDefault(emptyList()).forEach { acc ->
            acc.calendars.orEmpty().filter { it.enabled }.forEach { cal ->
                result += WritableCalendar(
                    "google-${cal.id}", "${acc.email} – ${cal.name}",
                    cal.color ?: "#4285f4", "google", cal.id,
                )
            }
        }
        runCatching { api.getHomeAssistantAccounts() }.getOrDefault(emptyList()).forEach { acc ->
            acc.calendars.orEmpty().filter { it.enabled }.forEach { cal ->
                result += WritableCalendar(
                    "ha-${cal.id}", "${acc.name} – ${cal.name}",
                    cal.color ?: "#46bdc6", "homeassistant", cal.id,
                )
            }
        }
        result
    }

    // ---- Events ----

    suspend fun fetchEvents(start: Instant, end: Instant): List<CalEvent> = withContext(Dispatchers.IO) {
        val resp = api.fetchEvents(Dates.isoUtc(start), Dates.isoUtc(end))
        resp.ensureSuccess()
        val raw = resp.body()?.string() ?: return@withContext emptyList()
        val root = JSONObject(raw)
        val arr = root.optJSONArray("events") ?: return@withContext emptyList()
        buildList {
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                CalEvent.fromJson(obj)?.let { add(it) }
            }
        }
    }

    suspend fun createLocalEvent(
        calendarId: Int, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String, color: String?,
    ) = guarded {
        api.createLocalEvent(eventBody(calendarId, title, start, end, isAllDay, location, description, color))
            .ensureSuccess()
    }

    suspend fun updateLocalEvent(
        uid: String, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String, color: String?,
    ) = guarded {
        api.updateLocalEvent(uid, eventBody(null, title, start, end, isAllDay, location, description, color))
            .ensureSuccess()
    }

    suspend fun deleteLocalEvent(uid: String) = guarded { api.deleteLocalEvent(uid).ensureSuccess() }

    suspend fun createCalDAVEvent(
        calendarId: Int, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String, color: String?,
    ) = guarded {
        api.createCalDAVEvent(eventBody(calendarId, title, start, end, isAllDay, location, description, color))
            .ensureSuccess()
    }

    suspend fun updateCalDAVEvent(
        uid: String, url: String, calendarId: Int?, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String, color: String?,
    ) = guarded {
        api.updateCalDAVEvent(
            uid, url, calendarId,
            eventBody(null, title, start, end, isAllDay, location, description, color),
        ).ensureSuccess()
    }

    suspend fun deleteCalDAVEvent(uid: String, url: String, calendarId: Int?) =
        guarded { api.deleteCalDAVEvent(uid, url, calendarId).ensureSuccess() }

    suspend fun createGoogleEvent(
        calendarDbId: Int, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String,
    ) = guarded {
        api.createGoogleEvent(
            jsonBody(
                "calendar_db_id" to calendarDbId, "title" to title,
                "start" to Dates.format(start, isAllDay), "end" to Dates.format(end, isAllDay),
                "allDay" to isAllDay, "location" to location, "description" to description,
            )
        ).ensureSuccess()
    }

    suspend fun createHAEvent(
        calendarId: Int, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String,
    ) = guarded {
        api.createHAEvent(
            jsonBody(
                "calendar_id" to calendarId, "title" to title,
                "start" to Dates.format(start, isAllDay), "end" to Dates.format(end, isAllDay),
                "allDay" to isAllDay, "location" to location, "description" to description,
            )
        ).ensureSuccess()
    }

    suspend fun deleteHAEvent(calendarId: Int, uid: String) =
        guarded { api.deleteHAEvent(calendarId, uid).ensureSuccess() }

    private fun eventBody(
        calendarId: Int?, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String, color: String?,
    ) = jsonBody(
        buildMap {
            calendarId?.let { put("calendar_id", it) }
            put("title", title)
            put("start", Dates.format(start, isAllDay))
            put("end", Dates.format(end, isAllDay))
            put("allDay", isAllDay)
            put("location", location)
            put("description", description)
            if (!color.isNullOrBlank()) put("color", color)
        }
    )
}
