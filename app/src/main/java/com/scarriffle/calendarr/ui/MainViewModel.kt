package com.scarriffle.calendarr.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.data.CredentialStore
import com.scarriffle.calendarr.data.SettingsStore
import com.scarriffle.calendarr.data.remote.ApiProvider
import com.scarriffle.calendarr.domain.model.AppSettings
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class AppRoute { SETUP, LOGIN, MAIN }

@HiltViewModel
class MainViewModel @Inject constructor(
    private val credentialStore: CredentialStore,
    private val settingsStore: SettingsStore,
    private val repository: CalendarRepository,
    private val apiProvider: ApiProvider,
) : ViewModel() {

    private val _route = MutableStateFlow(computeRoute())
    val route: StateFlow<AppRoute> = _route.asStateFlow()

    private val _settings = MutableStateFlow(settingsStore.loadSettings())
    val settings: StateFlow<AppSettings> = _settings.asStateFlow()

    val serverUrl: String get() = credentialStore.serverUrl ?: ""
    val username: String get() = credentialStore.username ?: ""
    val isAdmin: Boolean get() = credentialStore.isAdmin

    init {
        if (_route.value == AppRoute.MAIN) refreshSettings()
    }

    private fun computeRoute(): AppRoute = when {
        !credentialStore.isConfigured -> AppRoute.SETUP
        !credentialStore.isLoggedIn -> AppRoute.LOGIN
        else -> AppRoute.MAIN
    }

    fun onServerConfigured() { _route.value = computeRoute() }

    fun onLoggedIn() {
        _route.value = AppRoute.MAIN
        refreshSettings()
    }

    fun logout() {
        credentialStore.clearToken()
        _route.value = computeRoute()
    }

    fun switchServer() {
        credentialStore.clearAll()
        apiProvider.invalidate()
        _route.value = computeRoute()
    }

    /** Pull settings from the server and merge them with local values honouring
     *  each setting's sync flag (synced keys take the server value). */
    fun refreshSettings() {
        viewModelScope.launch {
            runCatching { repository.getSettings() }.onSuccess { s ->
                _settings.value = settingsStore.applyServerPull(s)
            }
        }
    }

    fun applyLocalSettings(s: AppSettings) {
        settingsStore.saveSettings(s)
        _settings.value = s
    }
}
