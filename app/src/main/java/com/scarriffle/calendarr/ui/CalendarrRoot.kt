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
import com.scarriffle.calendarr.ui.calendar.CalendarViewModel
import com.scarriffle.calendarr.ui.theme.CalendarrTheme
import kotlinx.coroutines.delay

@Composable
fun CalendarrRoot(vm: MainViewModel = hiltViewModel()) {
    val route by vm.route.collectAsState()
    val settings by vm.settings.collectAsState()

    CalendarrTheme(settings) {
        CompositionLocalProvider(
            LocalLang provides L10n.resolved(settings.language),
            LocalAppSettings provides settings,
        ) {
            Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                // Obtain the calendar VM early when logged in so events load
                // *behind* the splash; the branded splash stays until ready.
                val calendarVm: CalendarViewModel? =
                    if (route == AppRoute.MAIN) hiltViewModel() else null
                val dataReady = calendarVm?.ready?.collectAsState()?.value ?: true

                var minElapsed by remember { mutableStateOf(false) }
                var timedOut by remember { mutableStateOf(false) }
                LaunchedEffect(Unit) { delay(500); minElapsed = true }
                LaunchedEffect(Unit) { delay(6000); timedOut = true }

                if (!minElapsed || (!dataReady && !timedOut)) {
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
                    AppRoute.MAIN -> calendarVm?.let { cvm ->
                        CalendarScreen(
                            vm = cvm,
                            onLogout = vm::logout,
                            onSwitchServer = vm::switchServer,
                            onSettingsChanged = vm::applyLocalSettings,
                            onSettingsSynced = vm::refreshSettings,
                        )
                    } ?: SplashScreen()
                }
            }
        }
    }
}
