package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex

data class CalendarFilterEntry(val key: String, val name: String, val color: String, val source: String = "", val readOnly: Boolean = false)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalendarFilterSheet(
    events: List<CalendarFilterEntry>,
    vm: CalendarViewModel,
    onDismiss: () -> Unit,
) {
    val state by vm.state.collectAsState()
    val groupMode = state.activeGroup != null

    // In group mode the filter lists members (+ the group calendar) so they can
    // be hidden individually, Outlook-style; otherwise the normal calendars.
    val groupEntries: List<CalendarFilterEntry> = if (groupMode) {
        buildList {
            state.activeGroupMembers.forEach { m ->
                add(CalendarFilterEntry(groupMemberKey(m.id), m.displayName, m.color ?: "#4285f4"))
            }
            add(CalendarFilterEntry(GROUP_CALENDAR_KEY, tr("groups.calendar"), state.activeGroup?.groupCalendarColor ?: "#4285f4"))
        }
    } else emptyList()
    val rows = if (groupMode) groupEntries else events
    val hiddenSet = if (groupMode) state.hiddenGroupKeys else state.hiddenKeys

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(tr("filter.title"), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                Row {
                    TextButton(onClick = {
                        if (groupMode) vm.setHiddenGroupKeys(emptySet()) else vm.setHiddenCalendars(emptySet())
                    }) { Text(tr("filter.show_all")) }
                    TextButton(onClick = {
                        if (groupMode) vm.setHiddenGroupKeys(rows.map { it.key }.toSet())
                        else vm.setHiddenCalendars(rows.map { it.key }.toSet())
                    }) { Text(tr("filter.hide_all")) }
                }
            }
            if (rows.isEmpty()) {
                Text(
                    tr("filter.empty"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 24.dp),
                )
            }
            rows.forEach { entry ->
                val visible = entry.key !in hiddenSet
                // entry.key is "source:id" (see calendarKey()); match sync errors on the
                // same (source, calendarId) pair the server already attaches to events.
                val entryId = entry.key.substringAfter(":")
                val hasSyncError = !groupMode && state.syncErrors.any { err ->
                    err.source == entry.source && err.calendarId?.toString() == entryId
                }
                Row(
                    Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(14.dp).clip(CircleShape).background(colorFromHex(entry.color)))
                    if (hasSyncError) {
                        Icon(
                            Icons.Filled.WarningAmber,
                            contentDescription = tr("filter.sync_error"),
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.padding(start = 8.dp).size(16.dp),
                        )
                    }
                    Text(
                        entry.name,
                        modifier = Modifier.weight(1f).padding(start = 12.dp),
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    if (entry.readOnly) {
                        Icon(
                            Icons.Filled.Lock,
                            contentDescription = tr("filter.read_only"),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(end = 4.dp).size(15.dp),
                        )
                    }
                    if (!groupMode) {
                        val remDisabled = entry.key in state.reminderDisabledKeys
                        IconButton(onClick = { vm.setCalendarRemindersDisabled(entry.key, disabled = !remDisabled) }) {
                            Icon(
                                if (remDisabled) Icons.Filled.NotificationsOff else Icons.Filled.Notifications,
                                contentDescription = tr(if (remDisabled) "filter.reminders_on" else "filter.reminders_off"),
                                tint = if (remDisabled) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary,
                            )
                        }
                        // Banish = permanently hide (syncs to the server); moves the
                        // calendar into Settings, distinct from the local quick-hide.
                        IconButton(onClick = { vm.setCalendarBanished(entry.key, banished = true) }) {
                            Icon(
                                Icons.Filled.Archive,
                                contentDescription = tr("filter.banish"),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    Switch(
                        checked = visible,
                        onCheckedChange = {
                            if (groupMode) vm.setGroupKeyHidden(entry.key, hidden = !it)
                            else vm.setCalendarHidden(entry.key, !it)
                        },
                    )
                }
            }
            if (!groupMode && state.banishedKeys.isNotEmpty()) {
                Text(
                    tr("filter.banished_footer"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            Box(Modifier.padding(bottom = 24.dp))
        }
    }
}
