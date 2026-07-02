package com.scarriffle.calendarr.ui.calendar

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Today
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Divider
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.scarriffle.calendarr.domain.model.AppSettings
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.domain.model.CalViewType
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.ui.accounts.AccountsScreen
import com.scarriffle.calendarr.domain.model.Group
import com.scarriffle.calendarr.ui.event.EventDetailScreen
import com.scarriffle.calendarr.ui.event.EventEditorSheet
import com.scarriffle.calendarr.ui.groups.GroupIcon
import com.scarriffle.calendarr.ui.groups.GroupsScreen
import com.scarriffle.calendarr.ui.menu.MenuSheet
import com.scarriffle.calendarr.ui.profile.ProfileScreen
import com.scarriffle.calendarr.ui.settings.SettingsScreen
import com.scarriffle.calendarr.ui.tr
import java.time.LocalDate

private enum class Overlay { NONE, PROFILE, SETTINGS, ACCOUNTS, GROUPS }

data class EditorRequest(val existing: CalEvent?, val date: LocalDate, val prefill: CalEvent? = null)

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
    val context = androidx.compose.ui.platform.LocalContext.current

    // Ask once for notification permission (Android 13+), then keep the OS
    // reminder alarms in sync with the visible events / muted-calendar set.
    val notifPermLauncher = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
    ) {}
    androidx.compose.runtime.LaunchedEffect(Unit) {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            androidx.core.content.ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.POST_NOTIFICATIONS
            ) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            notifPermLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    androidx.compose.runtime.LaunchedEffect(state.events, state.reminderDisabledKeys) {
        com.scarriffle.calendarr.notifications.NotificationScheduler.reschedule(
            context, state.events, state.reminderDisabledKeys, vm.defaultReminderMinutes
        )
    }

    var viewMenuOpen by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var showFilter by remember { mutableStateOf(false) }
    var detailEvent by remember { mutableStateOf<CalEvent?>(null) }
    var editor by remember { mutableStateOf<EditorRequest?>(null) }
    var overlay by remember { mutableStateOf(Overlay.NONE) }
    var dayPreview by remember { mutableStateOf<LocalDate?>(null) }

    // Continuous month scrolling
    val monthListState = rememberLazyListState()
    var todaySignal by remember { mutableIntStateOf(0) }
    var monthJumpSignal by remember { mutableIntStateOf(0) }
    var monthJumpTarget by remember { mutableStateOf<LocalDate?>(null) }
    var visibleMonth by remember { mutableStateOf(state.currentDate) }
    val isMonth = state.viewType == CalViewType.MONTH
    val barTitle = if (isMonth) titleForView(CalViewType.MONTH, visibleMonth, lang)
        else titleForView(state.viewType, state.currentDate, lang)

    fun goPrev() {
        if (isMonth) { monthJumpTarget = visibleMonth.minusMonths(1); monthJumpSignal++ } else vm.navigatePrev()
    }
    fun goNext() {
        if (isMonth) { monthJumpTarget = visibleMonth.plusMonths(1); monthJumpSignal++ } else vm.navigateNext()
    }
    fun goToday() {
        if (isMonth) todaySignal++ else vm.moveToToday()
    }

    Scaffold(
        topBar = {
            CompactTopBar(
                title = barTitle,
                viewType = state.viewType,
                loading = state.isLoading || state.isBackgroundCaching,
                viewMenuOpen = viewMenuOpen,
                groups = state.groups,
                activeGroup = state.activeGroup,
                onSwitchGroup = { vm.switchGroup(it) },
                onMenu = { showMenu = true },
                onPrev = { goPrev() },
                onToday = { goToday() },
                onNext = { goNext() },
                onFilter = { showFilter = true },
                onViewMenuToggle = { viewMenuOpen = it },
                onSelectView = { vm.setViewType(it) },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { editor = EditorRequest(null, if (isMonth) visibleMonth else state.currentDate) },
                shape = CircleShape,
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
            ) {
                Icon(Icons.Filled.Add, contentDescription = tr("cal.new_event"))
            }
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            state.error?.let { err ->
                ErrorBanner(err, onRetry = { vm.loadVisible(force = true) }, onDismiss = vm::clearError)
            }
            if (state.syncErrors.isNotEmpty()) {
                SyncErrorBanner(state.syncErrors, onDismiss = vm::clearSyncErrors)
            }
            state.activeGroup?.let { g ->
                GroupBanner(group = g, onExit = { vm.switchGroup(null) })
            }
            Box(Modifier.fillMaxSize()) {
                // remember: stable callbacks keep the lazily composed week rows
                // skippable during scroll (fresh lambdas would recompose them all).
                CalendarBody(
                    state = state,
                    vm = vm,
                    monthListState = monthListState,
                    scrollToTodaySignal = todaySignal,
                    monthJumpSignal = monthJumpSignal,
                    monthJumpTarget = monthJumpTarget,
                    onVisibleMonthChange = remember { { visibleMonth = it } },
                    onEventClick = remember { { detailEvent = it } },
                    onDayClick = remember(vm) { { date -> vm.goToDate(date, CalViewType.DAY) } },
                    onDayLongPress = remember { { date -> dayPreview = date } },
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
            onGroups = { showMenu = false; overlay = Overlay.GROUPS },
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

    dayPreview?.let { date ->
        DayPreviewDialog(
            date = date,
            events = remember(state.events, date) { vm.eventsOn(date, state.events) },
            onDismiss = { dayPreview = null },
            onEventClick = { ev -> dayPreview = null; detailEvent = ev },
            onCreateEvent = { dayPreview = null; editor = EditorRequest(null, date) },
            onOpenDay = { dayPreview = null; vm.goToDate(date, CalViewType.DAY) },
            onOpenWeek = { dayPreview = null; vm.goToDate(date, CalViewType.WEEK) },
        )
    }

    // Keep the last event during the close animation.
    var lastDetail by remember { mutableStateOf<CalEvent?>(null) }
    detailEvent?.let { lastDetail = it }
    AnimatedVisibility(
        visible = detailEvent != null,
        enter = slideInVertically(initialOffsetY = { it / 6 }) + fadeIn(),
        exit = slideOutVertically(targetOffsetY = { it / 6 }) + fadeOut(),
    ) {
        val ev = lastDetail
        if (ev != null) {
            EventDetailScreen(
                event = ev,
                currentUserId = vm.currentUserId,
                onClose = { detailEvent = null },
                onEdit = {
                    detailEvent = null
                    editor = EditorRequest(ev, localDate(ev.startDate))
                },
                onCopy = {
                    detailEvent = null
                    editor = EditorRequest(existing = null, date = localDate(ev.startDate), prefill = ev)
                },
                onDelete = {
                    vm.deleteEvent(ev) {}
                    detailEvent = null
                },
            )
        }
    }

    editor?.let { req ->
        EventEditorSheet(
            request = req,
            writableCalendars = state.writableCalendars,
            onDismiss = { editor = null },
            defaultDurationMinutes = vm.defaultEventDurationMinutes,
            reminderDisabledKeys = state.reminderDisabledKeys,
            onSave = { cal, title, start, end, allDay, location, desc, color, isPrivate, reminders ->
                vm.saveEvent(cal, req.existing, title, start, end, allDay, location, desc, color, isPrivate, reminders) { error ->
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
        Overlay.GROUPS -> GroupsScreen(
            onClose = { overlay = Overlay.NONE },
            onChanged = { vm.loadGroups(); vm.loadWritableCalendars() },
            onOpenGroupView = { g -> overlay = Overlay.NONE; vm.switchGroup(g) },
        )
        Overlay.NONE -> Unit
    }
}

@Composable
private fun CalendarBody(
    state: CalendarUiState,
    vm: CalendarViewModel,
    monthListState: androidx.compose.foundation.lazy.LazyListState,
    scrollToTodaySignal: Int,
    monthJumpSignal: Int,
    monthJumpTarget: LocalDate?,
    onVisibleMonthChange: (LocalDate) -> Unit,
    onEventClick: (CalEvent) -> Unit,
    onDayClick: (LocalDate) -> Unit,
    onDayLongPress: (LocalDate) -> Unit,
) {
    when (state.viewType) {
        CalViewType.MONTH -> MonthView(
            state = state,
            vm = vm,
            listState = monthListState,
            scrollToTodaySignal = scrollToTodaySignal,
            monthJumpSignal = monthJumpSignal,
            monthJumpTarget = monthJumpTarget,
            onVisibleMonthChange = onVisibleMonthChange,
            onDayClick = onDayClick,
            onDayLongPress = onDayLongPress,
            onEventClick = onEventClick,
        )
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

/**
 * Additive to [ErrorBanner]: the fetch as a whole succeeded, but one or more
 * enabled calendars failed to sync (e.g. expired credentials) and are showing
 * zero events with no other indication. Same visual language, no retry button
 * (retrying the whole range wouldn't target just the broken calendar).
 */
@Composable
private fun SyncErrorBanner(errors: List<com.scarriffle.calendarr.data.SyncError>, onDismiss: () -> Unit) {
    androidx.compose.material3.Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(12.dp)) {
            errors.forEach { err ->
                Text(
                    "${err.name}: ${err.message}",
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            androidx.compose.foundation.layout.Row {
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

@Composable
private fun CompactTopBar(
    title: String,
    viewType: CalViewType,
    loading: Boolean,
    viewMenuOpen: Boolean,
    groups: List<Group>,
    activeGroup: Group?,
    onSwitchGroup: (Group?) -> Unit,
    onMenu: () -> Unit,
    onPrev: () -> Unit,
    onToday: () -> Unit,
    onNext: () -> Unit,
    onFilter: () -> Unit,
    onViewMenuToggle: (Boolean) -> Unit,
    onSelectView: (CalViewType) -> Unit,
) {
    val twoLine = viewType == CalViewType.WEEK || viewType == CalViewType.DAY
    Surface(color = MaterialTheme.colorScheme.background) {
        Column {
        Row(
            Modifier.fillMaxWidth().height(50.dp).padding(horizontal = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CompactIcon(Icons.Filled.ChevronLeft, onPrev)
            TextButton(onClick = onToday, contentPadding = PaddingValues(horizontal = 6.dp)) {
                Text(tr("nav.today"), fontSize = 13.sp)
            }
            CompactIcon(Icons.Filled.ChevronRight, onNext)
            Text(
                title,
                modifier = Modifier.weight(1f).padding(horizontal = 4.dp),
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                fontSize = if (twoLine) 13.sp else 16.sp,
                lineHeight = if (twoLine) 15.sp else 18.sp,
                fontWeight = FontWeight.Medium,
            )
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp).padding(end = 2.dp),
                    strokeWidth = 2.dp,
                )
            }
            if (groups.isNotEmpty()) {
                GroupSwitcher(groups = groups, activeGroup = activeGroup, onSwitchGroup = onSwitchGroup)
            }
            CompactIcon(Icons.Filled.FilterList, onFilter, tr("filter.button"))
            Box {
                CompactIcon(viewType.icon, { onViewMenuToggle(true) }, tr("view.change"))
                DropdownMenu(expanded = viewMenuOpen, onDismissRequest = { onViewMenuToggle(false) }) {
                    CalViewType.entries.forEach { type ->
                        DropdownMenuItem(
                            text = { Text(tr("view.${type.key}")) },
                            leadingIcon = { Icon(type.icon, contentDescription = null) },
                            onClick = { onViewMenuToggle(false); onSelectView(type) },
                        )
                    }
                }
            }
            CompactIcon(Icons.Filled.Menu, onMenu, tr("nav.menu"))
        }
        Divider(
            thickness = 0.5.dp,
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.7f),
        )
        }
    }
}

@Composable
private fun CompactIcon(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
    contentDescription: String? = null,
) {
    IconButton(onClick = onClick, modifier = Modifier.size(40.dp)) {
        Icon(icon, contentDescription = contentDescription, modifier = Modifier.size(22.dp))
    }
}

/**
 * Top-bar switcher: "My calendar" + each group; flips the calendar into the
 * group overlay. Rendered as a tonal pill so it stands out from the flat icons
 * (filled in the accent colour while a group overlay is active).
 */
@Composable
private fun GroupSwitcher(groups: List<Group>, activeGroup: Group?, onSwitchGroup: (Group?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val active = activeGroup != null
    Box {
        Box(
            Modifier
                .padding(horizontal = 2.dp)
                .size(38.dp)
                .clip(CircleShape)
                .background(if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant)
                .clickable { open = true },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.People,
                contentDescription = tr("groups.title"),
                modifier = Modifier.size(21.dp),
                tint = if (active) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(tr("group.switch.personal")) },
                trailingIcon = { if (!active) Icon(Icons.Filled.Check, contentDescription = null) },
                onClick = { open = false; onSwitchGroup(null) },
            )
            groups.forEach { g ->
                DropdownMenuItem(
                    text = { Text(g.name) },
                    leadingIcon = { GroupIcon(g.icon) },
                    trailingIcon = { if (activeGroup?.id == g.id) Icon(Icons.Filled.Check, contentDescription = null) },
                    onClick = { open = false; onSwitchGroup(g) },
                )
            }
        }
    }
}

@Composable
private fun GroupBanner(group: Group, onExit: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), modifier = Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            GroupIcon(group.icon, modifier = Modifier.padding(end = 6.dp))
            Text(
                "${tr("groups.view")}: ${group.name}",
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodyMedium,
            )
            TextButton(onClick = onExit) { Text(tr("group.switch.personal")) }
        }
    }
}

/** Distinct calendars currently present in the cache, for the filter sheet. */
private fun allKnownCalendars(vm: CalendarViewModel): List<CalendarFilterEntry> {
    val st = vm.state.value
    return st.events
        .map { CalendarFilterEntry(calendarKey(it.source, it.calendarId), it.calendarName.ifBlank { it.source }, it.effectiveColor, it.source) }
        .distinctBy { it.key }
        .sortedBy { it.name.lowercase() }
}
