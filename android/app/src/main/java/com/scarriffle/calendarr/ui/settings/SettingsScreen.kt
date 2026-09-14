package com.scarriffle.calendarr.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.Divider
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.scarriffle.calendarr.domain.model.AppSettings
import com.scarriffle.calendarr.domain.model.CalViewType
import com.scarriffle.calendarr.ui.LocalAppSettings
import com.scarriffle.calendarr.ui.components.ColorPickerDialog
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex
import com.scarriffle.calendarr.util.toHex

// Canonical default colours (single source for the reset buttons).
private val DEFAULT_COLORS = mapOf(
    "primary_color" to "#4285F4", "accent_color" to "#EA4335", "today_color" to "#4285F4",
    "text_color" to "#FFFFFF", "bg_color" to "#000000", "line_color" to "#3A3A52",
    "month_divider_color" to "#7090C0", "month_label_color" to "#7090C0",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onClose: () -> Unit,
    onSettingsChanged: (AppSettings) -> Unit,
    onSettingsSynced: () -> Unit,
    vm: SettingsViewModel = hiltViewModel(),
) {
    val initialSettings = LocalAppSettings.current
    var settings by remember { mutableStateOf(initialSettings) }

    fun update(newSettings: AppSettings) {
        settings = newSettings
        onSettingsChanged(newSettings)
        vm.apply(newSettings, onSettingsSynced)
    }

    // Per-row sync toggle: enabling adopts this device's current value.
    fun toggle(key: String) { vm.toggleSync(key, settings, onSettingsSynced) }
    fun synced(key: String) = vm.syncFlags[key] == true

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(tr("settings.title")) },
                    navigationIcon = {
                        IconButton(onClick = onClose) { Icon(Icons.Filled.Close, contentDescription = tr("common.close")) }
                    },
                )
            },
        ) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp)) {

                // Global "sync everything" master switch.
                Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(tr("settings.sync_all"), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Text(tr("settings.sync_all.desc"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(
                        checked = vm.syncableKeys.all { vm.syncFlags[it] == true },
                        onCheckedChange = { on -> vm.setAllSync(on, settings, onSettingsSynced) },
                    )
                }
                Divider(Modifier.padding(vertical = 16.dp))

                ProfileChapter(vm)
                Divider(Modifier.padding(vertical = 16.dp))

                // ---- Termine (synced) ----
                Section(tr("settings.calview"))
                SyncDropdownRow(
                    tr("settings.default_duration"),
                    listOf("15" to "15 min", "30" to "30 min", "45" to "45 min", "60" to "1 h", "90" to "1.5 h", "120" to "2 h"),
                    settings.defaultEventDurationMinutes.toString(),
                    { update(settings.copy(defaultEventDurationMinutes = it.toInt())) },
                    synced("default_event_duration_minutes"), { toggle("default_event_duration_minutes") },
                )
                SyncDropdownRow(
                    tr("settings.defaultreminder"),
                    reminderOptions(),
                    (settings.defaultReminderMinutes ?: -1).toString(),
                    { update(settings.copy(defaultReminderMinutes = it.toInt().takeIf { m -> m >= 0 })) },
                    synced("default_reminder_minutes"), { toggle("default_reminder_minutes") },
                )
                Divider(Modifier.padding(vertical = 16.dp))

                // ---- Ansicht (synced) ----
                Section(tr("settings.appearance"))
                SyncDropdownRow(
                    tr("settings.defaultview"),
                    CalViewType.entries.map { it.key to tr("view.${it.key}") },
                    settings.defaultView,
                    { update(settings.copy(defaultView = it)) },
                    synced("default_view"), { toggle("default_view") },
                )
                SyncDropdownRow(
                    tr("settings.firstweekday"),
                    listOf("monday" to tr("settings.monday"), "sunday" to tr("settings.sunday")),
                    settings.weekStartDay,
                    { update(settings.copy(weekStartDay = it)) },
                    synced("week_start_day"), { toggle("week_start_day") },
                )
                SyncSwitchRow(tr("settings.dimpast"), settings.dimPastEvents, { update(settings.copy(dimPastEvents = it)) }, synced("dim_past_events"), { toggle("dim_past_events") })
                SyncDropdownRow(
                    tr("settings.month_mode"),
                    listOf("false" to tr("settings.month_mode.scroll"), "true" to tr("settings.month_mode.paged")),
                    settings.monthViewPaged.toString(),
                    { update(settings.copy(monthViewPaged = it.toBoolean())) },
                    synced("month_view_paged"), { toggle("month_view_paged") },
                )
                SyncDropdownRow(
                    tr("settings.hourheight"),
                    listOf("28" to tr("settings.hourheight.compact"), "44" to tr("settings.hourheight.normal"), "60" to tr("settings.hourheight.comfort"), "80" to tr("settings.hourheight.large")),
                    settings.hourHeight.toString(),
                    { update(settings.copy(hourHeight = it.toInt())) },
                    synced("hour_height"), { toggle("hour_height") },
                )
                Divider(Modifier.padding(vertical = 16.dp))

                // ---- Farben (synced) ----
                Section(tr("settings.colors"))
                SyncColorRow("primary_color", tr("settings.color.primary"), settings.primaryColor, synced("primary_color"), { toggle("primary_color") }) { update(settings.copy(primaryColor = it)) }
                SyncColorRow("accent_color", tr("settings.color.accent"), settings.accentColor, synced("accent_color"), { toggle("accent_color") }) { update(settings.copy(accentColor = it)) }
                SyncColorRow("today_color", tr("settings.color.today"), settings.todayColor, synced("today_color"), { toggle("today_color") }) { update(settings.copy(todayColor = it)) }
                SyncColorRow("text_color", tr("settings.color.text"), settings.textColor, synced("text_color"), { toggle("text_color") }) { update(settings.copy(textColor = it)) }
                SyncColorRow("bg_color", tr("settings.color.background"), settings.backgroundColor, synced("bg_color"), { toggle("bg_color") }) { update(settings.copy(backgroundColor = it)) }
                SyncColorRow("line_color", tr("settings.color.line"), settings.lineColor, synced("line_color"), { toggle("line_color") }) { update(settings.copy(lineColor = it)) }
                SyncColorRow("month_divider_color", tr("settings.color.divider"), settings.monthDividerColor, synced("month_divider_color"), { toggle("month_divider_color") }) { update(settings.copy(monthDividerColor = it)) }
                SyncColorRow("month_label_color", tr("settings.color.label"), settings.monthLabelColor, synced("month_label_color"), { toggle("month_label_color") }) { update(settings.copy(monthLabelColor = it)) }
                Divider(Modifier.padding(vertical = 16.dp))

                // ---- Cache (synced) ----
                SyncDropdownRow(
                    tr("settings.cache.range"),
                    listOf("1" to tr("settings.cache.1m"), "3" to tr("settings.cache.3m"), "6" to tr("settings.cache.6m"), "12" to tr("settings.cache.1y")),
                    settings.cacheMonths.toString(),
                    { update(settings.copy(cacheMonths = it.toInt())) },
                    synced("cache_months"), { toggle("cache_months") },
                )
                Divider(Modifier.padding(vertical = 16.dp))

                // ---- Gerät (device-local: language + contrast) ----
                Section(tr("settings.device"))
                DeviceDropdownRow(
                    tr("settings.language"),
                    listOf("system" to tr("lang.system"), "de" to tr("lang.german"), "en" to tr("lang.english")),
                    settings.language,
                ) { update(settings.copy(language = it)) }
                DeviceDropdownRow(
                    tr("settings.textcontrast"),
                    listOf("1" to tr("settings.contrast.dark"), "2" to tr("settings.contrast.medium"), "3" to tr("settings.contrast.bright"), "4" to tr("settings.contrast.max")),
                    settings.textContrast.toString(),
                ) { update(settings.copy(textContrast = it.toInt())) }
                DeviceDropdownRow(
                    tr("settings.linecontrast"),
                    listOf("1" to tr("settings.linecontrast.barely"), "2" to tr("settings.linecontrast.subtle"), "3" to tr("settings.linecontrast.normal"), "4" to tr("settings.linecontrast.strong")),
                    settings.lineContrast.toString(),
                ) { update(settings.copy(lineContrast = it.toInt())) }
                var hideMenu by remember { mutableStateOf(vm.hideMenuButton) }
                Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Spacer(Modifier.size(44.dp))
                    Text(tr("settings.hide_menu_button"), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                    Switch(checked = hideMenu, onCheckedChange = { hideMenu = it; vm.hideMenuButton = it })
                }
                Text(tr("settings.device.footer"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 44.dp, top = 6.dp))
                Spacer(Modifier.size(40.dp))
            }
        }
    }
}

