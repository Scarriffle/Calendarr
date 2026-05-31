package com.scarriffle.calendarr

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import com.scarriffle.calendarr.data.CredentialStore
import com.scarriffle.calendarr.data.StartupState
import com.scarriffle.calendarr.ui.CalendarrRoot
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject lateinit var startupState: StartupState
    @Inject lateinit var credentialStore: CredentialStore

    override fun onCreate(savedInstanceState: Bundle?) {
        // Single, uniform splash: keep the system splash on screen until the
        // first events have loaded (or a timeout), so there is no two-stage
        // splash and no entering a half-loaded, janky app.
        val splash = installSplashScreen()
        splash.setKeepOnScreenCondition { !startupState.ready.value }

        super.onCreate(savedInstanceState)

        // Nothing to load before login → reveal immediately.
        if (!credentialStore.isLoggedIn) startupState.markReady()
        // Safety timeout so the splash can never hang.
        lifecycleScope.launch { delay(6000); startupState.markReady() }

        setContent {
            CalendarrRoot()
        }
    }
}
