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
    /**
     * Per-event override colour, then the calendar's colour, then a stable
     * per-calendar palette colour (so events never collapse to one default).
     */
    val effectiveColor: String
        get() = color?.takeIf { it.isNotBlank() }
            ?: calendarColor.takeIf { it.isNotBlank() }
            ?: fallbackColorFor("$source:$calendarId")

    companion object {
        private val FALLBACK_PALETTE = listOf(
            "#34a853", "#4285f4", "#ea4335", "#fbbc05",
            "#46bdc6", "#9c27b0", "#ff7043", "#7090c0",
        )

        private fun fallbackColorFor(key: String): String {
            val idx = (key.hashCode().and(Int.MAX_VALUE)) % FALLBACK_PALETTE.size
            return FALLBACK_PALETTE[idx]
        }

        /**
         * Read a string field, treating JSON null correctly. Android's
         * [JSONObject.optString] returns the literal string "null" for a JSON
         * null value, which previously made every event blue (color "null" →
         * unparseable → fallback) and showed "null" for empty location/notes.
         */
        private fun JSONObject.strOrNull(key: String): String? {
            if (!has(key) || isNull(key)) return null
            return optString(key, "").takeIf { it.isNotBlank() && it != "null" }
        }

        /** Parse one event object from the `/api/caldav/events` aggregate response. */
        fun fromJson(json: JSONObject): CalEvent? {
            val title = json.strOrNull("title") ?: return null
            val startStr = json.strOrNull("start") ?: return null
            val endStr = json.strOrNull("end") ?: return null

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

            return CalEvent(
                id = id,
                url = json.strOrNull("url") ?: "",
                title = title,
                startDate = start,
                endDate = end,
                isAllDay = isAllDay,
                location = json.strOrNull("location") ?: "",
                notes = json.strOrNull("description") ?: "",
                color = json.strOrNull("color"),
                calendarId = calendarId,
                calendarName = json.strOrNull("calendar_name") ?: "",
                calendarColor = json.strOrNull("calendarColor") ?: "",
                source = json.strOrNull("source") ?: "local",
            )
        }
    }
}
