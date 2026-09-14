package com.scarriffle.calendarr.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.unit.dp
import com.scarriffle.calendarr.domain.model.AppSettings
import com.scarriffle.calendarr.util.colorFromHex
import com.scarriffle.calendarr.util.contrastingTextColor

/** Fallback brand accent (iOS `AccentColor` #20A050) used only when the user's
 *  primary colour is unset. */
val BrandGreen = Color(0xFF20A050)

/**
 * Fully dynamic theme: every colour is derived from [AppSettings] so the whole
 * app follows the user's palette (matching the web client). primary/accent tint
 * the controls; background/text/line drive `background`/`onBackground`/`outline`,
 * which the calendar views already read (grid, secondary text). "today", divider
 * and label colours are read directly in the views.
 */
@Composable
fun CalendarrTheme(
    settings: AppSettings = AppSettings(),
    content: @Composable () -> Unit,
) {
    val primary = colorFromHex(settings.primaryColor, BrandGreen)
    val accent = colorFromHex(settings.accentColor, primary)
    val bg = colorFromHex(settings.backgroundColor, Color(0xFF000000))
    val onBg = colorFromHex(settings.textColor, Color(0xFFF2F2F7))
    val line = colorFromHex(settings.lineColor, Color(0xFF3A3A52))

    val surface = lerp(bg, Color.White, 0.10f)
    val surfaceVariant = lerp(bg, Color.White, 0.17f)
    val container = lerp(primary, Color.Black, 0.55f)
    val onContainer = lerp(primary, Color.White, 0.75f)

    val colors = darkColorScheme(
        primary = primary,
        onPrimary = primary.contrastingTextColor(),
        primaryContainer = container,
        onPrimaryContainer = onContainer,
        secondary = accent,
        onSecondary = accent.contrastingTextColor(),
        secondaryContainer = container,
        onSecondaryContainer = onContainer,
        tertiary = accent,
        onTertiary = accent.contrastingTextColor(),
        tertiaryContainer = container,
        onTertiaryContainer = onContainer,
        surfaceTint = primary,
        background = bg,
        onBackground = onBg,
        surface = surface,
        onSurface = onBg,
        surfaceVariant = surfaceVariant,
        onSurfaceVariant = onBg.copy(alpha = 0.7f),
        outline = line,
    )

    MaterialTheme(
        colorScheme = colors,
        typography = Typography(),
        // extraSmall drives DropdownMenu containers (default 4dp looks boxy);
        // rounder popups to match the iOS look.
        shapes = Shapes(extraSmall = RoundedCornerShape(14.dp)),
        content = content,
    )
}
