package com.scarriffle.calendarr.util

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Date parsing/formatting that mirrors the iOS client (CalEvent.swift).
 *
 * The backend may produce any of these forms:
 *   "2026-05-17"                    (all-day, date only)
 *   "2026-05-17T10:00:00Z"
 *   "2026-05-17T10:00:00+02:00"
 *   "2026-05-17T10:00:00.000Z"
 *   "2026-05-17T10:00:00"           (no timezone -> treat as UTC)
 *   "2026-05-17 10:00:00+00:00"     (Python isoformat, space separator)
 */
object Dates {

    private val zone: ZoneId get() = ZoneId.systemDefault()

    private val spaceSep: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ssXXX")
    private val noTz: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss")

    /** Parse a server date string into an [Instant]. Returns null if unparseable. */
    fun parse(raw: String, allDay: Boolean): Instant? {
        val s = raw.trim()
        if (s.isEmpty()) return null

        if (allDay || (s.length == 10 && !s.contains('T'))) {
            return runCatching {
                LocalDate.parse(s.take(10)).atStartOfDay(zone).toInstant()
            }.getOrNull()
        }
        // ISO with offset / Z
        runCatching { return OffsetDateTime.parse(s).toInstant() }
        runCatching { return Instant.parse(s) }
        // Python isoformat with a space
        runCatching { return OffsetDateTime.parse(s, spaceSep).toInstant() }
        // No timezone -> UTC
        runCatching {
            return LocalDateTime.parse(s.take(19), noTz).toInstant(ZoneOffset.UTC)
        }
        // Last resort: just the date part
        return runCatching {
            LocalDate.parse(s.take(10)).atStartOfDay(zone).toInstant()
        }.getOrNull()
    }

    /** Format an [Instant] for sending to the server. */
    fun format(instant: Instant, allDay: Boolean): String {
        return if (allDay) {
            LocalDate.ofInstant(instant, zone).toString() // yyyy-MM-dd
        } else {
            // ISO8601 with Z, no fractional seconds (matches iOS isoBasic)
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'")
                .withZone(ZoneOffset.UTC)
                .format(instant)
        }
    }

    /** ISO8601 UTC string used for the events query range (`?start=&end=`). */
    fun isoUtc(instant: Instant): String =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'")
            .withZone(ZoneOffset.UTC)
            .format(instant)

    fun localDate(instant: Instant): LocalDate = LocalDate.ofInstant(instant, zone)

    fun startOfDay(date: LocalDate): Instant = date.atStartOfDay(zone).toInstant()
}
