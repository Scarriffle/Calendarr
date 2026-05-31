package com.scarriffle.calendarr.ui.event

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Notes
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.ui.calendar.eventDateRange
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun EventDetailSheet(
    event: CalEvent,
    onDismiss: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onCopy: () -> Unit,
) {
    val lang = LocalLang.current
    var confirmDelete by remember { mutableStateOf(false) }
    val canEdit = event.source == "local" || event.source == "caldav"
    val canDelete = event.source == "local" || event.source == "caldav" || event.source == "homeassistant"

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 28.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(16.dp).clip(CircleShape).background(colorFromHex(event.effectiveColor)))
                Spacer(Modifier.size(10.dp))
                Text(
                    event.title,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Spacer(Modifier.size(16.dp))
            DetailRow(Icons.Filled.Schedule, eventDateRange(event, lang))
            if (event.calendarName.isNotBlank()) {
                DetailRow(Icons.Filled.CalendarMonth, event.calendarName)
            }
            if (event.location.isNotBlank()) {
                DetailRow(Icons.Filled.LocationOn, event.location)
            }
            if (event.notes.isNotBlank()) {
                DetailRow(Icons.Filled.Notes, event.notes)
            }
            Spacer(Modifier.size(20.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (canEdit) {
                    OutlinedButton(onClick = onEdit) {
                        Icon(Icons.Filled.Edit, contentDescription = null)
                        Spacer(Modifier.size(6.dp))
                        Text(tr("event.edit_title"))
                    }
                }
                OutlinedButton(onClick = onCopy) {
                    Icon(Icons.Filled.ContentCopy, contentDescription = null)
                    Spacer(Modifier.size(6.dp))
                    Text(tr("event.copy_title"))
                }
                if (canDelete) {
                    OutlinedButton(onClick = { confirmDelete = true }) {
                        Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.size(6.dp))
                        Text(tr("common.delete"), color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(tr("common.delete")) },
            text = { Text(tr("event.delete_confirm")) },
            confirmButton = {
                TextButton(onClick = { confirmDelete = false; onDelete() }) {
                    Text(tr("common.delete"), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text(tr("common.cancel")) }
            },
        )
    }
}

@Composable
private fun DetailRow(icon: ImageVector, text: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
        Spacer(Modifier.size(12.dp))
        Text(text, style = MaterialTheme.typography.bodyLarge)
    }
}
