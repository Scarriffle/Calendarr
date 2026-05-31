package com.scarriffle.calendarr.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.scarriffle.calendarr.domain.model.AppSettings
import com.scarriffle.calendarr.util.colorFromHex
import com.scarriffle.calendarr.util.contrastingTextColor

/**
 * The Calendarr brand accent — the green from the iOS `AccentColor` asset
 * (#20A050). This drives the global control tint (buttons, FAB, switches,
 * top bar) regardless of the server's per-calendar colours, matching iOS
 * where the app tint is fixed and `primary_color` only styles calendar
 * elements (e.g. the "today" highlight, read from [AppSettings]).
 */
val BrandGreen = Color(0xFF20A050)

@Composable
fun CalendarrTheme(
    settings: AppSettings = AppSettings(),
    content: @Composable () -> Unit,
) {
    val primary = BrandGreen

    val colors = darkColorScheme(
        primary = primary,
        onPrimary = primary.contrastingTextColor(),
        secondary = primary,
        onSecondary = primary.contrastingTextColor(),
        tertiary = primary,
        background = Color(0xFF000000),
        onBackground = Color(0xFFF2F2F7),
        surface = Color(0xFF1C1C1E),
        onSurface = Color(0xFFF2F2F7),
        surfaceVariant = Color(0xFF2C2C2E),
        onSurfaceVariant = Color(0xFFBEBEC4),
        outline = Color(0xFF3A3A3C),
    )

    MaterialTheme(
        colorScheme = colors,
        typography = Typography(),
        content = content,
    )
}
