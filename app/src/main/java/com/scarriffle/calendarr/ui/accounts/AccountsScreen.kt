package com.scarriffle.calendarr.ui.accounts

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
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
import androidx.hilt.navigation.compose.hiltViewModel
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex

private enum class AddType { LOCAL, CALDAV, ICAL, HA }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountsScreen(
    onClose: () -> Unit,
    onChanged: () -> Unit,
    vm: AccountsViewModel = hiltViewModel(),
) {
    var addDialog by remember { mutableStateOf<AddType?>(null) }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Scaffold(
            topBar = {
                androidx.compose.material3.TopAppBar(
                    title = { Text(tr("accounts.title")) },
                    navigationIcon = {
                        IconButton(onClick = onClose) { Icon(Icons.Filled.Close, contentDescription = tr("common.close")) }
                    },
                )
            },
        ) { padding ->
            if (vm.loading) {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                return@Scaffold
            }
            LazyColumn(Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp)) {
                // Local
                item { SectionHeader(tr("accounts.local.header"), tr("accounts.local.add")) { addDialog = AddType.LOCAL } }
                if (vm.local.isEmpty()) item { EmptyRow(tr("accounts.local.empty")) }
                items(vm.local, key = { "l${it.id}" }) { cal ->
                    AccountRow(cal.name, cal.color) { vm.deleteLocal(cal.id, onChanged) }
                }

                // CalDAV
                item { SectionHeader(tr("accounts.caldav.header"), tr("accounts.caldav.add")) { addDialog = AddType.CALDAV } }
                if (vm.caldav.isEmpty()) item { EmptyRow(tr("accounts.caldav.empty")) }
                items(vm.caldav, key = { "c${it.id}" }) { acc ->
                    AccountRow("${acc.name} (${acc.username})", acc.color) { vm.deleteCalDAV(acc.id, onChanged) }
                }

                // iCal
                item { SectionHeader(tr("accounts.ical.header"), tr("accounts.ical.add")) { addDialog = AddType.ICAL } }
                if (vm.ical.isEmpty()) item { EmptyRow(tr("accounts.ical.empty")) }
                items(vm.ical, key = { "i${it.id}" }) { sub ->
                    AccountRow(sub.name, sub.color) { vm.deleteICal(sub.id, onChanged) }
                }

                // Google
                item { SectionHeaderNoAdd(tr("accounts.google.header")) }
                if (vm.google.isEmpty()) item { EmptyRow(tr("accounts.google.hint")) }
                items(vm.google, key = { "g${it.id}" }) { acc ->
                    AccountRow(acc.email, "#4285f4") { vm.deleteGoogle(acc.id, onChanged) }
                }

                // Home Assistant
                item { SectionHeader(tr("accounts.ha.header"), tr("accounts.ha.add")) { addDialog = AddType.HA } }
                if (vm.homeAssistant.isEmpty()) item { EmptyRow(tr("accounts.ha.empty")) }
                items(vm.homeAssistant, key = { "h${it.id}" }) { acc ->
                    AccountRow(acc.name, "#46bdc6") { vm.deleteHA(acc.id, onChanged) }
                }

                vm.error?.let { item { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(vertical = 12.dp)) } }
                item { Spacer(Modifier.size(40.dp)) }
            }
        }
    }

    when (addDialog) {
        AddType.LOCAL -> LocalDialog(onDismiss = { addDialog = null }) { name, color ->
            vm.addLocal(name, color, onChanged); addDialog = null
        }
        AddType.CALDAV -> CalDAVDialog(onDismiss = { addDialog = null }) { n, u, us, p, c ->
            vm.addCalDAV(n, u, us, p, c, onChanged); addDialog = null
        }
        AddType.ICAL -> ICalDialog(onDismiss = { addDialog = null }) { n, u, c, r ->
            vm.addICal(n, u, c, r, onChanged); addDialog = null
        }
        AddType.HA -> HADialog(onDismiss = { addDialog = null }) { n, u, t ->
            vm.addHA(n, u, t, onChanged); addDialog = null
        }
        null -> Unit
    }
}

