package com.scarriffle.calendarr.domain.model

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = false)
data class CalDAVAccount(
    val id: Int,
    val name: String = "",
    val url: String = "",
    val username: String = "",
    val color: String = "#4285f4",
    val enabled: Boolean = true,
    val calendars: List<CalDAVCalendar>? = null,
)

@JsonClass(generateAdapter = false)
data class CalDAVCalendar(
    val id: Int,
    val name: String = "",
    val color: String? = null,
    val enabled: Boolean = true,
    @Json(name = "sidebar_hidden") val sidebarHidden: Boolean = false,
)

@JsonClass(generateAdapter = false)
data class LocalCalendar(
    val id: Int,
    val name: String = "",
    val color: String = "#34a853",
    val enabled: Boolean = true,
    val type: String = "local",
    val owned: Boolean = true,
    @Json(name = "shared_by") val sharedBy: String? = null,
    val permission: String? = null,
    val group: Boolean = false,
)

@JsonClass(generateAdapter = false)
data class ICalSubscription(
    val id: Int,
    val name: String = "",
    val url: String = "",
    val color: String = "#46bdc6",
    val enabled: Boolean = true,
    @Json(name = "refresh_minutes") val refreshMinutes: Int = 60,
    @Json(name = "last_fetched") val lastFetched: String? = null,
)

@JsonClass(generateAdapter = false)
data class GoogleAccount(
    val id: Int,
    val email: String = "",
    val calendars: List<GoogleCalendar>? = null,
)

@JsonClass(generateAdapter = false)
data class GoogleCalendar(
    val id: Int,
    val name: String = "",
    val color: String? = null,
    val enabled: Boolean = true,
    @Json(name = "sidebar_hidden") val sidebarHidden: Boolean = false,
)

@JsonClass(generateAdapter = false)
data class HomeAssistantAccount(
    val id: Int,
    val name: String = "",
    val url: String = "",
    @Json(name = "auth_method") val authMethod: String = "token",
    val calendars: List<HACalendar>? = null,
)

@JsonClass(generateAdapter = false)
data class HACalendar(
    val id: Int,
    val name: String = "",
    @Json(name = "entity_id") val entityId: String = "",
    val color: String? = null,
    val enabled: Boolean = true,
    @Json(name = "sidebar_hidden") val sidebarHidden: Boolean = false,
)

@JsonClass(generateAdapter = false)
data class UserProfile(
    val id: Int,
    val username: String = "",
    @Json(name = "display_name") val displayName: String? = null,
    val email: String? = null,
    @Json(name = "is_admin") val isAdmin: Boolean = false,
    @Json(name = "has_avatar") val hasAvatar: Boolean = false,
    @Json(name = "totp_enabled") val totpEnabled: Boolean = false,
)

/** A calendar the user can create events in (resolved from all writable sources). */
data class WritableCalendar(
    val id: String,
    val name: String,
    val color: String,
    val source: String,
    val numericId: Int,
)
