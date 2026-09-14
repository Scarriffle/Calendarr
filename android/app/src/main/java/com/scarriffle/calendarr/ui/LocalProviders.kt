package com.scarriffle.calendarr.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.staticCompositionLocalOf
import com.scarriffle.calendarr.domain.model.AppSettings

/** Resolved UI language ("de" / "en"), provided at the root. */
val LocalLang = compositionLocalOf { "de" }

/** Current appearance settings, provided at the root. */
val LocalAppSettings = staticCompositionLocalOf { AppSettings() }

/** Convenience translation lookup that reads the ambient language. */
@Composable
@ReadOnlyComposable
fun tr(key: String): String = L10n.t(key, LocalLang.current)

@Composable
@ReadOnlyComposable
fun tr(key: String, vararg args: Any): String = L10n.t(key, LocalLang.current, *args)
