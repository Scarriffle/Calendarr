package com.scarriffle.calendarr.ui.accounts

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.domain.model.CalDAVAccount
import com.scarriffle.calendarr.domain.model.CalendarShareEntry
import com.scarriffle.calendarr.domain.model.DirectoryUser
import com.scarriffle.calendarr.domain.model.GoogleAccount
import com.scarriffle.calendarr.domain.model.HomeAssistantAccount
import com.scarriffle.calendarr.domain.model.ICalSubscription
import com.scarriffle.calendarr.domain.model.LocalCalendar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class AccountsViewModel @Inject constructor(
    private val repository: CalendarRepository,
) : ViewModel() {

    var loading by mutableStateOf(true)
        private set
    var error by mutableStateOf<String?>(null)
        private set

    var caldav by mutableStateOf<List<CalDAVAccount>>(emptyList())
        private set
    var local by mutableStateOf<List<LocalCalendar>>(emptyList())
        private set
    var ical by mutableStateOf<List<ICalSubscription>>(emptyList())
        private set
    var google by mutableStateOf<List<GoogleAccount>>(emptyList())
        private set
    var homeAssistant by mutableStateOf<List<HomeAssistantAccount>>(emptyList())
        private set

    init { load() }

    fun load() {
        viewModelScope.launch {
            loading = true
            error = null
            caldav = runCatching { repository.getCalDAVAccounts() }.getOrDefault(emptyList())
            local = runCatching { repository.getLocalCalendars() }.getOrDefault(emptyList())
            ical = runCatching { repository.getICalSubscriptions() }.getOrDefault(emptyList())
            google = runCatching { repository.getGoogleAccounts() }.getOrDefault(emptyList())
            homeAssistant = runCatching { repository.getHomeAssistantAccounts() }.getOrDefault(emptyList())
            loading = false
        }
    }

    private fun mutate(onChanged: () -> Unit, block: suspend () -> Unit) {
        viewModelScope.launch {
            runCatching { block() }
                .onSuccess { load(); onChanged() }
                .onFailure { error = it.message }
        }
    }

    fun addLocal(name: String, color: String, onChanged: () -> Unit) =
        mutate(onChanged) { repository.addLocalCalendar(name, color) }

    fun deleteLocal(id: Int, onChanged: () -> Unit) =
        mutate(onChanged) { repository.deleteLocalCalendar(id) }

    fun addCalDAV(name: String, url: String, user: String, pass: String, color: String, onChanged: () -> Unit) =
        mutate(onChanged) { repository.addCalDAVAccount(name, url, user, pass, color) }

    fun deleteCalDAV(id: Int, onChanged: () -> Unit) =
        mutate(onChanged) { repository.deleteCalDAVAccount(id) }

    fun addICal(name: String, url: String, color: String, refreshMinutes: Int, onChanged: () -> Unit) =
        mutate(onChanged) { repository.addICalSubscription(name, url, color, refreshMinutes) }

    fun deleteICal(id: Int, onChanged: () -> Unit) =
        mutate(onChanged) { repository.deleteICalSubscription(id) }

    fun addHA(name: String, url: String, token: String, onChanged: () -> Unit) =
        mutate(onChanged) { repository.addHomeAssistantAccount(name, url, token) }

    fun deleteHA(id: Int, onChanged: () -> Unit) =
        mutate(onChanged) { repository.deleteHomeAssistantAccount(id) }

    fun deleteGoogle(id: Int, onChanged: () -> Unit) =
        mutate(onChanged) { repository.deleteGoogleAccount(id) }

    // ---- Calendar colour ----

    fun setLocalColor(id: Int, color: String, onChanged: () -> Unit) =
        mutate(onChanged) { repository.updateLocalCalendarColor(id, color) }

    fun setICalColor(id: Int, color: String, onChanged: () -> Unit) =
        mutate(onChanged) { repository.updateICalColor(id, color) }

    fun setSourceColor(source: String, calendarId: Int, color: String, onChanged: () -> Unit) =
        mutate(onChanged) { repository.setCalendarColor(source, calendarId, color) }

    // ---- Banished (permanently hidden) calendars ----

    /** Lift the server-side sidebar_hidden flag so a banished calendar reappears.
     *  `onChanged` triggers the calendar screen's reconcile + refetch. */
    fun unbanishCalendar(source: String, calendarId: Int, onChanged: () -> Unit) =
        mutate(onChanged) { repository.setCalendarSidebarHidden(source, calendarId, hidden = false) }

    // ---- Sharing ----

    var shares by mutableStateOf<List<CalendarShareEntry>>(emptyList())
        private set
    var directory by mutableStateOf<List<DirectoryUser>>(emptyList())
        private set

    fun loadSharing(calendarId: Int) {
        viewModelScope.launch {
            shares = runCatching { repository.getShares(calendarId) }.getOrDefault(emptyList())
            directory = runCatching { repository.getUserDirectory() }.getOrDefault(emptyList())
        }
    }

    fun addShare(calendarId: Int, userId: Int, permission: String) {
        viewModelScope.launch {
            runCatching { repository.addShare(calendarId, userId, permission) }
                .onSuccess { loadSharing(calendarId) }
                .onFailure { error = it.message }
        }
    }

    fun removeShare(calendarId: Int, userId: Int) {
        viewModelScope.launch {
            runCatching { repository.removeShare(calendarId, userId) }
                .onSuccess { loadSharing(calendarId) }
                .onFailure { error = it.message }
        }
    }

    // ---- Import / export ----

    var infoMessage by mutableStateOf<String?>(null)
        private set

    fun clearInfo() { infoMessage = null }
    fun clearError() { error = null }

    fun importIcs(calendarId: Int, bytes: ByteArray, filename: String, result: (Int, Int) -> String, onChanged: () -> Unit) {
        viewModelScope.launch {
            runCatching { repository.importIcsFile(calendarId, bytes, filename) }
                .onSuccess { (imported, skipped, _) -> infoMessage = result(imported, skipped); load(); onChanged() }
                .onFailure { error = it.message }
        }
    }

    fun exportIcs(calendarId: Int, onBytes: (ByteArray) -> Unit) {
        viewModelScope.launch {
            runCatching { repository.exportIcs(calendarId) }
                .onSuccess { onBytes(it) }
                .onFailure { error = it.message }
        }
    }
}
