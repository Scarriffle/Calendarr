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
) {
    val weekStartsOnMonday: Boolean get() = weekStartDay != "sunday"
}
