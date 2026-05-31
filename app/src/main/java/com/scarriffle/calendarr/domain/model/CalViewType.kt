package com.scarriffle.calendarr.domain.model

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CalendarViewWeek
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.ViewList
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.ui.graphics.vector.ImageVector

enum class CalViewType(val key: String) {
    MONTH("month"),
    WEEK("week"),
    DAY("day"),
    QUARTER("quarter"),
    AGENDA("agenda");

    val icon: ImageVector
        get() = when (this) {
            MONTH -> Icons.Filled.CalendarMonth
            WEEK -> Icons.Filled.CalendarViewWeek
            DAY -> Icons.Filled.WbSunny
            QUARTER -> Icons.Filled.DateRange
            AGENDA -> Icons.Filled.ViewList
        }

    companion object {
        fun fromKey(key: String?): CalViewType =
            entries.firstOrNull { it.key == key } ?: MONTH
    }
}
