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
import androidx.compose.material3.ExperimentalMaterial3Api
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

data class CalendarFilterEntry(val key: String, val name: String, val color: String)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalendarFilterSheet(
    events: List<CalendarFilterEntry>,
    vm: CalendarViewModel,
    onDismiss: () -> Unit,
) {
    val state by vm.state.collectAsState()

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(tr("filter.title"), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                Row {
                    TextButton(onClick = { vm.setHiddenCalendars(emptySet()) }) { Text(tr("filter.show_all")) }
                    TextButton(onClick = {
                        vm.setHiddenCalendars(events.map { it.key }.toSet())
                    }) { Text(tr("filter.hide_all")) }
                }
            }
            if (events.isEmpty()) {
                Text(
                    tr("filter.empty"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 24.dp),
                )
            }
            events.forEach { entry ->
                val visible = entry.key !in state.hiddenKeys
                Row(
                    Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(14.dp).clip(CircleShape).background(colorFromHex(entry.color)))
                    Text(
                        entry.name,
                        modifier = Modifier.weight(1f).padding(start = 12.dp),
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    Switch(
                        checked = visible,
                        onCheckedChange = { vm.setCalendarHidden(entry.key, hidden = !it) },
                    )
                }
            }
            Box(Modifier.padding(bottom = 24.dp))
        }
    }
}
