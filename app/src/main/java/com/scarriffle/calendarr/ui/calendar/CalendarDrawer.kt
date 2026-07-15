package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.scarriffle.calendarr.domain.model.CalViewType
import com.scarriffle.calendarr.domain.model.Group
import com.scarriffle.calendarr.ui.groups.GroupIcon
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex

/**
 * The left navigation drawer: calendar visibility (flat, reorderable) + view /
 * group switching + a header with manual sync, the full menu, and close. Mirrors
 * the iOS side drawer. Order is device-local (CalendarViewModel.calendarOrder).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun CalendarDrawerContent(
    state: CalendarUiState,
    vm: CalendarViewModel,
    username: String,
    serverUrl: String,
    calendars: List<CalendarFilterEntry>,
    onOpenMenu: () -> Unit,
    onSync: () -> Unit,
    onClose: () -> Unit,
) {
    var isSorting by remember { mutableStateOf(false) }

    // Working order: entries sorted by the stored order (unknown → end, by name).
    var order by remember(calendars, vm.calendarOrder) {
        mutableStateOf(
            calendars.sortedWith(
                compareBy(
                    { vm.calendarOrder.indexOf(it.key).let { i -> if (i < 0) Int.MAX_VALUE else i } },
                    { it.name.lowercase() },
                )
            ).map { it.key }
        )
    }
    val entries = order.mapNotNull { key -> calendars.firstOrNull { it.key == key } }

    fun move(index: Int, delta: Int) {
        val to = index + delta
        if (to < 0 || to >= order.size) return
        val m = order.toMutableList()
        val x = m.removeAt(index); m.add(to, x)
        order = m
        vm.setCalendarOrder(m)
    }

    ModalDrawerSheet(Modifier.width(320.dp).fillMaxHeight()) {
        Column(Modifier.fillMaxHeight()) {
            header(username, serverUrl, onSync, onOpenMenu, onClose)
            Divider()
            viewSwitcher(state.viewType) { vm.setViewType(it) }
            Divider()
            if (state.groups.isNotEmpty()) {
                groupSwitcher(state.groups, state.activeGroup) { vm.switchGroup(it) }
                Divider()
            }
            Row(
                Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 8.dp, bottom = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(tr("filter.title"), style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { isSorting = !isSorting }) {
                    Text(tr(if (isSorting) "filter.done" else "filter.sort"))
                }
            }
            LazyColumn(Modifier.fillMaxWidth().weight(1f).navigationBarsPadding()) {
                items(entries, key = { it.key }) { entry ->
                    CalendarRow(
                        entry = entry,
                        visible = entry.key !in state.hiddenKeys,
                        reminderDisabled = entry.key in state.reminderDisabledKeys,
                        sorting = isSorting,
                        onToggle = { vm.setCalendarHidden(entry.key, !it) },
                        onBanish = { vm.setCalendarBanished(entry.key, banished = true) },
                        onToggleReminders = { vm.setCalendarRemindersDisabled(entry.key, disabled = it) },
                        onMoveUp = { move(order.indexOf(entry.key), -1) },
                        onMoveDown = { move(order.indexOf(entry.key), 1) },
                    )
                }
            }
        }
    }
}

@Composable
private fun header(
    username: String,
    serverUrl: String,
    onSync: () -> Unit,
    onOpenMenu: () -> Unit,
    onClose: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().statusBarsPadding().padding(start = 18.dp, end = 8.dp, top = 12.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(48.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary),
            contentAlignment = Alignment.Center,
        ) {
            Text(username.firstOrNull()?.uppercase() ?: "?",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onPrimary, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.weight(1f).padding(start = 14.dp)) {
            Text(username, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Text(serverUrl.removePrefix("https://").removePrefix("http://"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
        IconButton(onClick = onSync) {
            Icon(Icons.Filled.Refresh, contentDescription = tr("menu.sync"), tint = MaterialTheme.colorScheme.primary)
        }
        IconButton(onClick = onOpenMenu) {
            Icon(Icons.Filled.Settings, contentDescription = tr("menu.appearance"), tint = MaterialTheme.colorScheme.primary)
        }
        IconButton(onClick = onClose) {
            Icon(Icons.Filled.Close, contentDescription = tr("common.close"), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun viewSwitcher(current: CalViewType, onSelect: (CalViewType) -> Unit) {
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        CalViewType.entries.forEach { type ->
            FilterChip(
                selected = current == type,
                onClick = { onSelect(type) },
                label = { Text(tr("view.${type.key}")) },
                leadingIcon = { Icon(type.icon, contentDescription = null, modifier = Modifier.size(18.dp)) },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun groupSwitcher(groups: List<Group>, active: Group?, onSwitch: (Group?) -> Unit) {
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FilterChip(
            selected = active == null,
            onClick = { onSwitch(null) },
            label = { Text(tr("group.switch.personal")) },
        )
        groups.forEach { g ->
            FilterChip(
                selected = active?.id == g.id,
                onClick = { onSwitch(g) },
                label = { Text(g.name) },
                leadingIcon = { GroupIcon(g.icon) },
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CalendarRow(
    entry: CalendarFilterEntry,
    visible: Boolean,
    reminderDisabled: Boolean,
    sorting: Boolean,
    onToggle: (Boolean) -> Unit,
    onBanish: () -> Unit,
    onToggleReminders: (Boolean) -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth()
                .combinedClickable(
                    onClick = { if (!sorting) onToggle(visible) },
                    onLongClick = { if (!sorting) menuOpen = true },
                )
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(14.dp).clip(CircleShape).background(colorFromHex(entry.color)))
            Text(
                entry.name,
                modifier = Modifier.weight(1f).padding(start = 12.dp),
                style = MaterialTheme.typography.bodyLarge,
                color = if (visible) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (entry.readOnly) {
                Icon(Icons.Filled.Lock, contentDescription = tr("filter.read_only"),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(end = 6.dp).size(15.dp))
            }
            if (sorting) {
                IconButton(onClick = onMoveUp) { Icon(Icons.Filled.KeyboardArrowUp, contentDescription = tr("filter.move_up")) }
                IconButton(onClick = onMoveDown) { Icon(Icons.Filled.KeyboardArrowDown, contentDescription = tr("filter.move_down")) }
            } else {
                if (reminderDisabled) {
                    Icon(Icons.Filled.NotificationsOff, contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(end = 6.dp).size(16.dp))
                }
                Switch(checked = visible, onCheckedChange = onToggle)
            }
        }
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(
                text = { Text(tr(if (reminderDisabled) "filter.reminders_on" else "filter.reminders_off")) },
                leadingIcon = { Icon(if (reminderDisabled) Icons.Filled.Notifications else Icons.Filled.NotificationsOff, contentDescription = null) },
                onClick = { menuOpen = false; onToggleReminders(!reminderDisabled) },
            )
            DropdownMenuItem(
                text = { Text(tr("filter.banish")) },
                leadingIcon = { Icon(Icons.Filled.Archive, contentDescription = null) },
                onClick = { menuOpen = false; onBanish() },
            )
        }
    }
}
