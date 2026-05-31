package com.scarriffle.calendarr

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.scarriffle.calendarr.ui.CalendarrRoot
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Covers the window from the first frame (no warm-start flash), then
        // hands off to the in-app splash which stays until data is loaded.
        installSplashScreen()
        super.onCreate(savedInstanceState)
        setContent {
            CalendarrRoot()
        }
    }
}
