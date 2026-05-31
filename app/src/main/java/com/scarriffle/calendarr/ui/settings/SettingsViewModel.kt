package com.scarriffle.calendarr.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.data.SettingsStore
import com.scarriffle.calendarr.domain.model.AppSettings
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
}
