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
import com.scarriffle.calendarr.domain.model.CalendarShareEntry
import com.scarriffle.calendarr.domain.model.DirectoryUser
import com.scarriffle.calendarr.domain.model.Group
import com.scarriffle.calendarr.domain.model.GroupMember
import com.scarriffle.calendarr.domain.model.GoogleAccount
import com.scarriffle.calendarr.domain.model.HomeAssistantAccount
import com.scarriffle.calendarr.domain.model.ICalSubscription
import com.scarriffle.calendarr.domain.model.LocalCalendar
import com.scarriffle.calendarr.domain.model.UserProfile
import com.scarriffle.calendarr.domain.model.WritableCalendar
import com.scarriffle.calendarr.util.Dates
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
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

    /** Current logged-in user id (0 if unknown) — for creator/owner comparisons. */
    val currentUserId: Int get() = credentialStore.userId

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
        val uid = user?.optInt("id", 0) ?: 0
        val displayName = user?.optString("display_name")?.takeIf { it.isNotBlank() } ?: uname

        credentialStore.serverUrl = ApiProvider.normalize(baseUrl)
        credentialStore.saveLogin(token, uname, isAdmin, uid, displayName)
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
                "private_event_visibility" to s.privateEventVisibility,
                // Explicit JSON null clears it (off); jsonBody drops Kotlin nulls.
                "default_reminder_minutes" to (s.defaultReminderMinutes ?: org.json.JSONObject.NULL),
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

    /** Change a local calendar's colour. */
    suspend fun updateLocalCalendarColor(id: Int, color: String) = guarded {
        api.updateLocalCalendar(id, jsonBody("color" to color)).ensureSuccess()
    }

    /** Change an iCal subscription's colour. */
    suspend fun updateICalColor(id: Int, color: String) = guarded {
        api.updateICalSubscription(id, jsonBody("color" to color)).ensureSuccess()
    }

    /** Set a per-calendar colour for server-managed sources (caldav/google/homeassistant). */
    suspend fun setCalendarColor(source: String, calendarId: Int, color: String) = guarded {
        val body = jsonBody("color" to color)
        when (source) {
            "caldav" -> api.updateCalDAVCalendar(calendarId, body).ensureSuccess()
            "google" -> api.updateGoogleCalendar(calendarId, body).ensureSuccess()
            "homeassistant" -> api.updateHACalendar(calendarId, body).ensureSuccess()
            else -> Unit
        }
    }

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
        isPrivate: Boolean = false, reminders: List<Int>? = null,
    ) = guarded {
        api.createLocalEvent(eventBody(calendarId, title, start, end, isAllDay, location, description, color, isPrivate, reminders))
            .ensureSuccess()
    }

    suspend fun updateLocalEvent(
        uid: String, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String, color: String?,
        isPrivate: Boolean = false, reminders: List<Int>? = null,
    ) = guarded {
        api.updateLocalEvent(uid, eventBody(null, title, start, end, isAllDay, location, description, color, isPrivate, reminders))
            .ensureSuccess()
    }

    // ---- Sharing ----

    suspend fun getUserDirectory(): List<DirectoryUser> = guarded {
        val resp = api.getUserDirectory()
        resp.ensureSuccess()
        val arr = org.json.JSONArray(resp.body()?.string() ?: "[]")
        buildList {
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                add(DirectoryUser(o.optInt("id"), o.optString("display_name")))
            }
        }
    }

    suspend fun getShares(calendarId: Int): List<CalendarShareEntry> = guarded {
        val resp = api.getShares(calendarId)
        resp.ensureSuccess()
        val arr = org.json.JSONArray(resp.body()?.string() ?: "[]")
        buildList {
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                add(CalendarShareEntry(o.optInt("user_id"), o.optString("display_name"), o.optString("permission")))
            }
        }
    }

    suspend fun addShare(calendarId: Int, userId: Int, permission: String) = guarded {
        api.addShare(calendarId, jsonBody("user_id" to userId, "permission" to permission)).ensureSuccess()
    }

    suspend fun removeShare(calendarId: Int, userId: Int) = guarded {
        api.removeShare(calendarId, userId).ensureSuccess()
    }

    // ---- iCal import/export ----

    suspend fun importIcs(calendarId: Int, part: okhttp3.MultipartBody.Part): Triple<Int, Int, List<String>> = guarded {
        val resp = api.importCalendar(calendarId, part)
        resp.ensureSuccess()
        val o = JSONObject(resp.body()?.string() ?: "{}")
        val errors = o.optJSONArray("errors")
        val errList = buildList<String> { if (errors != null) for (i in 0 until errors.length()) add(errors.optString(i)) }
        Triple(o.optInt("imported"), o.optInt("skipped"), errList)
    }

    /** Build the multipart body from raw bytes and import (server form field: "file"). */
    suspend fun importIcsFile(calendarId: Int, bytes: ByteArray, filename: String): Triple<Int, Int, List<String>> {
        val body = bytes.toRequestBody("text/calendar".toMediaTypeOrNull())
        val part = okhttp3.MultipartBody.Part.createFormData("file", filename, body)
        return importIcs(calendarId, part)
    }

    suspend fun exportIcs(calendarId: Int): ByteArray = guarded {
        val resp = api.exportCalendar(calendarId)
        resp.ensureSuccess()
        resp.body()?.bytes() ?: ByteArray(0)
    }

    // ---- Groups ----

    suspend fun getGroups(): List<Group> = guarded {
        val resp = api.getGroups()
        resp.ensureSuccess()
        val arr = org.json.JSONArray(resp.body()?.string() ?: "[]")
        buildList {
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                add(Group(
                    id = o.optInt("id"),
                    name = o.optString("name"),
                    icon = if (o.isNull("icon")) null else o.optString("icon").ifBlank { null },
                    role = o.optString("role", "member"),
                    memberCount = o.optInt("member_count", 0),
                    groupCalendarId = if (o.isNull("group_calendar_id")) null else o.optInt("group_calendar_id"),
                    groupCalendarColor = if (o.isNull("group_calendar_color")) null else o.optString("group_calendar_color").ifBlank { null },
                    members = emptyList(),
                ))
            }
        }
    }

    suspend fun getGroup(id: Int): Group = guarded {
        val resp = api.getGroup(id)
        resp.ensureSuccess()
        val o = JSONObject(resp.body()?.string() ?: "{}")
        val membersArr = o.optJSONArray("members")
        val members = buildList<GroupMember> {
            if (membersArr != null) for (i in 0 until membersArr.length()) {
                val m = membersArr.optJSONObject(i) ?: continue
                add(GroupMember(
                    m.optInt("id"), m.optString("display_name"), m.optString("role", "member"),
                    if (m.isNull("color")) null else m.optString("color").ifBlank { null },
                ))
            }
        }
        Group(
            id = o.optInt("id"),
            name = o.optString("name"),
            icon = if (o.isNull("icon")) null else o.optString("icon").ifBlank { null },
            role = "",
            memberCount = members.size,
            groupCalendarId = if (o.isNull("group_calendar_id")) null else o.optInt("group_calendar_id"),
            groupCalendarColor = if (o.isNull("group_calendar_color")) null else o.optString("group_calendar_color").ifBlank { null },
            members = members,
        )
    }

    suspend fun createGroup(name: String, memberIds: List<Int>, icon: String?) = guarded {
        val arr = org.json.JSONArray()
        memberIds.forEach { arr.put(it) }
        api.createGroup(jsonBody("name" to name, "member_ids" to arr, "icon" to icon)).ensureSuccess()
    }

    suspend fun updateGroup(id: Int, name: String?, icon: String?) = guarded {
        api.updateGroup(id, jsonBody("name" to name, "icon" to icon)).ensureSuccess()
    }

    suspend fun addGroupMember(groupId: Int, userId: Int) = guarded {
        api.addGroupMember(groupId, jsonBody("user_id" to userId)).ensureSuccess()
    }

    suspend fun removeGroupMember(groupId: Int, userId: Int) = guarded {
        api.removeGroupMember(groupId, userId).ensureSuccess()
    }

    suspend fun setGroupMemberColor(groupId: Int, userId: Int, color: String) = guarded {
        api.setGroupMemberColor(groupId, userId, jsonBody("color" to color)).ensureSuccess()
    }

    suspend fun deleteGroup(id: Int) = guarded { api.deleteGroup(id).ensureSuccess() }

    // ---- Profile & targeted settings ----

    suspend fun updateProfile(displayName: String?, username: String?, email: String?): String? = guarded {
        val resp = api.updateProfile(jsonBody("display_name" to displayName, "username" to username, "email" to email))
        resp.ensureSuccess()
        runCatching { JSONObject(resp.body()?.string() ?: "{}").optString("access_token").ifBlank { null } }.getOrNull()
    }

    suspend fun updatePrivateVisibility(value: String) = guarded {
        api.updateSettings(jsonBody("private_event_visibility" to value)).ensureSuccess()
    }

    suspend fun updateGroupVisibleCalendar(calendarId: Int?) = guarded {
        // Send explicit JSON null to clear (jsonBody drops Kotlin nulls).
        api.updateSettings(jsonBody("group_visible_calendar_id" to (calendarId ?: org.json.JSONObject.NULL)))
            .ensureSuccess()
    }

    suspend fun fetchGroupCombined(groupId: Int, start: Instant, end: Instant): List<CalEvent> = withContext(Dispatchers.IO) {
        val resp = api.fetchGroupCombined(groupId, Dates.isoUtc(start), Dates.isoUtc(end))
        resp.ensureSuccess()
        val root = JSONObject(resp.body()?.string() ?: "{}")
        val arr = root.optJSONArray("events") ?: return@withContext emptyList()
        buildList {
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                CalEvent.fromJson(obj)?.let { add(it) }
            }
        }
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
        api.createGoogleEvent(simpleEventBody("calendar_db_id", calendarDbId, title, start, end, isAllDay, location, description))
            .ensureSuccess()
    }

    suspend fun updateGoogleEvent(
        gcalDbId: Int, eventId: String, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String,
    ) = guarded {
        api.updateGoogleEvent(gcalDbId, eventId, simpleEventBody(null, null, title, start, end, isAllDay, location, description))
            .ensureSuccess()
    }

    suspend fun deleteGoogleEvent(gcalDbId: Int, eventId: String) =
        guarded { api.deleteGoogleEvent(gcalDbId, eventId).ensureSuccess() }

    suspend fun createHAEvent(
        calendarId: Int, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String,
    ) = guarded {
        api.createHAEvent(simpleEventBody("calendar_id", calendarId, title, start, end, isAllDay, location, description))
            .ensureSuccess()
    }

    suspend fun updateHAEvent(
        calendarId: Int, uid: String, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String,
    ) = guarded {
        api.updateHAEvent(calendarId, uid, simpleEventBody(null, null, title, start, end, isAllDay, location, description))
            .ensureSuccess()
    }

    suspend fun deleteHAEvent(calendarId: Int, uid: String) =
        guarded { api.deleteHAEvent(calendarId, uid).ensureSuccess() }

    /** Body for Google/HA events (no per-event colour). */
    private fun simpleEventBody(
        calKey: String?, calId: Int?, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String,
    ) = jsonBody(
        buildMap {
            if (calKey != null && calId != null) put(calKey, calId)
            put("title", title)
            put("start", Dates.format(start, isAllDay))
            put("end", Dates.format(end, isAllDay))
            put("allDay", isAllDay)
            put("location", location)
            put("description", description)
        }
    )

    private fun eventBody(
        calendarId: Int?, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String, color: String?,
        isPrivate: Boolean = false, reminders: List<Int>? = null,
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
            put("private", isPrivate)
            if (reminders != null) put("reminders", org.json.JSONArray(reminders))
        }
    )
}
