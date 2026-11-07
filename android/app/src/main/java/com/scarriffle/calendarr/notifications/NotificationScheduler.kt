package com.scarriffle.calendarr.notifications

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.scarriffle.calendarr.domain.model.CalEvent
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import com.scarriffle.calendarr.ui.calendar.calendarKey

/**
 * Schedules OS reminder notifications for upcoming events via AlarmManager.
 * Per-event reminders take precedence; otherwise the user's default reminder
 * applies. Calendars the user muted (`disabledKeys`) are skipped — their
 * reminders are kept on the events, just never fired. Mirrors the iOS
 * `NotificationScheduler`.
 */
object NotificationScheduler {
    const val CHANNEL_ID = "calendarr_reminders"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_ID = "id"

    private const val PREFS = "calendarr_reminders_sched"
    private const val KEY_COUNT = "scheduled_count"
    private const val MAX = 50  // keep the alarm count bounded

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = context.getSystemService(NotificationManager::class.java)
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                mgr.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Reminders", NotificationManager.IMPORTANCE_HIGH)
                )
            }
        }
    }

    // Known limit: alarms do not survive a reboot. They are only re-registered
    // when the calendar screen opens, and there is no local event cache to
    // rebuild them from at boot — a BOOT_COMPLETED receiver would have to reach
    // the server before the user has unlocked the device. Matters most for
    // all-day reminders, which are set days ahead.
    private data class Pending(val fire: Long, val title: String, val body: String)

    fun reschedule(
        context: Context,
        events: List<CalEvent>,
        disabledKeys: Set<String>,
        defaultMinutes: Int,
        allDayDays: Int = -1,
        allDayTime: String = "09:00",
    ) {
        ensureChannel(context)
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()

        val pending = mutableListOf<Pending>()
        for (ev in events) {
            if (disabledKeys.contains(calendarKey(ev.source, ev.calendarId))) continue
            val fallback = if (ev.isAllDay) allDayDays * 1440 else defaultMinutes
            val enabled = if (ev.isAllDay) allDayDays >= 0 else defaultMinutes >= 0
            val offsets = if (ev.reminders.isEmpty()) {
                if (enabled) listOf(fallback) else emptyList()
            } else ev.reminders
            for (m in offsets) {
                val fire = fireAt(ev, m, allDayTime)
                if (fire > now) {
                    val rel = if (ev.isAllDay) allDayRelativeText(fire, ev.startDate.toEpochMilli())
                              else relativeText(m)
                    val body = if (ev.location.isNotBlank()) "$rel · ${ev.location}" else rel
                    pending.add(Pending(fire, ev.title, body))
                }
            }
        }
        pending.sortBy { it.fire }
        val limited = pending.take(MAX)

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val lastCount = prefs.getInt(KEY_COUNT, 0)
        // Cancel every alarm from the previous run (extras are ignored when
        // matching a PendingIntent, so a bare intent with the same code cancels).
        for (i in 0 until maxOf(lastCount, limited.size)) {
            am.cancel(intentFor(context, i, null))
        }
        limited.forEachIndexed { i, p ->
            val pi = intentFor(context, i, p)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, p.fire, pi)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, p.fire, pi)
            }
        }
        prefs.edit().putInt(KEY_COUNT, limited.size).apply()
    }

    /**
     * When a reminder fires.
     *
     * An all-day event starts at local midnight, so a minute offset puts the
     * reminder in the middle of the night — 30 minutes before becomes 23:30.
     * For those the offset is read as whole days instead, fired at a configured
     * time of day. Birthday calendars inherit that for free: the offsets the
     * server injects for them are always multiples of 1440.
     */
    private fun fireAt(ev: CalEvent, minutes: Int, allDayTime: String): Long {
        if (!ev.isAllDay) return ev.startDate.toEpochMilli() - minutes * 60_000L
        val zone = ZoneId.systemDefault()
        val days = Math.round(minutes / 1440.0).toInt()
        val parts = allDayTime.split(":")
        val hour = parts.getOrNull(0)?.toIntOrNull()?.coerceIn(0, 23) ?: 9
        val minute = parts.getOrNull(1)?.toIntOrNull()?.coerceIn(0, 59) ?: 0
        return ev.startDate.atZone(zone).toLocalDate()
            .minusDays(days.toLong())
            .atTime(hour, minute)
            .atZone(zone).toInstant().toEpochMilli()
    }

    /** "heute" / "morgen" / "in N Tagen" — counted in days, not in minutes. */
    private fun allDayRelativeText(fire: Long, start: Long): String {
        val zone = ZoneId.systemDefault()
        val days = ChronoUnit.DAYS.between(
            Instant.ofEpochMilli(fire).atZone(zone).toLocalDate(),
            Instant.ofEpochMilli(start).atZone(zone).toLocalDate(),
        )
        return when {
            days < 1L -> "heute"
            days == 1L -> "morgen"
            else -> "in $days Tagen"
        }
    }

    private fun relativeText(minutes: Int): String = when {
        minutes < 60   -> "in $minutes Min."
        minutes == 60  -> "in 1 Std."
        minutes < 1440 -> "in ${minutes / 60} Std."
        minutes == 1440 -> "morgen"
        else            -> "in ${minutes / 1440} Tagen"
    }

    private fun intentFor(context: Context, code: Int, p: Pending?): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).apply {
            // Distinct action per code so PendingIntents don't collapse together.
            action = "com.scarriffle.calendarr.REMINDER_$code"
            if (p != null) {
                putExtra(EXTRA_ID, code)
                putExtra(EXTRA_TITLE, p.title)
                putExtra(EXTRA_BODY, p.body)
            }
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, code, intent, flags)
    }
}
