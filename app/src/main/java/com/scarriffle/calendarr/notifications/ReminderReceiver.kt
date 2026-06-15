package com.scarriffle.calendarr.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.scarriffle.calendarr.R

/** Posts the reminder notification when an AlarmManager alarm fires. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        NotificationScheduler.ensureChannel(context)
        val title = intent.getStringExtra(NotificationScheduler.EXTRA_TITLE) ?: return
        val body = intent.getStringExtra(NotificationScheduler.EXTRA_BODY) ?: ""
        val id = intent.getIntExtra(NotificationScheduler.EXTRA_ID, 0)

        val notification = NotificationCompat.Builder(context, NotificationScheduler.CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        // notify() is a no-op (and may throw on some OEMs) without the runtime
        // POST_NOTIFICATIONS permission; ignore that case.
        try {
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (_: SecurityException) {
        }
    }
}
