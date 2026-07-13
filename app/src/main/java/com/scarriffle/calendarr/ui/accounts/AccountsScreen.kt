package com.scarriffle.calendarr.ui.accounts

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.People
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.scarriffle.calendarr.domain.model.LocalCalendar
import com.scarriffle.calendarr.ui.L10n
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.ui.components.ColorPickerDialog
import com.scarriffle.calendarr.ui.components.PasswordField
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex

private enum class AddType { LOCAL, CALDAV, ICAL, HA }

/** What colour the picker dialog is currently editing. */
private sealed interface ColorTarget {
    val current: String
    data class Local(val id: Int, override val current: String) : ColorTarget
    data class ICal(val id: Int, override val current: String) : ColorTarget
    data class Source(val source: String, val id: Int, override val current: String) : ColorTarget
}

private fun safeFileName(name: String): String {
    val cleaned = name.map { if (it.isLetterOrDigit()) it else '_' }.joinToString("")
    return (cleaned.ifBlank { "calendar" }) + ".ics"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountsScreen(
    onClose: () -> Unit,
    onChanged: () -> Unit,
    vm: AccountsViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val lang = LocalLang.current
    var addDialog by remember { mutableStateOf<AddType?>(null) }
    var editingColor by remember { mutableStateOf<ColorTarget?>(null) }
    var shareCalId by remember { mutableStateOf<Int?>(null) }

    // Import: pick a document, read its bytes, upload to importTarget.
    var importTarget by remember { mutableStateOf<Int?>(null) }
    val openDoc = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val calId = importTarget
        importTarget = null
        if (uri != null && calId != null) {
            val bytes = runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()
            if (bytes != null) {
                vm.importIcs(
                    calId, bytes, "import.ics",
                    result = { imported, skipped -> L10n.t("import.result", lang, imported, skipped) },
                    onChanged = onChanged,
                )
            }
        }
    }

    // Export: fetch bytes first, then let the user save them to a chosen location.
    var pendingExport by remember { mutableStateOf<ByteArray?>(null) }
    val createDoc = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/calendar")) { uri ->
        val bytes = pendingExport
        pendingExport = null
        if (uri != null && bytes != null) {
            runCatching { context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) } }
        }
    }

    // Calendars permanently hidden ("banished") on the server — offered for
    // re-enabling. Derived from the loaded account lists' sidebar_hidden flags.
    val banishedCals: List<BanishedCalendar> = buildList {
        vm.caldav.forEach { acc ->
            acc.calendars.orEmpty().filter { it.sidebarHidden }.forEach {
                add(BanishedCalendar("caldav", it.id, "${acc.name} – ${it.name}", it.color ?: acc.color))
            }
        }
        vm.google.forEach { acc ->
            acc.calendars.orEmpty().filter { it.sidebarHidden }.forEach {
                add(BanishedCalendar("google", it.id, "${acc.email} – ${it.name}", it.color ?: "#4285f4"))
            }
        }
        vm.homeAssistant.forEach { acc ->
            acc.calendars.orEmpty().filter { it.sidebarHidden }.forEach {
                add(BanishedCalendar("homeassistant", it.id, "${acc.name} – ${it.name}", it.color ?: "#46bdc6"))
            }
        }
    }

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
                // Local (incl. shared-with-me and group calendars)
                item { SectionHeader(tr("accounts.local.header"), tr("accounts.local.add")) { addDialog = AddType.LOCAL } }
                if (vm.local.isEmpty()) item { EmptyRow(tr("accounts.local.empty")) }
                items(vm.local, key = { "l${it.id}" }) { cal ->
                    LocalCalendarRow(
                        cal = cal,
                        onColor = { editingColor = ColorTarget.Local(cal.id, cal.color) },
                        onShare = { shareCalId = cal.id },
                        onImport = { importTarget = cal.id; openDoc.launch(arrayOf("*/*")) },
                        onExport = { vm.exportIcs(cal.id) { bytes -> pendingExport = bytes; createDoc.launch(safeFileName(cal.name)) } },
                        onDelete = { vm.deleteLocal(cal.id, onChanged) },
                    )
                }

                // CalDAV
                item { SectionHeader(tr("accounts.caldav.header"), tr("accounts.caldav.add")) { addDialog = AddType.CALDAV } }
                if (vm.caldav.isEmpty()) item { EmptyRow(tr("accounts.caldav.empty")) }
                items(vm.caldav, key = { "c${it.id}" }) { acc ->
                    Column {
                        AccountHeaderRow("${acc.name} (${acc.username})", acc.color) { vm.deleteCalDAV(acc.id, onChanged) }
                        acc.calendars.orEmpty().forEach { cal ->
                            ChildCalendarRow(cal.name, cal.color ?: acc.color) {
                                editingColor = ColorTarget.Source("caldav", cal.id, cal.color ?: acc.color)
                            }
                        }
                    }
                }

                // iCal
                item { SectionHeader(tr("accounts.ical.header"), tr("accounts.ical.add")) { addDialog = AddType.ICAL } }
                if (vm.ical.isEmpty()) item { EmptyRow(tr("accounts.ical.empty")) }
                items(vm.ical, key = { "i${it.id}" }) { sub ->
                    EditableColorRow(sub.name, sub.color, onColor = { editingColor = ColorTarget.ICal(sub.id, sub.color) }) {
                        vm.deleteICal(sub.id, onChanged)
                    }
                }

                // Google
                item { SectionHeaderNoAdd(tr("accounts.google.header")) }
                if (vm.google.isEmpty()) item { EmptyRow(tr("accounts.google.hint")) }
                items(vm.google, key = { "g${it.id}" }) { acc ->
                    Column {
                        AccountHeaderRow(acc.email, "#4285f4") { vm.deleteGoogle(acc.id, onChanged) }
                        acc.calendars.orEmpty().forEach { cal ->
                            ChildCalendarRow(cal.name, cal.color ?: "#4285f4") {
                                editingColor = ColorTarget.Source("google", cal.id, cal.color ?: "#4285f4")
                            }
                        }
                    }
                }

                // Home Assistant
                item { SectionHeader(tr("accounts.ha.header"), tr("accounts.ha.add")) { addDialog = AddType.HA } }
                if (vm.homeAssistant.isEmpty()) item { EmptyRow(tr("accounts.ha.empty")) }
                items(vm.homeAssistant, key = { "h${it.id}" }) { acc ->
                    Column {
                        AccountHeaderRow(acc.name, "#46bdc6") { vm.deleteHA(acc.id, onChanged) }
                        acc.calendars.orEmpty().forEach { cal ->
                            ChildCalendarRow(cal.name, cal.color ?: "#46bdc6") {
                                editingColor = ColorTarget.Source("homeassistant", cal.id, cal.color ?: "#46bdc6")
                            }
                        }
                    }
                }

                // Banished (permanently hidden) calendars — re-enable here.
                if (banishedCals.isNotEmpty()) {
                    item { SectionHeaderNoAdd(tr("accounts.banished_header")) }
                    items(banishedCals, key = { "b${it.source}${it.id}" }) { cal ->
                        BanishedCalendarRow(cal.label, cal.color) { vm.unbanishCalendar(cal.source, cal.id, onChanged) }
                    }
                }

                vm.error?.let { item { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(vertical = 12.dp)) } }
                item { Spacer(Modifier.size(40.dp)) }
            }
        }
    }

    when (addDialog) {
        AddType.LOCAL -> LocalDialog(onDismiss = { addDialog = null }) { name, color, isBirthday, notify ->
            vm.addLocal(name, color, onChanged, isBirthday, notify); addDialog = null
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

    editingColor?.let { target ->
        ColorPickerDialog(
            initial = target.current,
            title = tr("accounts.color"),
            onDismiss = { editingColor = null },
            onConfirm = { hex ->
                when (target) {
                    is ColorTarget.Local -> vm.setLocalColor(target.id, hex, onChanged)
                    is ColorTarget.ICal -> vm.setICalColor(target.id, hex, onChanged)
                    is ColorTarget.Source -> vm.setSourceColor(target.source, target.id, hex, onChanged)
                }
                editingColor = null
            },
        )
    }

    shareCalId?.let { id ->
        SharingSheet(vm = vm, calendarId = id, onDismiss = { shareCalId = null })
    }

    vm.infoMessage?.let { msg ->
        AlertDialog(
            onDismissRequest = { vm.clearInfo() },
            confirmButton = { TextButton(onClick = { vm.clearInfo() }) { Text(tr("common.ok")) } },
            text = { Text(msg) },
        )
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

/** Tappable colour swatch. */
@Composable
private fun ColorDot(hex: String, editable: Boolean, onClick: () -> Unit) {
    val base = Modifier.size(if (editable) 18.dp else 14.dp).clip(CircleShape).background(colorFromHex(hex))
    Box(if (editable) base.clickable(onClick = onClick) else base)
}

/** Account header (CalDAV/Google/HA) with a delete button; colour edited on the child rows. */
@Composable
private fun AccountHeaderRow(name: String, color: String, onDelete: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(14.dp).clip(CircleShape).background(colorFromHex(color)))
        Text(name, modifier = Modifier.weight(1f).padding(start = 12.dp), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
        IconButton(onClick = onDelete) {
            Icon(Icons.Filled.Delete, contentDescription = tr("common.delete"), tint = MaterialTheme.colorScheme.error)
        }
    }
}

/** A child calendar of a server-managed account: editable colour + name. */
@Composable
private fun ChildCalendarRow(name: String, color: String, onColor: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ColorDot(color, editable = true, onClick = onColor)
        Text(name, modifier = Modifier.padding(start = 12.dp), style = MaterialTheme.typography.bodyMedium)
    }
}

/** A permanently-hidden ("banished") calendar with a "show again" button. */
private data class BanishedCalendar(val source: String, val id: Int, val label: String, val color: String)

@Composable
private fun BanishedCalendarRow(name: String, color: String, onUnbanish: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ColorDot(color, editable = false, onClick = {})
        Text(
            name,
            modifier = Modifier.weight(1f).padding(start = 12.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        TextButton(onClick = onUnbanish) { Text(tr("accounts.banished_unhide")) }
    }
}

/** A simple row (iCal) with editable colour + delete. */
@Composable
private fun EditableColorRow(name: String, color: String, onColor: () -> Unit, onDelete: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        ColorDot(color, editable = true, onClick = onColor)
        Text(name, modifier = Modifier.weight(1f).padding(start = 12.dp), style = MaterialTheme.typography.bodyLarge)
        IconButton(onClick = onDelete) {
            Icon(Icons.Filled.Delete, contentDescription = tr("common.delete"), tint = MaterialTheme.colorScheme.error)
        }
    }
}

/** Local calendar row: colour, group marker, "shared by", and an actions menu. */
@Composable
private fun LocalCalendarRow(
    cal: LocalCalendar,
    onColor: () -> Unit,
    onShare: () -> Unit,
    onImport: () -> Unit,
    onExport: () -> Unit,
    onDelete: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        // Recipients of a shared calendar may recolour it (their own per-user
        // colour); only renaming/other management stays owner-only.
        ColorDot(cal.color, editable = true, onClick = onColor)
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(cal.name, style = MaterialTheme.typography.bodyLarge)
                if (cal.group) {
                    Spacer(Modifier.size(6.dp))
                    Icon(Icons.Filled.People, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                }
            }
            val by = cal.sharedBy
            if (!cal.owned && by != null) {
                Text(tr("accounts.shared_by", by), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Box {
            IconButton(onClick = { menu = true }) {
                Icon(Icons.Filled.MoreVert, contentDescription = tr("accounts.action.share"), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                if (cal.owned && !cal.group) {
                    DropdownMenuItem(text = { Text(tr("accounts.action.share")) }, onClick = { menu = false; onShare() })
                }
                if (cal.owned || cal.permission == "read_write") {
                    DropdownMenuItem(text = { Text(tr("accounts.action.import")) }, onClick = { menu = false; onImport() })
                }
                DropdownMenuItem(text = { Text(tr("accounts.action.export")) }, onClick = { menu = false; onExport() })
                if (cal.owned) {
                    DropdownMenuItem(text = { Text(tr("common.delete")) }, onClick = { menu = false; onDelete() })
                }
            }
        }
    }
}

/** Manage who a local calendar is shared with (owner only). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SharingSheet(vm: AccountsViewModel, calendarId: Int, onDismiss: () -> Unit) {
    LaunchedEffect(calendarId) { vm.loadSharing(calendarId) }
    var permission by remember { mutableStateOf("read") }
    var search by remember { mutableStateOf("") }
    val sharedIds = vm.shares.map { it.userId }.toSet()
    val candidates = vm.directory.filter {
        it.id !in sharedIds && (search.isBlank() || it.displayName.contains(search, ignoreCase = true))
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 24.dp).verticalScroll(rememberScrollState()),
        ) {
            Text(tr("share.title"), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.size(16.dp))

            Text(tr("share.with"), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            if (vm.shares.isEmpty()) {
                Text(tr("share.none"), color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 6.dp))
            } else {
                vm.shares.forEach { s ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(s.displayName, modifier = Modifier.weight(1f))
                        Text(
                            if (s.permission == "read_write") tr("share.permission.read_write") else tr("share.permission.read"),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        IconButton(onClick = { vm.removeShare(calendarId, s.userId) }) {
                            Icon(Icons.Filled.Delete, contentDescription = tr("common.delete"), tint = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }

            Divider(Modifier.padding(vertical = 16.dp))

            Text(tr("share.add"), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.size(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = permission == "read", onClick = { permission = "read" }, label = { Text(tr("share.permission.read")) })
                FilterChip(selected = permission == "read_write", onClick = { permission = "read_write" }, label = { Text(tr("share.permission.read_write")) })
            }
            Spacer(Modifier.size(8.dp))
            OutlinedTextField(
                value = search,
                onValueChange = { search = it },
                label = { Text(tr("share.search")) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.size(4.dp))
            candidates.forEach { u ->
                Row(
                    Modifier.fillMaxWidth().clickable { vm.addShare(calendarId, u.id, permission) }.padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(u.displayName, modifier = Modifier.weight(1f))
                    Icon(Icons.Filled.Add, contentDescription = tr("share.add"), tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

// ---- Add dialogs ----

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun LocalDialog(onDismiss: () -> Unit, onConfirm: (String, String, Boolean, Int?) -> Unit) {
    var name by remember { mutableStateOf("") }
    var birthday by remember { mutableStateOf(false) }
    var notify by remember { mutableStateOf(-1) }   // -1 off, 0 on the day, N days before
    var notifyMenu by remember { mutableStateOf(false) }
    val color = "#34a853"
    FormDialog(
        tr("accounts.local.add"), onDismiss,
        confirmEnabled = name.isNotBlank(),
        onConfirm = { onConfirm(name.trim(), color, birthday, if (birthday && notify >= 0) notify else null) },
    ) {
        OutlinedTextField(name, { name = it }, label = { Text(tr("local.name")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.size(8.dp))
        FilterChip(selected = birthday, onClick = { birthday = !birthday }, label = { Text(tr("birthday.is_calendar")) })
        if (birthday) {
            Spacer(Modifier.size(8.dp))
            Box {
                FilterChip(
                    selected = notify >= 0,
                    onClick = { notifyMenu = true },
                    label = { Text("${tr("birthday.notify")}: ${notifyLabel(notify)}") },
                )
                DropdownMenu(expanded = notifyMenu, onDismissRequest = { notifyMenu = false }) {
                    listOf(-1, 0, 1, 2, 3, 7).forEach { d ->
                        DropdownMenuItem(text = { Text(notifyLabel(d)) }, onClick = { notify = d; notifyMenu = false })
                    }
                }
            }
        }
    }
}

@Composable
private fun notifyLabel(d: Int): String = when {
    d < 0 -> tr("birthday.notify.off")
    d == 0 -> tr("birthday.notify.same_day")
    d == 1 -> tr("birthday.notify.one_day")
    else -> tr("birthday.notify.days", d)
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
        PasswordField(pass, { pass = it }, label = tr("caldav.password"), modifier = Modifier.fillMaxWidth())
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
