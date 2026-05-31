package com.scarriffle.calendarr.ui.calendar

import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.domain.model.CalViewType
import com.scarriffle.calendarr.ui.L10n
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle

private val zone: ZoneId = ZoneId.systemDefault()

fun titleForView(viewType: CalViewType, date: LocalDate, lang: String): String {
    val loc = L10n.locale(lang)
    return when (viewType) {
        CalViewType.MONTH ->
            DateTimeFormatter.ofPattern("LLLL yyyy", loc).format(date)
                .replaceFirstChar { it.uppercase(loc) }
        CalViewType.QUARTER -> {
            val fmt = DateTimeFormatter.ofPattern("LLL yyyy", loc)
            "${fmt.format(date)} – ${fmt.format(date.plusMonths(2))}"
        }
        CalViewType.WEEK -> {
            val start = date
            val fmt = DateTimeFormatter.ofPattern("d. MMM", loc)
            val endFmt = DateTimeFormatter.ofPattern("d. MMM yyyy", loc)
            // Two lines for the compact top bar.
            "${fmt.format(start)} –\n${endFmt.format(start.plusDays(6))}"
        }
        CalViewType.DAY -> {
            val weekday = DateTimeFormatter.ofPattern("EEEE", loc).format(date)
            val rest = DateTimeFormatter.ofPattern("d. MMMM yyyy", loc).format(date)
            "$weekday\n$rest"
        }
        CalViewType.AGENDA -> L10n.t("view.agenda", lang)
    }
}

fun weekdayLabels(mondayFirst: Boolean, lang: String): List<String> {
    val loc = L10n.locale(lang)
    val order = if (mondayFirst) {
        listOf(1, 2, 3, 4, 5, 6, 7)
    } else {
        listOf(7, 1, 2, 3, 4, 5, 6)
    }
    return order.map {
        java.time.DayOfWeek.of(it).getDisplayName(TextStyle.SHORT, loc).take(2)
    }
}

fun timeLabel(instant: Instant, lang: String): String =
    DateTimeFormatter.ofPattern("HH:mm", L10n.locale(lang)).withZone(zone).format(instant)

/** Opacity for secondary text (week number, overflow count) per text_contrast 1..4. */
fun secondaryTextOpacity(contrast: Int): Float = when (contrast.coerceIn(1, 4)) {
    1 -> 0.40f
    2 -> 0.55f
    3 -> 0.72f
    else -> 0.92f
}

/** Opacity for regular grid lines per line_contrast 1..4. */
fun gridLineOpacity(contrast: Int): Float = when (contrast.coerceIn(1, 4)) {
    1 -> 0.15f
    2 -> 0.30f
    3 -> 0.50f
    else -> 0.80f
}

fun localTime(instant: Instant): LocalTime = LocalTime.ofInstant(instant, zone)

fun localDate(instant: Instant): LocalDate = LocalDate.ofInstant(instant, zone)

/** Minutes-from-midnight of the instant in the local zone. */
fun minutesOfDay(instant: Instant): Int {
    val t = localTime(instant)
    return t.hour * 60 + t.minute
}

fun eventTimeRange(event: CalEvent, lang: String): String {
    if (event.isAllDay) return L10n.t("cal.allday", lang)
    return "${timeLabel(event.startDate, lang)} – ${timeLabel(event.endDate, lang)}"
}

/** Full human-readable date (+time) range for the detail sheet. */
fun eventDateRange(event: CalEvent, lang: String): String {
    val loc = L10n.locale(lang)
    val dateFmt = DateTimeFormatter.ofPattern("EEE, d. MMM yyyy", loc)
    val startDate = localDate(event.startDate)
    val endDate = localDate(event.endDate)
    if (event.isAllDay) {
        // All-day end is exclusive on the server; show the inclusive last day.
        val lastDay = endDate.minusDays(1)
        return if (lastDay.isAfter(startDate)) {
            "${dateFmt.format(startDate)} – ${dateFmt.format(lastDay)}"
        } else {
            "${dateFmt.format(startDate)} · ${L10n.t("cal.allday", lang)}"
        }
    }
    return if (startDate == endDate) {
        "${dateFmt.format(startDate)}\n${timeLabel(event.startDate, lang)} – ${timeLabel(event.endDate, lang)}"
    } else {
        "${dateFmt.format(startDate)} ${timeLabel(event.startDate, lang)}\n– ${dateFmt.format(endDate)} ${timeLabel(event.endDate, lang)}"
    }
}
