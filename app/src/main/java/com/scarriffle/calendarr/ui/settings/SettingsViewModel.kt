package com.scarriffle.calendarr.ui.settings

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.data.SettingsStore
import com.scarriffle.calendarr.domain.model.AppSettings
import com.scarriffle.calendarr.domain.model.LocalCalendar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val repository: CalendarRepository,
    private val settingsStore: SettingsStore,
) : ViewModel() {

    /** Persist locally immediately, then sync to the server in the background. */
    fun apply(settings: AppSettings, onSynced: () -> Unit) {
        settingsStore.saveSettings(settings)
        viewModelScope.launch {
            runCatching { repository.updateSettings(settings) }
            onSynced()
        }
    }

    var cacheMonths: Int
        get() = settingsStore.cacheMonths
        set(value) { settingsStore.cacheMonths = value }

    // ---- Profile chapter (server-backed) ----

    var displayName by mutableStateOf("")
    var loginName by mutableStateOf("")
    var email by mutableStateOf("")
        private set
    var privateVisibility by mutableStateOf("busy")
        private set
    var groupVisibleId by mutableStateOf(0) // 0 = none
        private set
    var ownLocalCalendars by mutableStateOf<List<LocalCalendar>>(emptyList())
        private set
    var profileMessage by mutableStateOf<String?>(null)
        private set

    init { loadProfile() }

    fun onDisplayNameChange(v: String) { displayName = v }
    fun onEmailChange(v: String) { email = v }

    private fun loadProfile() {
        viewModelScope.launch {
            runCatching { repository.getProfile() }.onSuccess { p ->
                displayName = p.displayName ?: p.username
                loginName = p.username
                email = p.email ?: ""
            }
            runCatching { repository.getSettings() }.onSuccess { s ->
                privateVisibility = s.privateEventVisibility
                groupVisibleId = s.groupVisibleCalendarId ?: 0
            }
            runCatching { repository.getLocalCalendars() }.onSuccess { cals ->
                ownLocalCalendars = cals.filter { it.owned && !it.group }
            }
        }
    }

    fun saveProfile(savedLabel: String) {
        viewModelScope.launch {
            runCatching {
                repository.updateProfile(
                    displayName = displayName.trim().ifEmpty { null },
                    username = null,
                    email = email.trim(),
                )
            }
                .onSuccess { profileMessage = savedLabel }
                .onFailure { profileMessage = it.message }
        }
    }

    fun changePrivateVisibility(value: String) {
        privateVisibility = value
        viewModelScope.launch { runCatching { repository.updatePrivateVisibility(value) } }
    }

    fun changeGroupVisible(id: Int) {
        groupVisibleId = id
        viewModelScope.launch { runCatching { repository.updateGroupVisibleCalendar(id.takeIf { it != 0 }) } }
    }
}
