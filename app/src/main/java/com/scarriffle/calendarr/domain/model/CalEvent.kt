package com.scarriffle.calendarr.domain.model

import com.scarriffle.calendarr.util.Dates
import org.json.JSONObject
import java.time.Instant

/**
 * A unified calendar event, blended from all server sources
 * (local, caldav, google, ical, homeassistant). Mirrors iOS `CalEvent`.
 */
data class CalEvent(
    val id: String,
    val url: String,
    val title: String,
    val startDate: Instant,
    val endDate: Instant,
    val isAllDay: Boolean,
    val location: String,
    val notes: String,
    val color: String?,
    val calendarId: String,
    val calendarName: String,
    val calendarColor: String,
    val source: String,
) {
    /** Per-event override colour, falling back to the calendar's colour. */
    val effectiveColor: String get() = color?.takeIf { it.isNotBlank() } ?: calendarColor

    companion object {
        /** Parse one event object from the `/api/caldav/events` aggregate response. */
        fun fromJson(json: JSONObject): CalEvent? {
            val title = json.optString("title").takeIf { json.has("title") } ?: return null
            val startStr = json.optString("start").takeIf { json.has("start") } ?: return null
            val endStr = json.optString("end").takeIf { json.has("end") } ?: return null

            // id may be a String (local UUID) or an Int (CalDAV numeric)
            val id: String = when (val raw = json.opt("id")) {
                is String -> raw
                is Number -> raw.toString()
                else -> return null
            }

            val isAllDay = json.optBoolean("allDay", false)
            val start = Dates.parse(startStr, isAllDay) ?: return null
            val end = Dates.parse(endStr, isAllDay) ?: return null

            // calendar_id arrives as raw numeric (caldav) or "<source>-<id>" string
            val calendarId = when (val raw = json.opt("calendar_id")) {
                null, JSONObject.NULL -> ""
                else -> raw.toString()
            }

            val colorRaw = json.optString("color", "")
            return CalEvent(
                id = id,
                url = json.optString("url", ""),
                title = title,
                startDate = start,
                endDate = end,
                isAllDay = isAllDay,
                location = json.optString("location", ""),
                notes = json.optString("description", ""),
                color = colorRaw.takeIf { it.isNotBlank() },
                calendarId = calendarId,
                calendarName = json.optString("calendar_name", ""),
                calendarColor = json.optString("calendarColor", "#4285f4"),
                source = json.optString("source", "local"),
            )
        }
    }
}
