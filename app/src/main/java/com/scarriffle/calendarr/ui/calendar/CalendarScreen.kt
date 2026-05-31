package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Today
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.scarriffle.calendarr.domain.model.AppSettings
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.domain.model.CalViewType
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.ui.accounts.AccountsScreen
import com.scarriffle.calendarr.ui.event.EventDetailSheet
import com.scarriffle.calendarr.ui.event.EventEditorSheet
import com.scarriffle.calendarr.ui.menu.MenuSheet
import com.scarriffle.calendarr.ui.profile.ProfileScreen
import com.scarriffle.calendarr.ui.settings.SettingsScreen
import com.scarriffle.calendarr.ui.tr
import java.time.LocalDate

private enum class Overlay { NONE, PROFILE, SETTINGS, ACCOUNTS }

data class EditorRequest(val existing: CalEvent?, val date: LocalDate)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalendarScreen(
    onLogout: () -> Unit,
    onSwitchServer: () -> Unit,
    onSettingsChanged: (AppSettings) -> Unit,
    onSettingsSynced: () -> Unit,
    vm: CalendarViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()
    val lang = LocalLang.current

    var viewMenuOpen by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var showFilter by remember { mutableStateOf(false) }
    var detailEvent by remember { mutableStateOf<CalEvent?>(null) }
    var editor by remember { mutableStateOf<EditorRequest?>(null) }
    var overlay by remember { mutableStateOf(Overlay.NONE) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        titleForView(state.viewType, state.currentDate, lang),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = { showMenu = true }) {
                        Icon(Icons.Filled.Menu, contentDescription = tr("nav.menu"))
                    }
                },
                actions = {
                    IconButton(onClick = vm::navigatePrev) {
                        Icon(Icons.Filled.ChevronLeft, contentDescription = null)
                    }
                    IconButton(onClick = vm::moveToToday) {
                        Icon(Icons.Filled.Today, contentDescription = tr("nav.today"))
                    }
                    IconButton(onClick = vm::navigateNext) {
                        Icon(Icons.Filled.ChevronRight, contentDescription = null)
                    }
                    IconButton(onClick = { showFilter = true }) {
                        Icon(Icons.Filled.FilterList, contentDescription = tr("filter.button"))
                    }
                    Box {
                        IconButton(onClick = { viewMenuOpen = true }) {
                            Icon(state.viewType.icon, contentDescription = tr("view.change"))
                        }
                        DropdownMenu(expanded = viewMenuOpen, onDismissRequest = { viewMenuOpen = false }) {
                            CalViewType.entries.forEach { type ->
                                DropdownMenuItem(
                                    text = { Text(tr("view.${type.key}")) },
                                    leadingIcon = { Icon(type.icon, contentDescription = null) },
                                    onClick = {
                                        viewMenuOpen = false
                                        vm.setViewType(type)
                                    },
                                )
                            }
                        }
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { editor = EditorRequest(null, state.currentDate) }) {
                Icon(Icons.Filled.Add, contentDescription = tr("cal.new_event"))
            }
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            if (state.isLoading || state.isBackgroundCaching) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
            }
            state.error?.let { err ->
                ErrorBanner(err, onRetry = { vm.loadVisible(force = true) }, onDismiss = vm::clearError)
            }
            Box(Modifier.fillMaxSize()) {
                CalendarBody(
                    state = state,
                    vm = vm,
                    onEventClick = { detailEvent = it },
                    onDayClick = { date -> vm.goToDate(date, CalViewType.DAY) },
                    onEmptySlotClick = { date -> editor = EditorRequest(null, date) },
                )
            }
        }
    }

    // ---- Sheets ----

    if (showMenu) {
        MenuSheet(
            isAdmin = false,
            onDismiss = { showMenu = false },
            onProfile = { showMenu = false; overlay = Overlay.PROFILE },
            onAppearance = { showMenu = false; overlay = Overlay.SETTINGS },
            onAccounts = { showMenu = false; overlay = Overlay.ACCOUNTS },
            onSync = { showMenu = false; vm.syncWithServer() },
            onLogout = { showMenu = false; onLogout() },
            onSwitchServer = { showMenu = false; onSwitchServer() },
        )
    }

    if (showFilter) {
        CalendarFilterSheet(
            events = remember(state.events, state.hiddenKeys) { allKnownCalendars(vm) },
            vm = vm,
            onDismiss = { showFilter = false },
        )
    }

    detailEvent?.let { ev ->
        EventDetailSheet(
            event = ev,
            onDismiss = { detailEvent = null },
            onEdit = {
                detailEvent = null
                editor = EditorRequest(ev, localDate(ev.startDate))
            },
            onDelete = {
                vm.deleteEvent(ev) {}
                detailEvent = null
            },
        )
    }

    editor?.let { req ->
        EventEditorSheet(
            request = req,
            writableCalendars = state.writableCalendars,
            onDismiss = { editor = null },
            onSave = { cal, title, start, end, allDay, location, desc, color ->
                vm.saveEvent(cal, req.existing, title, start, end, allDay, location, desc, color) { error ->
                    if (error == null) editor = null
                }
            },
        )
    }

    when (overlay) {
        Overlay.PROFILE -> ProfileScreen(onClose = { overlay = Overlay.NONE })
        Overlay.SETTINGS -> SettingsScreen(
            onClose = { overlay = Overlay.NONE },
            onSettingsChanged = onSettingsChanged,
            onSettingsSynced = onSettingsSynced,
        )
        Overlay.ACCOUNTS -> AccountsScreen(
            onClose = { overlay = Overlay.NONE },
            onChanged = { vm.loadWritableCalendars(); vm.syncWithServer() },
        )
        Overlay.NONE -> Unit
    }
}

@Composable
private fun CalendarBody(
    state: CalendarUiState,
    vm: CalendarViewModel,
    onEventClick: (CalEvent) -> Unit,
    onDayClick: (LocalDate) -> Unit,
    onEmptySlotClick: (LocalDate) -> Unit,
) {
    when (state.viewType) {
        CalViewType.MONTH -> MonthView(state, vm, onDayClick, onEventClick)
        CalViewType.WEEK -> WeekView(state, vm, onEventClick)
        CalViewType.DAY -> DayView(state, vm, onEventClick)
        CalViewType.QUARTER -> QuarterView(state, onDayClick)
        CalViewType.AGENDA -> AgendaView(state, vm, onEventClick)
    }
}

@Composable
private fun ErrorBanner(message: String, onRetry: () -> Unit, onDismiss: () -> Unit) {
    androidx.compose.material3.Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(12.dp)) {
            Text(message, color = MaterialTheme.colorScheme.onErrorContainer, style = MaterialTheme.typography.bodySmall)
            androidx.compose.foundation.layout.Row {
                TextButton(onClick = onRetry) { Text(tr("common.retry")) }
                TextButton(onClick = onDismiss) { Text(tr("common.close")) }
            }
        }
    }
}

@Composable
private fun loadingPlaceholder() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

/** Distinct calendars currently present in the cache, for the filter sheet. */
private fun allKnownCalendars(vm: CalendarViewModel): List<CalendarFilterEntry> {
    val st = vm.state.value
    return st.events
        .map { CalendarFilterEntry(calendarKey(it.source, it.calendarId), it.calendarName.ifBlank { it.source }, it.effectiveColor) }
        .distinctBy { it.key }
        .sortedBy { it.name.lowercase() }
}
