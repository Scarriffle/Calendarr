package com.scarriffle.calendarr.domain.model

import com.scarriffle.calendarr.util.Dates
import org.json.JSONObject
import java.time.Instant

/**
 * A unified calendar event, blended from all server sources
 * (local, caldav, google, ical, homeassistant). Mirrors iOS `CalEvent`.
 */
/** Creator (or owner, in the group combined view) of an event. id is null for imported events. */
data class EventPerson(val id: Int?, val displayName: String)

/**
 * Read a string field, treating JSON null correctly. Android's
 * [JSONObject.optString] returns the literal string "null" for a JSON null
 * value, which previously made every event blue (color "null" → unparseable
 * → fallback) and showed "null" for empty location/notes.
 *
 * File-scope rather than inside CalEvent's companion, so EventAttachment can
 * use it as well.
 */
private fun JSONObject.strOrNull(key: String): String? {
    if (!has(key) || isNull(key)) return null
    return optString(key, "").takeIf { it.isNotBlank() && it != "null" }
}

/**
 * A file attached to an event. Mirrors iOS `EventAttachment`.
 */
data class EventAttachment(
    val id: Int,
    val filename: String,
    val contentType: String,
    val sizeBytes: Int,
    val hasThumbnail: Boolean,
    val uploadedBy: EventPerson? = null,
) {
    val isImage: Boolean get() = contentType.startsWith("image/")

    companion object {
        fun fromJson(json: JSONObject): EventAttachment? {
            val id = (json.opt("id") as? Number)?.toInt() ?: return null
            val filename = json.strOrNull("filename") ?: return null
            return EventAttachment(
                id = id,
                filename = filename,
                contentType = json.strOrNull("content_type") ?: "application/octet-stream",
                sizeBytes = json.optInt("size_bytes", 0),
                hasThumbnail = json.optBoolean("has_thumb", false),
                uploadedBy = json.optJSONObject("uploaded_by")?.let { obj ->
                    obj.strOrNull("display_name")?.let { name ->
                        EventPerson((obj.opt("id") as? Number)?.toInt(), name)
                    }
                },
            )
        }
    }
}

/**
 * A file picked in the editor but not uploaded yet. The bytes are read at pick
 * time (the content URI may not survive the save), and the event it belongs to
 * may not exist yet.
 */
data class StagedAttachment(
    val bytes: ByteArray,
    val filename: String,
    val mimeType: String?,
) {
    // ByteArray uses identity equality, so a data class holding one needs these
    // spelled out or two distinct picks of the same file compare unequal in a
    // list diff.
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is StagedAttachment) return false
        return filename == other.filename && mimeType == other.mimeType &&
            bytes.contentEquals(other.bytes)
    }

    override fun hashCode(): Int =
        31 * (31 * filename.hashCode() + (mimeType?.hashCode() ?: 0)) + bytes.contentHashCode()
}

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
    val creator: EventPerson? = null,
    val isPrivate: Boolean = false,
    // Only set in the group combined view:
    val owner: EventPerson? = null,
    val isGroupEvent: Boolean = false,
    val displayColor: String? = null,
    // Server-decorated title for the group combined view (group icon / owner
    // prefix); rendered in group mode while `title` stays raw for editing.
    val displayTitle: String? = null,
    // Reminder offsets in minutes-before-start (0 = at start). Local events only.
    val reminders: List<Int> = emptyList(),
    // True for events from a calendar shared with the user read-only.
    val readOnly: Boolean = false,
    // True for events from a birthday calendar — clients show a cake icon and
    // the server bakes the age into `displayTitle`.
    val isBirthday: Boolean = false,
    // How many files hang off this event. The list payload carries only the
    // count; the files themselves are fetched when the detail screen opens.
    // Absent on non-local sources and on busy-masked private events, so 0.
    val attachmentCount: Int = 0,
) {
    /**
     * Title to render: the server-decorated one (birthday age, group prefix)
     * wins over the raw title, which is kept for editing.
     */
    val renderTitle: String
        get() = displayTitle?.takeIf { it.isNotBlank() } ?: title
    /**
     * Group view supplies a server-resolved colour (display_color); otherwise
     * per-event override colour, then the calendar's colour, then a stable
     * per-calendar palette colour (so events never collapse to one default).
     */
    val effectiveColor: String
        get() = displayColor?.takeIf { it.isNotBlank() }
            ?: color?.takeIf { it.isNotBlank() }
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

        /** Parse a {id, display_name} person object (creator/owner). */
        private fun personFrom(json: JSONObject?, key: String): EventPerson? {
            val obj = json?.optJSONObject(key) ?: return null
            val name = obj.strOrNull("display_name") ?: return null
            val id = if (obj.isNull("id")) null else obj.opt("id")?.let {
                when (it) { is Number -> it.toInt(); is String -> it.toIntOrNull(); else -> null }
            }
            return EventPerson(id, name)
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
                creator = personFrom(json, "creator"),
                isPrivate = json.optBoolean("private", false),
                owner = personFrom(json, "owner"),
                isGroupEvent = json.optBoolean("is_group_event", false),
                displayColor = json.strOrNull("display_color"),
                displayTitle = json.strOrNull("display_title"),
                reminders = json.optJSONArray("reminders")?.let { arr ->
                    (0 until arr.length()).mapNotNull { (arr.opt(it) as? Number)?.toInt() }
                } ?: emptyList(),
                readOnly = json.optBoolean("read_only", false),
                isBirthday = json.optBoolean("is_birthday", false),
                attachmentCount = json.optInt("attachment_count", 0),
            )
        }
    }
}
