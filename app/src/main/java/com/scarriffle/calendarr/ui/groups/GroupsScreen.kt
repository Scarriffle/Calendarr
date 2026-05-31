package com.scarriffle.calendarr.ui.groups

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.scarriffle.calendarr.domain.model.Group
import com.scarriffle.calendarr.ui.components.ColorPickerDialog
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex

private val GROUP_ICONS = listOf(
    "👥", "👨‍👩‍👧", "🏠", "❤️", "🧑‍🤝‍🧑", "⚽", "🎓", "💼", "🎉", "🐶", "✈️", "🎵", "🍕", "📚", "🌳", "⭐",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupsScreen(
    onClose: () -> Unit,
    onChanged: () -> Unit,
    vm: GroupsViewModel = hiltViewModel(),
) {
    var createOpen by remember { mutableStateOf(false) }
    var manageId by remember { mutableStateOf<Int?>(null) }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(tr("groups.title")) },
                    navigationIcon = {
                        IconButton(onClick = onClose) { Icon(Icons.Filled.Close, contentDescription = tr("common.close")) }
                    },
                    actions = {
                        IconButton(onClick = { createOpen = true }) { Icon(Icons.Filled.Add, contentDescription = tr("groups.create")) }
                    },
                )
            },
        ) { padding ->
            if (vm.loading) {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                return@Scaffold
            }
            LazyColumn(Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp)) {
                if (vm.groups.isEmpty()) {
                    item {
                        Text(tr("groups.empty"), color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 16.dp))
                    }
                }
                items(vm.groups, key = { it.id }) { g ->
                    Row(
                        Modifier.fillMaxWidth().clickable { manageId = g.id }.padding(vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(g.icon ?: "👥", style = MaterialTheme.typography.titleMedium)
                        Text(g.name, modifier = Modifier.weight(1f).padding(start = 12.dp), style = MaterialTheme.typography.bodyLarge)
                        Text(
                            tr("groups.member_count", g.memberCount),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Divider()
                }
                vm.error?.let { item { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(vertical = 12.dp)) } }
            }
        }
    }

    if (createOpen) {
        GroupEditSheet(
            vm = vm,
            existing = null,
            onDismiss = { createOpen = false },
            onSaved = { createOpen = false; onChanged() },
        )
    }

    manageId?.let { id ->
        val existing = vm.groups.firstOrNull { it.id == id }
        GroupEditSheet(
            vm = vm,
            existing = existing,
            onDismiss = { manageId = null },
            onSaved = { manageId = null; onChanged() },
        )
    }
}

/** Create (existing == null) or manage (existing != null) a group. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun GroupEditSheet(
    vm: GroupsViewModel,
    existing: Group?,
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
) {
    val me = vm.currentUserId
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var icon by remember { mutableStateOf(existing?.icon ?: "👥") }
    var selected by remember { mutableStateOf(setOf<Int>()) }
    var existingMembers by remember { mutableStateOf(setOf<Int>()) }
    var detail by remember { mutableStateOf<Group?>(null) }
    var loaded by remember { mutableStateOf(existing == null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var memberColorTarget by remember { mutableStateOf<Pair<Int, String>?>(null) } // userId, current hex

    // Manage: load full details (members + colours) and pre-fill selection.
    LaunchedEffect(existing?.id) {
        val id = existing?.id ?: return@LaunchedEffect
        val g = vm.groupDetail(id)
        detail = g
        if (g != null) {
            name = g.name
            icon = g.icon ?: "👥"
            val members = g.members.map { it.id }.filter { it != me }.toSet()
            existingMembers = members
            selected = members
        }
        loaded = true
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp).verticalScroll(rememberScrollState())) {
            Text(
                if (existing == null) tr("groups.create") else tr("groups.manage"),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.size(16.dp))

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(tr("groups.name")) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.size(16.dp))

            Text(tr("groups.icon"), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.size(8.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                GROUP_ICONS.forEach { ic ->
                    val sel = ic == icon
                    Box(
                        Modifier.size(44.dp).clip(RoundedCornerShape(8.dp))
                            .background(if (sel) MaterialTheme.colorScheme.primary.copy(alpha = 0.25f) else MaterialTheme.colorScheme.surfaceVariant)
                            .clickable { icon = ic },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(ic, style = MaterialTheme.typography.titleLarge)
                    }
                }
            }
            Spacer(Modifier.size(16.dp))

            Text(tr("groups.members"), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            if (!loaded) {
                Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp) }
            } else {
                vm.directory.forEach { u ->
                    Row(
                        Modifier.fillMaxWidth().clickable {
                            selected = if (u.id in selected) selected - u.id else selected + u.id
                        }.padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Checkbox(checked = u.id in selected, onCheckedChange = {
                            selected = if (u.id in selected) selected - u.id else selected + u.id
                        })
                        Text(u.displayName, modifier = Modifier.padding(start = 4.dp))
                    }
                }
            }

            // Member colours (manage only)
            detail?.members?.takeIf { it.isNotEmpty() }?.let { members ->
                Spacer(Modifier.size(8.dp))
                Divider()
                Spacer(Modifier.size(8.dp))
                Text(tr("groups.member_color"), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                members.forEach { m ->
                    val hex = m.color ?: "#4285f4"
                    Row(
                        Modifier.fillMaxWidth().clickable { memberColorTarget = m.id to hex }.padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.size(20.dp).clip(CircleShape).background(colorFromHex(hex)))
                        Text(m.displayName, modifier = Modifier.weight(1f).padding(start = 12.dp))
                    }
                }
            }

            Spacer(Modifier.size(20.dp))
            Button(onClick = {
                val n = name.trim()
                if (n.isEmpty()) return@Button
                if (existing == null) {
                    vm.createGroup(n, icon, selected.toList()) { onSaved() }
                } else {
                    vm.saveGroup(existing.id, n, icon, selected, existingMembers) { onSaved() }
                }
            }, enabled = name.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
                Text(tr("event.save"))
            }

            if (existing != null) {
                Spacer(Modifier.size(8.dp))
                OutlinedButton(
                    onClick = { confirmDelete = true },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.size(8.dp))
                    Text(tr("groups.delete"), color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }

    memberColorTarget?.let { (userId, hex) ->
        ColorPickerDialog(
            initial = hex,
            title = tr("groups.member_color"),
            onDismiss = { memberColorTarget = null },
            onConfirm = { picked ->
                existing?.let { vm.setMemberColor(it.id, userId, picked) }
                // reflect locally
                detail = detail?.let { d -> d.copy(members = d.members.map { if (it.id == userId) it.copy(color = picked) else it }) }
                memberColorTarget = null
            },
        )
    }

    if (confirmDelete && existing != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(tr("groups.delete")) },
            text = { Text(tr("groups.delete_confirm")) },
            confirmButton = {
                TextButton(onClick = { confirmDelete = false; vm.deleteGroup(existing.id) { onSaved() } }) {
                    Text(tr("groups.delete"), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(tr("common.cancel")) } },
        )
    }
}
