package com.scarriffle.calendarr.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.scarriffle.calendarr.ui.auth.LoginScreen
import com.scarriffle.calendarr.ui.auth.ServerSetupScreen
import com.scarriffle.calendarr.ui.calendar.CalendarScreen
import com.scarriffle.calendarr.ui.theme.CalendarrTheme

@Composable
fun CalendarrRoot(vm: MainViewModel = hiltViewModel()) {
    val route by vm.route.collectAsState()
    val settings by vm.settings.collectAsState()

    var showSplash by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(1200)
        showSplash = false
    }

    CalendarrTheme(settings) {
        CompositionLocalProvider(
            LocalLang provides L10n.resolved(settings.language),
            LocalAppSettings provides settings,
        ) {
            Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                if (showSplash) {
                    SplashScreen()
                    return@Surface
                }
                when (route) {
                    AppRoute.SETUP -> ServerSetupScreen(onConfigured = vm::onServerConfigured)
                    AppRoute.LOGIN -> LoginScreen(
                        serverUrl = vm.serverUrl,
                        onLoggedIn = vm::onLoggedIn,
                        onBack = vm::switchServer,
                    )
                    AppRoute.MAIN -> CalendarScreen(
                        onLogout = vm::logout,
                        onSwitchServer = vm::switchServer,
                        onSettingsChanged = vm::applyLocalSettings,
                        onSettingsSynced = vm::refreshSettings,
                    )
                }
            }
        }
    }
}
