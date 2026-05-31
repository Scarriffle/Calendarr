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
 * The Calendarr UI is a dark theme whose accent colours follow the user's
 * synced [AppSettings] (mirrors the iOS appearance settings).
 */
@Composable
fun CalendarrTheme(
    settings: AppSettings = AppSettings(),
    content: @Composable () -> Unit,
) {
    val primary = colorFromHex(settings.primaryColor, Color(0xFF4285F4))
    val accent = colorFromHex(settings.accentColor, Color(0xFFEA4335))

    val colors = darkColorScheme(
        primary = primary,
        onPrimary = primary.contrastingTextColor(),
        secondary = accent,
        onSecondary = accent.contrastingTextColor(),
        tertiary = accent,
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
