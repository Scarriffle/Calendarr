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

    /** Persist locally immediately, then push the synced values to the server. */
    fun apply(settings: AppSettings, onSynced: () -> Unit) {
        settingsStore.saveSettings(settings)
        viewModelScope.launch {
            runCatching { repository.updateSettings(settings, settingsStore.loadSyncFlags()) }
            onSynced()
        }
    }

    // ---- Per-setting sync flags ----

    val syncableKeys: List<String> get() = settingsStore.syncableKeys
    var syncFlags by mutableStateOf(settingsStore.loadSyncFlags())
        private set

    /** Toggle one setting's flag. Enabling adopts this device's current value
     *  (pushes the synced values up); disabling keeps the value local. */
    fun toggleSync(key: String, current: AppSettings, onSynced: () -> Unit) {
        settingsStore.setSyncFlag(key, !(syncFlags[key] ?: false))
        syncFlags = settingsStore.loadSyncFlags()
        viewModelScope.launch { runCatching { repository.updateSettings(current, syncFlags) }; onSynced() }
    }

    /** Global "sync everything" switch. */
    fun setAllSync(on: Boolean, current: AppSettings, onSynced: () -> Unit) {
        settingsStore.setAllSyncFlags(on)
        syncFlags = settingsStore.loadSyncFlags()
        viewModelScope.launch { runCatching { repository.updateSettings(current, syncFlags) }; onSynced() }
    }

    // ---- Profile chapter (server-backed) ----

    var displayName by mutableStateOf("")
    var loginName by mutableStateOf("")
    var email by mutableStateOf("")
        private set
    var directoryHidden by mutableStateOf(false)
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
    fun onDirectoryHiddenChange(v: Boolean) { directoryHidden = v }

    private fun loadProfile() {
        viewModelScope.launch {
            runCatching { repository.getProfile() }.onSuccess { p ->
                displayName = p.displayName ?: p.username
                loginName = p.username
                email = p.email ?: ""
                directoryHidden = p.directoryHidden
            }
            runCatching { repository.getSettings() }.onSuccess { s ->
                privateVisibility = s.privateEventVisibility
                groupVisibleId = s.groupVisibleCalendarId ?: 0
            }
            runCatching { repository.getLocalCalendars() }.onSuccess { cals ->
                // A birthday calendar may be shared directly, but never stand in
                // as the group-visible personal calendar.
                ownLocalCalendars = cals.filter { it.owned && !it.group && !it.isBirthday }
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
                    directoryHidden = directoryHidden,
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
