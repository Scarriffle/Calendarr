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
            .apply()
    }

    /** Device-local cache range in months around today (default 3). */
    var cacheMonths: Int
        get() = prefs.getInt(K_CACHE_MONTHS, 3)
        set(value) = prefs.edit().putInt(K_CACHE_MONTHS, value).apply()

    // --- Hidden calendars ("source:id") ---

    var hiddenCalendarKeys: Set<String>
        get() = prefs.getStringSet(K_HIDDEN, emptySet())?.toSet() ?: emptySet()
        set(value) = prefs.edit().putStringSet(K_HIDDEN, value).apply()

    // --- Banished calendars ("source:id") ---

    var banishedCalendarKeys: Set<String>
        get() = prefs.getStringSet(K_BANISHED, emptySet())?.toSet() ?: emptySet()
        set(value) = prefs.edit().putStringSet(K_BANISHED, value).apply()

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
        const val K_CACHE_MONTHS = "cache_months"
        const val K_HIDDEN = "hidden_calendar_keys"
        const val K_BANISHED = "banished_calendar_keys"
    }
}
