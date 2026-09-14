package com.scarriffle.calendarr.domain.model

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

/**
 * User appearance / behaviour settings, synced with the server.
 * Mirrors iOS `AppSettings`. Missing keys fall back to the defaults below
 * (the server only persists a subset).
 */
@JsonClass(generateAdapter = false)
data class AppSettings(
    @Json(name = "default_view") val defaultView: String = "month",
    @Json(name = "week_start_day") val weekStartDay: String = "monday",
    @Json(name = "primary_color") val primaryColor: String = "#4285f4",
    @Json(name = "accent_color") val accentColor: String = "#ea4335",
    @Json(name = "today_color") val todayColor: String = "#4285f4",
    @Json(name = "dim_past_events") val dimPastEvents: Boolean = false,
    @Json(name = "text_contrast") val textContrast: Int = 3,
    @Json(name = "line_contrast") val lineContrast: Int = 3,
    @Json(name = "hour_height") val hourHeight: Int = 60,
    @Json(name = "language") val language: String = "de",
    @Json(name = "month_divider_color") val monthDividerColor: String = "#7090c0",
    @Json(name = "month_label_color") val monthLabelColor: String = "#7090c0",
    // Text / background / line colours drive the Material theme (onBackground,
    // background, outline) so the whole app follows them, matching web/iOS.
    @Json(name = "text_color") val textColor: String = "#FFFFFF",
    @Json(name = "bg_color") val backgroundColor: String = "#000000",
    @Json(name = "line_color") val lineColor: String = "#3A3A52",
    // How this user's private events appear to other group members: 'hidden' | 'busy'.
    @Json(name = "private_event_visibility") val privateEventVisibility: String = "busy",
    @Json(name = "group_visible_calendar_id") val groupVisibleCalendarId: Int? = null,
    // Minutes-before-start applied to all events client-side; null = off.
    @Json(name = "default_reminder_minutes") val defaultReminderMinutes: Int? = null,
    // Duration (minutes) applied to a newly created event's end time.
    @Json(name = "default_event_duration_minutes") val defaultEventDurationMinutes: Int = 60,
    // Preload range in months (device-local by default) and month-view paging.
    @Json(name = "cache_months") val cacheMonths: Int = 3,
    @Json(name = "month_view_paged") val monthViewPaged: Boolean = false,
    // Account-wide per-setting sync flags, fully resolved by the server.
    @Json(name = "sync_flags") val syncFlags: Map<String, Boolean>? = null,
) {
    val weekStartsOnMonday: Boolean get() = weekStartDay != "sunday"
}
