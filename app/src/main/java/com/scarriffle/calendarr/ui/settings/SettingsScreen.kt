package com.scarriffle.calendarr.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
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

private val PALETTE = listOf(
    "#4285f4", "#ea4335", "#34a853", "#fbbc05", "#46bdc6", "#9c27b0", "#ff7043", "#7090c0",
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
    var cacheMonths by remember { mutableStateOf(vm.cacheMonths) }

    fun update(newSettings: AppSettings) {
        settings = newSettings
        onSettingsChanged(newSettings)
        vm.apply(newSettings, onSettingsSynced)
    }

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

                ProfileChapter(vm)
                Divider(Modifier.padding(vertical = 16.dp))

                Section(tr("settings.calview"))
                ChipRow(
                    options = CalViewType.entries.map { it.key to tr("view.${it.key}") },
                    selected = settings.defaultView,
                    onSelect = { update(settings.copy(defaultView = it)) },
                )
                Spacer(Modifier.size(16.dp))

                Section(tr("settings.firstweekday"))
                ChipRow(
                    options = listOf("monday" to tr("settings.monday"), "sunday" to tr("settings.sunday")),
                    selected = settings.weekStartDay,
                    onSelect = { update(settings.copy(weekStartDay = it)) },
                )
                Spacer(Modifier.size(16.dp))

                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(tr("settings.dimpast"), style = MaterialTheme.typography.bodyLarge)
                    Switch(checked = settings.dimPastEvents, onCheckedChange = { update(settings.copy(dimPastEvents = it)) })
                }
                Spacer(Modifier.size(16.dp))

                Section(tr("settings.default_duration"))
                ChipRow(
                    options = listOf(
                        "15" to "15 min", "30" to "30 min", "45" to "45 min",
                        "60" to "1 h", "90" to "1.5 h", "120" to "2 h",
                    ),
                    selected = settings.defaultEventDurationMinutes.toString(),
                    onSelect = { update(settings.copy(defaultEventDurationMinutes = it.toInt())) },
                )
                Divider(Modifier.padding(vertical = 16.dp))

                Section(tr("settings.language"))
                ChipRow(
                    options = listOf("system" to tr("lang.system"), "de" to tr("lang.german"), "en" to tr("lang.english")),
                    selected = settings.language,
                    onSelect = { update(settings.copy(language = it)) },
                )
                Divider(Modifier.padding(vertical = 16.dp))

                Section(tr("settings.colors"))
                ColorRow(tr("settings.color.primary"), settings.primaryColor) { update(settings.copy(primaryColor = it)) }
                ColorRow(tr("settings.color.accent"), settings.accentColor) { update(settings.copy(accentColor = it)) }
                ColorRow(tr("settings.color.today"), settings.todayColor) { update(settings.copy(todayColor = it)) }
                ColorRow(tr("settings.color.divider"), settings.monthDividerColor) { update(settings.copy(monthDividerColor = it)) }
                ColorRow(tr("settings.color.label"), settings.monthLabelColor) { update(settings.copy(monthLabelColor = it)) }
                Divider(Modifier.padding(vertical = 16.dp))

                Section(tr("settings.hourheight"))
                ChipRow(
                    options = listOf(
                        "28" to tr("settings.hourheight.compact"),
                        "44" to tr("settings.hourheight.normal"),
                        "60" to tr("settings.hourheight.comfort"),
                        "80" to tr("settings.hourheight.large"),
                    ),
                    selected = settings.hourHeight.toString(),
                    onSelect = { update(settings.copy(hourHeight = it.toInt())) },
                )
                Spacer(Modifier.size(16.dp))

                Section(tr("settings.textcontrast"))
                ChipRow(
                    options = listOf(
                        "1" to tr("settings.contrast.dark"), "2" to tr("settings.contrast.medium"),
                        "3" to tr("settings.contrast.bright"), "4" to tr("settings.contrast.max"),
                    ),
                    selected = settings.textContrast.toString(),
                    onSelect = { update(settings.copy(textContrast = it.toInt())) },
                )
                Spacer(Modifier.size(16.dp))
                Section(tr("settings.linecontrast"))
                ChipRow(
                    options = listOf(
                        "1" to tr("settings.linecontrast.barely"), "2" to tr("settings.linecontrast.subtle"),
                        "3" to tr("settings.linecontrast.normal"), "4" to tr("settings.linecontrast.strong"),
                    ),
                    selected = settings.lineContrast.toString(),
                    onSelect = { update(settings.copy(lineContrast = it.toInt())) },
                )
                Divider(Modifier.padding(vertical = 16.dp))

                Section(tr("settings.cache.title"))
                ChipRow(
                    options = listOf("1" to tr("settings.cache.1m"), "3" to tr("settings.cache.3m"), "6" to tr("settings.cache.6m"), "12" to tr("settings.cache.1y")),
                    selected = cacheMonths.toString(),
                    onSelect = { cacheMonths = it.toInt(); vm.cacheMonths = it.toInt() },
                )
                Spacer(Modifier.size(40.dp))
            }
        }
    }
}

@Composable
private fun Section(title: String) {
    Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 8.dp))
}

/** Server-backed "Profil" chapter: display name, login name, email, privacy, shared calendar. */
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
    Button(onClick = { vm.saveProfile(savedLabel) }) { Text(tr("event.save")) }
    vm.profileMessage?.let {
        Spacer(Modifier.size(8.dp))
        Text(it, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodySmall)
    }
    Divider(Modifier.padding(vertical = 16.dp))

    Section(tr("settings.privacy"))
    ChipRow(
        options = listOf("busy" to tr("settings.private.busy"), "hidden" to tr("settings.private.hidden")),
        selected = vm.privateVisibility,
        onSelect = vm::changePrivateVisibility,
    )
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChipRow(options: List<Pair<String, String>>, selected: String, onSelect: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { (key, label) ->
            FilterChip(selected = key == selected, onClick = { onSelect(key) }, label = { Text(label) })
        }
    }
}

@Composable
private fun ColorRow(label: String, current: String, onPick: (String) -> Unit) {
    var showPicker by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().clickable { showPicker = true }.padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(28.dp).clip(CircleShape).background(colorFromHex(current)).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape))
        Spacer(Modifier.size(12.dp))
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Text(colorFromHex(current).toHex(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