@Composable
private fun SectionHeader(title: String, addLabel: String, onAdd: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(top = 20.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        TextButton(onClick = onAdd) {
            Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.size(4.dp))
            Text(addLabel)
        }
    }
}

@Composable
private fun SectionHeaderNoAdd(title: String) {
    Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 20.dp, bottom = 6.dp))
}

@Composable
private fun EmptyRow(text: String) {
    Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(vertical = 6.dp))
}

@Composable
private fun AccountRow(name: String, color: String, onDelete: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(14.dp).clip(CircleShape).background(colorFromHex(color)))
        Text(name, modifier = Modifier.weight(1f).padding(start = 12.dp), style = MaterialTheme.typography.bodyLarge)
        IconButton(onClick = onDelete) {
            Icon(Icons.Filled.Delete, contentDescription = tr("common.delete"), tint = MaterialTheme.colorScheme.error)
        }
    }
}

// ---- Add dialogs ----

@Composable
private fun LocalDialog(onDismiss: () -> Unit, onConfirm: (String, String) -> Unit) {
    var name by remember { mutableStateOf("") }
    val color = "#34a853"
    FormDialog(tr("accounts.local.add"), onDismiss, confirmEnabled = name.isNotBlank(), onConfirm = { onConfirm(name.trim(), color) }) {
        OutlinedTextField(name, { name = it }, label = { Text(tr("local.name")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun CalDAVDialog(onDismiss: () -> Unit, onConfirm: (String, String, String, String, String) -> Unit) {
    var name by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    var user by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    val color = "#4285f4"
    FormDialog(tr("accounts.caldav.add"), onDismiss, confirmEnabled = url.isNotBlank() && user.isNotBlank(), onConfirm = { onConfirm(name.trim(), url.trim(), user.trim(), pass, color) }) {
        OutlinedTextField(name, { name = it }, label = { Text(tr("caldav.display_name")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.size(8.dp))
        OutlinedTextField(url, { url = it }, label = { Text(tr("caldav.url")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.size(8.dp))
        OutlinedTextField(user, { user = it }, label = { Text(tr("caldav.username")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.size(8.dp))
        OutlinedTextField(pass, { pass = it }, label = { Text(tr("caldav.password")) }, singleLine = true, visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun ICalDialog(onDismiss: () -> Unit, onConfirm: (String, String, String, Int) -> Unit) {
    var name by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    val color = "#46bdc6"
    FormDialog(tr("accounts.ical.add"), onDismiss, confirmEnabled = url.isNotBlank(), onConfirm = { onConfirm(name.trim(), url.trim(), color, 60) }) {
        OutlinedTextField(name, { name = it }, label = { Text(tr("ical.name")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.size(8.dp))
        OutlinedTextField(url, { url = it }, label = { Text(tr("ical.url")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun HADialog(onDismiss: () -> Unit, onConfirm: (String, String, String) -> Unit) {
    var name by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    var token by remember { mutableStateOf("") }
    FormDialog(tr("accounts.ha.add"), onDismiss, confirmEnabled = url.isNotBlank() && token.isNotBlank(), onConfirm = { onConfirm(name.trim(), url.trim(), token.trim()) }) {
        OutlinedTextField(name, { name = it }, label = { Text(tr("ha.display_name")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.size(8.dp))
        OutlinedTextField(url, { url = it }, label = { Text(tr("ha.url_placeholder")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.size(8.dp))
        OutlinedTextField(token, { token = it }, label = { Text(tr("ha.token")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun FormDialog(
    title: String,
    onDismiss: () -> Unit,
    confirmEnabled: Boolean,
    onConfirm: () -> Unit,
    content: @Composable () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Column { content() } },
        confirmButton = { TextButton(onClick = onConfirm, enabled = confirmEnabled) { Text(tr("caldav.connect")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(tr("common.cancel")) } },
    )
}