@Composable
private fun reminderOptions(): List<Pair<String, String>> = listOf(
    "-1" to tr("reminder.off"), "0" to tr("reminder.at_start"), "5" to "5 min", "15" to "15 min",
    "30" to "30 min", "60" to "1 h", "1440" to tr("reminder.1d"), "10080" to tr("reminder.1w"),
)

@Composable
private fun Section(title: String) {
    Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 8.dp))
}


/** Leading per-row sync toggle: highlighted = synced across devices. */
@Composable
private fun SyncIcon(on: Boolean, onClick: () -> Unit) {
    IconButton(onClick = onClick, modifier = Modifier.size(32.dp)) {
        Icon(
            Icons.Filled.Refresh,
            contentDescription = tr("settings.sync_this"),
            modifier = Modifier.size(18.dp),
            tint = if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// Compact dropdown trigger (a small outlined chip) — much shorter than a full
// OutlinedTextField, so the settings rows aren't inflated.
@Composable
private fun Dropdown(options: List<Pair<String, String>>, selected: String, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val selectedLabel = options.firstOrNull { it.first == selected }?.second ?: selected
    Box {
        Row(
            Modifier
                .clip(RoundedCornerShape(8.dp))
                .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(8.dp))
                .clickable { expanded = true }
                .padding(start = 12.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(selectedLabel, style = MaterialTheme.typography.bodyMedium, maxLines = 1)
            Icon(Icons.Filled.ArrowDropDown, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (key, label) ->
                DropdownMenuItem(text = { Text(label) }, onClick = { onSelect(key); expanded = false })
            }
        }
    }
}

@Composable
private fun SyncDropdownRow(
    label: String,
    options: List<Pair<String, String>>,
    selected: String,
    onSelect: (String) -> Unit,
    synced: Boolean,
    onToggleSync: () -> Unit,
) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        SyncIcon(synced, onToggleSync)
        Spacer(Modifier.size(8.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Dropdown(options, selected, onSelect)
    }
}

@Composable
private fun DeviceDropdownRow(
    label: String,
    options: List<Pair<String, String>>,
    selected: String,
    onSelect: (String) -> Unit,
) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Spacer(Modifier.size(44.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Dropdown(options, selected, onSelect)
    }
}

@Composable
private fun SyncSwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit, synced: Boolean, onToggleSync: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        SyncIcon(synced, onToggleSync)
        Spacer(Modifier.size(8.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun SyncColorRow(
    syncKey: String,
    label: String,
    current: String,
    synced: Boolean,
    onToggleSync: () -> Unit,
    onPick: (String) -> Unit,
) {
    var showPicker by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        SyncIcon(synced, onToggleSync)
        Spacer(Modifier.size(8.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Text(colorFromHex(current).toHex(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.size(12.dp))
        Box(
            Modifier.size(28.dp).clip(CircleShape).background(colorFromHex(current))
                .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape)
                .clickable { showPicker = true },
        )
        TextButton(onClick = { onPick(DEFAULT_COLORS[syncKey] ?: "#000000") }, contentPadding = PaddingValues(horizontal = 8.dp)) {
            Text(tr("settings.reset"), style = MaterialTheme.typography.labelSmall)
        }
    }
    if (showPicker) {
        ColorPickerDialog(
            initial = current,
            title = label,
            onDismiss = { showPicker = false },
            onConfirm = { showPicker = false; onPick(it) },
        )
    }
}

/** Server-backed "Profil" chapter: name, login, email, hide-profile, privacy, shared calendar. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileChapter(vm: SettingsViewModel) {
    val savedLabel = tr("settings.saved")

    Section(tr("settings.nav.profile"))
    OutlinedTextField(
        value = vm.displayName,
        onValueChange = vm::onDisplayNameChange,
        label = { Text(tr("profile.display_name")) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.size(8.dp))
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Text(tr("profile.login_name"), modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(vm.loginName, fontWeight = FontWeight.Medium)
    }
    Spacer(Modifier.size(8.dp))
    OutlinedTextField(
        value = vm.email,
        onValueChange = vm::onEmailChange,
        label = { Text(tr("profile.email")) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.size(8.dp))
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(tr("settings.directory_hidden"), style = MaterialTheme.typography.bodyLarge)
            Text(tr("settings.directory_hidden.desc"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked = vm.directoryHidden, onCheckedChange = vm::onDirectoryHiddenChange)
    }
    Spacer(Modifier.size(8.dp))
    Button(onClick = { vm.saveProfile(savedLabel) }) { Text(tr("event.save")) }
    vm.profileMessage?.let {
        Spacer(Modifier.size(8.dp))
        Text(it, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodySmall)
    }
    Divider(Modifier.padding(vertical = 16.dp))

    Section(tr("settings.privacy"))
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(tr("settings.private_visibility"), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Dropdown(
            listOf("busy" to tr("settings.private.busy"), "hidden" to tr("settings.private.hidden")),
            vm.privateVisibility,
            vm::changePrivateVisibility,
        )
    }
    Spacer(Modifier.size(6.dp))
    Text(tr("settings.private_visibility.desc"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    Divider(Modifier.padding(vertical = 16.dp))

    Section(tr("settings.group_visible"))
    CalendarDropdown(vm)
    Spacer(Modifier.size(6.dp))
    Text(tr("settings.group_visible.desc"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CalendarDropdown(vm: SettingsViewModel) {
    var expanded by remember { mutableStateOf(false) }
    val noneLabel = tr("group.visible.none")
    val selectedLabel = vm.ownLocalCalendars.firstOrNull { it.id == vm.groupVisibleId }?.name ?: noneLabel
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = selectedLabel,
            onValueChange = {},
            readOnly = true,
            label = { Text(tr("settings.group_visible")) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.menuAnchor().fillMaxWidth(),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text(noneLabel) }, onClick = { vm.changeGroupVisible(0); expanded = false })
            vm.ownLocalCalendars.forEach { cal ->
                DropdownMenuItem(text = { Text(cal.name) }, onClick = { vm.changeGroupVisible(cal.id); expanded = false })
            }
        }
    }
}
