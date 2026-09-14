package com.scarriffle.calendarr.ui.event

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Notes
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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
import com.scarriffle.calendarr.domain.model.EventAttachment
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.ui.calendar.eventDateRange
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex

/** Full-screen event detail (mirrors the iOS detail page). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventDetailScreen(
    event: CalEvent,
    currentUserId: Int = 0,
    onClose: () -> Unit,
    onEdit: () -> Unit,
    onCopy: () -> Unit,
    onDelete: () -> Unit,
    attachments: List<EventAttachment> = emptyList(),
    attachmentThumbs: Map<Int, ImageBitmap> = emptyMap(),
    onOpenAttachment: (EventAttachment) -> Unit = {},
) {
    val lang = LocalLang.current
    var confirmDelete by remember { mutableStateOf(false) }
    val canEdit = event.source in setOf("local", "caldav", "homeassistant", "google")
    val canDelete = canEdit

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(tr("event.detail_title")) },
                    navigationIcon = {
                        IconButton(onClick = onClose) { Icon(Icons.Filled.Close, contentDescription = tr("common.close")) }
                    },
                    actions = {
                        if (canEdit) {
                            TextButton(onClick = onEdit) { Text(tr("event.edit_title")) }
                        }
                    },
                )
            },
        ) { padding ->
            Column(
                Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(20.dp),
            ) {
                Row(verticalAlignment = Alignment.Top) {
                    Box(
                        Modifier.width(6.dp).height(46.dp).clip(RoundedCornerShape(3.dp))
                            .background(colorFromHex(event.effectiveColor)),
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(event.renderTitle, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
                        if (event.calendarName.isNotBlank()) {
                            Text(event.calendarName, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                Spacer(Modifier.height(20.dp))

                DetailRow(Icons.Filled.Schedule, eventDateRange(event, lang))
                if (event.location.isNotBlank()) DetailRow(Icons.Filled.LocationOn, event.location)
                if (event.notes.isNotBlank()) DetailRow(Icons.Filled.Notes, event.notes)
                if (event.calendarName.isNotBlank()) DetailRow(Icons.Filled.CalendarMonth, event.calendarName)
                DetailRow(Icons.Filled.Dns, event.source.replaceFirstChar { it.uppercase() })
                event.creator?.let { c ->
                    if (c.id != currentUserId) {
                        DetailRow(Icons.Filled.Person, "${tr("event.created_by")}: ${c.displayName}")
                    }
                }
                if (event.isPrivate) DetailRow(Icons.Filled.Lock, tr("event.private"))

                // Attachments exist on local events only; the payload carries
                // just the count, so the list arrives once the screen is open.
                if (event.source == "local" && event.attachmentCount > 0) {
                    Spacer(Modifier.height(12.dp))
                    Text(
                        tr("event.attachments"),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(4.dp))
                    attachments.forEach { att ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onOpenAttachment(att) }
                                .padding(vertical = 8.dp),
                        ) {
                            val thumb = attachmentThumbs[att.id]
                            if (thumb != null) {
                                Image(
                                    bitmap = thumb,
                                    contentDescription = null,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier
                                        .size(32.dp)
                                        .clip(RoundedCornerShape(4.dp)),
                                )
                            } else {
                                Icon(
                                    Icons.Filled.AttachFile,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.size(32.dp),
                                )
                            }
                            Spacer(Modifier.width(12.dp))
                            Text(
                                att.filename,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f),
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                formatAttachmentSize(att.sizeBytes),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }

                Spacer(Modifier.height(28.dp))
                OutlinedButton(onClick = onCopy, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.ContentCopy, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(tr("event.copy_title"))
                }
                if (canDelete) {
                    Spacer(Modifier.height(4.dp))
                    // Deliberately low-key (plain text button): destructive action
                    // should be findable, not the loudest element on the screen.
                    TextButton(
                        onClick = { confirmDelete = true },
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Filled.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(tr("common.delete"))
                    }
                }
                Spacer(Modifier.height(24.dp))
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
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(tr("common.cancel")) } },
        )
    }
}

@Composable
private fun DetailRow(icon: ImageVector, text: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(14.dp))
        Text(text, style = MaterialTheme.typography.bodyLarge)
    }
}

/** Human-readable size, matching what the web and iOS show. */
private fun formatAttachmentSize(bytes: Int): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> "${bytes / 1024} KB"
    else -> String.format(java.util.Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0))
}
