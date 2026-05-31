package com.scarriffle.calendarr.data

import kotlinx.coroutines.flow.MutableStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Shared startup readiness flag used to keep the system splash screen on screen
 * until the first events have loaded (so the app never appears mid-load).
 */
@Singleton
class StartupState @Inject constructor() {
    val ready = MutableStateFlow(false)
    fun markReady() { ready.value = true }
}
