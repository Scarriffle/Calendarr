package com.scarriffle.calendarr.domain.model

/**
 * Reminder offsets are stored as minutes-before-start integers (0 = at start).
 * A few quick presets are offered; anything else is entered as a custom
 * number + unit. Mirrors the iOS `ReminderOptions`.
 */
object ReminderOptions {
    /** Quick presets: at start, 30 min, 1 day. */
    val presets = listOf(0, 30, 1440)

    /** Default for a freshly-switched custom row (deliberately not a preset). */
    const val customDefault = 120

    enum class Unit(val mult: Int, val labelKey: String) {
        MINUTES(1, "event.reminder_unit.minutes"),
        HOURS(60, "event.reminder_unit.hours"),
        DAYS(1440, "event.reminder_unit.days"),
        WEEKS(10080, "event.reminder_unit.weeks"),
    }

    /** Split a minutes value into the largest exact {value, unit} for the custom picker. */
    fun split(minutes: Int): Pair<Int, Unit> {
        for (u in Unit.values().reversed()) {
            if (minutes > 0 && minutes % u.mult == 0) return (minutes / u.mult) to u
        }
        return maxOf(1, minutes) to Unit.MINUTES
    }
}
