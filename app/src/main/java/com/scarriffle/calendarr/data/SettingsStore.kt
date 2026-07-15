package com.scarriffle.calendarr.data

import android.content.Context
import android.content.SharedPreferences
import com.scarriffle.calendarr.domain.model.AppSettings
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Local persistence for cached appearance settings and the per-device
 * calendar visibility sets (hidden / banished). Mirrors the UserDefaults
 * usage in the iOS `CalendarStore`.
 */
@Singleton
class SettingsStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("calendarr_prefs", Context.MODE_PRIVATE)

    // --- Appearance settings cache (mirror of the server) ---

    fun loadSettings(): AppSettings = AppSettings(
        defaultView = prefs.getString(K_DEFAULT_VIEW, null) ?: "month",
        weekStartDay = prefs.getString(K_WEEK_START, null) ?: "monday",
        primaryColor = prefs.getString(K_PRIMARY, null) ?: "#4285f4",
        accentColor = prefs.getString(K_ACCENT, null) ?: "#ea4335",
        todayColor = prefs.getString(K_TODAY, null) ?: "#4285f4",
        dimPastEvents = prefs.getBoolean(K_DIM_PAST, false),
        textContrast = prefs.getInt(K_TEXT_CONTRAST, 3),
        lineContrast = prefs.getInt(K_LINE_CONTRAST, 3),
        hourHeight = prefs.getInt(K_HOUR_HEIGHT, 60),
        language = prefs.getString(K_LANGUAGE, null) ?: "de",
        monthDividerColor = prefs.getString(K_DIVIDER, null) ?: "#7090c0",
        monthLabelColor = prefs.getString(K_LABEL, null) ?: "#7090c0",
        textColor = prefs.getString(K_TEXT_COLOR, null) ?: "#FFFFFF",
        backgroundColor = prefs.getString(K_BG_COLOR, null) ?: "#000000",
        lineColor = prefs.getString(K_LINE_COLOR, null) ?: "#3A3A52",
        defaultReminderMinutes = prefs.getInt(K_DEFAULT_REMINDER, -1).takeIf { it >= 0 },
        defaultEventDurationMinutes = prefs.getInt(K_DEFAULT_DURATION, 60),
        cacheMonths = prefs.getInt(K_CACHE_MONTHS, 3),
        monthViewPaged = prefs.getBoolean(K_MONTH_PAGED, false),
    )

    fun saveSettings(s: AppSettings) {
        prefs.edit()
            .putString(K_DEFAULT_VIEW, s.defaultView)
            .putString(K_WEEK_START, s.weekStartDay)
            .putString(K_PRIMARY, s.primaryColor)
            .putString(K_ACCENT, s.accentColor)
            .putString(K_TODAY, s.todayColor)
            .putBoolean(K_DIM_PAST, s.dimPastEvents)
            .putInt(K_TEXT_CONTRAST, s.textContrast)
            .putInt(K_LINE_CONTRAST, s.lineContrast)
            .putInt(K_HOUR_HEIGHT, s.hourHeight)
            .putString(K_LANGUAGE, s.language)
            .putString(K_DIVIDER, s.monthDividerColor)
            .putString(K_LABEL, s.monthLabelColor)
            .putString(K_TEXT_COLOR, s.textColor)
            .putString(K_BG_COLOR, s.backgroundColor)
            .putString(K_LINE_COLOR, s.lineColor)
            .putInt(K_DEFAULT_REMINDER, s.defaultReminderMinutes ?: -1)
            .putInt(K_DEFAULT_DURATION, s.defaultEventDurationMinutes)
            .putInt(K_CACHE_MONTHS, s.cacheMonths)
            .putBoolean(K_MONTH_PAGED, s.monthViewPaged)
            .apply()
    }

    // --- Per-setting cross-device sync flags (account-wide; server is authority) ---

    /** Keys this Android client can sync. Excludes language (device "system" has
     *  no server value) and text/line contrast (iOS-style opacity, device-local). */
    val syncableKeys: List<String> = listOf(
        "default_view", "week_start_day", "dim_past_events", "hour_height",
        "default_event_duration_minutes", "default_reminder_minutes",
        "primary_color", "accent_color", "today_color",
        "text_color", "bg_color", "line_color",
        "month_divider_color", "month_label_color",
        "cache_months", "month_view_paged",
    )

    private val defaultSync: Map<String, Boolean> = syncableKeys.associateWith { key ->
        key != "cache_months" && key != "month_view_paged"
    }

    fun loadSyncFlags(): Map<String, Boolean> {
        val result = defaultSync.toMutableMap()
        val raw = prefs.getString(K_SYNC_FLAGS, null)
        if (!raw.isNullOrBlank()) {
            runCatching { org.json.JSONObject(raw) }.getOrNull()?.let { obj ->
                for (key in syncableKeys) if (obj.has(key)) result[key] = obj.getBoolean(key)
            }
        }
        return result
    }

    private fun writeSyncFlags(f: Map<String, Boolean>) {
        prefs.edit().putString(K_SYNC_FLAGS, org.json.JSONObject(f as Map<*, *>).toString()).apply()
    }

    fun storeServerFlags(server: Map<String, Boolean>?) {
        if (server == null) return
        val f = loadSyncFlags().toMutableMap()
        for (key in syncableKeys) server[key]?.let { f[key] = it }
        writeSyncFlags(f)
    }

    fun setSyncFlag(key: String, on: Boolean) {
        val f = loadSyncFlags().toMutableMap(); f[key] = on; writeSyncFlags(f)
    }

    fun setAllSyncFlags(on: Boolean) {
        val f = loadSyncFlags().toMutableMap(); for (key in syncableKeys) f[key] = on; writeSyncFlags(f)
    }

    /** Merge a server snapshot with local values honouring the (refreshed) flags:
     *  synced keys take the server value, others keep the local value. Persists
     *  the result and returns the effective settings. */
    fun applyServerPull(server: AppSettings): AppSettings {
        storeServerFlags(server.syncFlags)
        val flags = loadSyncFlags()
        val local = loadSettings()
        fun on(key: String) = flags[key] == true
        val eff = local.copy(
            defaultView = if (on("default_view")) server.defaultView else local.defaultView,
            weekStartDay = if (on("week_start_day")) server.weekStartDay else local.weekStartDay,
            dimPastEvents = if (on("dim_past_events")) server.dimPastEvents else local.dimPastEvents,
            hourHeight = if (on("hour_height")) server.hourHeight else local.hourHeight,
            defaultEventDurationMinutes = if (on("default_event_duration_minutes")) server.defaultEventDurationMinutes else local.defaultEventDurationMinutes,
            defaultReminderMinutes = if (on("default_reminder_minutes")) server.defaultReminderMinutes else local.defaultReminderMinutes,
            primaryColor = if (on("primary_color")) server.primaryColor else local.primaryColor,
            accentColor = if (on("accent_color")) server.accentColor else local.accentColor,
            todayColor = if (on("today_color")) server.todayColor else local.todayColor,
            textColor = if (on("text_color")) server.textColor else local.textColor,
            backgroundColor = if (on("bg_color")) server.backgroundColor else local.backgroundColor,
            lineColor = if (on("line_color")) server.lineColor else local.lineColor,
            monthDividerColor = if (on("month_divider_color")) server.monthDividerColor else local.monthDividerColor,
            monthLabelColor = if (on("month_label_color")) server.monthLabelColor else local.monthLabelColor,
            cacheMonths = if (on("cache_months")) server.cacheMonths else local.cacheMonths,
            monthViewPaged = if (on("month_view_paged")) server.monthViewPaged else local.monthViewPaged,
            // Device-local (never synced): language + contrast levels.
            language = local.language,
            textContrast = local.textContrast,
            lineContrast = local.lineContrast,
        )
        saveSettings(eff)
        return eff
    }

    /** Device-local cache range in months around today (default 3). */
    var cacheMonths: Int
        get() = prefs.getInt(K_CACHE_MONTHS, 3)
        set(value) = prefs.edit().putInt(K_CACHE_MONTHS, value).apply()

    /** Device-local: month view as horizontal paged (swipe) instead of the
     *  continuous vertical scroll feed (default false = scroll). */
    var monthViewPaged: Boolean
        get() = prefs.getBoolean(K_MONTH_PAGED, false)
        set(value) = prefs.edit().putBoolean(K_MONTH_PAGED, value).apply()

    /** Device-local: hide the top-bar menu button (drawer opens via edge-swipe). */
    var hideMenuButton: Boolean
        get() = prefs.getBoolean(K_HIDE_MENU, false)
        set(value) = prefs.edit().putBoolean(K_HIDE_MENU, value).apply()

    /** Whether this device mirrors its Contacts birthdays into the birthday calendar. */
    var birthdaysSyncEnabled: Boolean
        get() = prefs.getBoolean(K_BDAY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(K_BDAY_ENABLED, value).apply()

    /** Stable per-install id used to scope this device's contact-birthday rows. */
    val birthdaysDeviceId: String
        get() {
            prefs.getString(K_BDAY_DEVICE, null)?.let { return it }
            val id = java.util.UUID.randomUUID().toString()
            prefs.edit().putString(K_BDAY_DEVICE, id).apply()
            return id
        }

    // --- Hidden calendars ("source:id") ---

    var hiddenCalendarKeys: Set<String>
        get() = prefs.getStringSet(K_HIDDEN, emptySet())?.toSet() ?: emptySet()
        set(value) = prefs.edit().putStringSet(K_HIDDEN, value).apply()

    // --- Banished calendars ("source:id") ---

    var banishedCalendarKeys: Set<String>
        get() = prefs.getStringSet(K_BANISHED, emptySet())?.toSet() ?: emptySet()
        set(value) = prefs.edit().putStringSet(K_BANISHED, value).apply()

    // --- Reminder-disabled calendars ("source:id") ---
    // Mirrors the server's per-calendar `reminders_enabled` flag so the
    // notification scheduler can skip muted calendars without deleting any
    // event reminders.

    var reminderDisabledCalendarKeys: Set<String>
        get() = prefs.getStringSet(K_REMINDER_DISABLED, emptySet())?.toSet() ?: emptySet()
        set(value) = prefs.edit().putStringSet(K_REMINDER_DISABLED, value).apply()

    // --- Calendar display order ("source:id" keys), device-local (mirrors web cal_order) ---

    var calendarOrder: List<String>
        get() {
            val raw = prefs.getString(K_CAL_ORDER, null) ?: return emptyList()
            return runCatching {
                val arr = org.json.JSONArray(raw)
                (0 until arr.length()).map { arr.getString(it) }
            }.getOrDefault(emptyList())
        }
        set(value) = prefs.edit().putString(K_CAL_ORDER, org.json.JSONArray(value).toString()).apply()

    private companion object {
        const val K_DEFAULT_VIEW = "default_view"
        const val K_WEEK_START = "week_start_day"
        const val K_PRIMARY = "primary_color"
        const val K_ACCENT = "accent_color"
        const val K_TODAY = "today_color"
        const val K_DIM_PAST = "dim_past_events"
        const val K_TEXT_CONTRAST = "text_contrast"
        const val K_LINE_CONTRAST = "line_contrast"
        const val K_HOUR_HEIGHT = "hour_height"
        const val K_LANGUAGE = "language"
        const val K_DIVIDER = "month_divider_color"
        const val K_LABEL = "month_label_color"
        const val K_TEXT_COLOR = "text_color"
        const val K_BG_COLOR = "bg_color"
        const val K_LINE_COLOR = "line_color"
        const val K_SYNC_FLAGS = "sync_flags"
        const val K_DEFAULT_REMINDER = "default_reminder_minutes"
        const val K_DEFAULT_DURATION = "default_event_duration_minutes"
        const val K_CACHE_MONTHS = "cache_months"
        const val K_MONTH_PAGED = "month_view_paged"
        const val K_HIDE_MENU = "hide_menu_button"
        const val K_BDAY_ENABLED = "birthdays_sync_enabled"
        const val K_BDAY_DEVICE = "birthdays_device_id"
        const val K_HIDDEN = "hidden_calendar_keys"
        const val K_BANISHED = "banished_calendar_keys"
        const val K_REMINDER_DISABLED = "reminder_disabled_calendar_keys"
        const val K_CAL_ORDER = "calendar_order"
    }
}
