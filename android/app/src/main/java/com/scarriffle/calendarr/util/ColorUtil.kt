package com.scarriffle.calendarr.util

import androidx.compose.ui.graphics.Color

/** Parse a "#RRGGBB" (or "RRGGBB") hex string into a Compose [Color]. */
fun colorFromHex(hex: String?, fallback: Color = Color(0xFF4285F4)): Color {
    if (hex.isNullOrBlank()) return fallback
    val clean = hex.trim().removePrefix("#").filter { it.isLetterOrDigit() }
    return when (clean.length) {
        3 -> runCatching {
            // #RGB shorthand -> expand each nibble
            val r = clean[0].digitToInt(16) * 17
            val g = clean[1].digitToInt(16) * 17
            val b = clean[2].digitToInt(16) * 17
            Color(r / 255f, g / 255f, b / 255f, 1f)
        }.getOrDefault(fallback)
        6 -> runCatching {
            val v = clean.toLong(16)
            Color(
                red = ((v shr 16) and 0xFF) / 255f,
                green = ((v shr 8) and 0xFF) / 255f,
                blue = (v and 0xFF) / 255f,
                alpha = 1f,
            )
        }.getOrDefault(fallback)
        8 -> runCatching {
            val v = clean.toLong(16)
            Color(
                alpha = ((v shr 24) and 0xFF) / 255f,
                red = ((v shr 16) and 0xFF) / 255f,
                green = ((v shr 8) and 0xFF) / 255f,
                blue = (v and 0xFF) / 255f,
            )
        }.getOrDefault(fallback)
        else -> fallback
    }
}

/** Convert a Compose [Color] back to a "#RRGGBB" string. */
fun Color.toHex(): String {
    val r = (red * 255).toInt().coerceIn(0, 255)
    val g = (green * 255).toInt().coerceIn(0, 255)
    val b = (blue * 255).toInt().coerceIn(0, 255)
    return String.format("#%02X%02X%02X", r, g, b)
}

/** Pick black or white text for legibility on a given background color. */
fun Color.contrastingTextColor(): Color {
    val luminance = 0.299 * red + 0.587 * green + 0.114 * blue
    return if (luminance > 0.6) Color.Black else Color.White
}
