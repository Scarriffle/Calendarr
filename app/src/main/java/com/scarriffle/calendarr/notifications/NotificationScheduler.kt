package com.scarriffle.calendarr.notifications

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.scarriffle.calendarr.domain.model.CalEvent
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

    private data class Pending(val fire: Long, val title: String, val body: String)

    fun reschedule(
        context: Context,
        events: List<CalEvent>,
        disabledKeys: Set<String>,
        defaultMinutes: Int,
    ) {
        ensureChannel(context)
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()

        val pending = mutableListOf<Pending>()
        for (ev in events) {
            if (disabledKeys.contains(calendarKey(ev.source, ev.calendarId))) continue
            val offsets = if (ev.reminders.isEmpty()) {
                if (defaultMinutes >= 0) listOf(defaultMinutes) else emptyList()
            } else ev.reminders
            for (m in offsets) {
                val fire = ev.startDate.toEpochMilli() - m * 60_000L
                if (fire > now) pending.add(Pending(fire, ev.title, ev.location))
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
