package com.scarriffle.calendarr

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.scarriffle.calendarr.ui.CalendarrRoot
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Covers the window from the first frame (incl. warm-start), then hands
        // off to the in-app branded splash which stays until data is loaded.
        installSplashScreen()
        // Draw edge-to-edge so system-bar insets reach every window, including
        // ModalBottomSheets — otherwise navigationBarsPadding() inside the sheets
        // resolves to 0 and the bottom menu rows hide behind the nav bar.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            CalendarrRoot()
        }
    }
}
