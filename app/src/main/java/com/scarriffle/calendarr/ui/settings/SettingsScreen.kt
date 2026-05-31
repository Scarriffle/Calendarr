package com.scarriffle.calendarr.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.scarriffle.calendarr.domain.model.AppSettings
import com.scarriffle.calendarr.domain.model.CalViewType
import com.scarriffle.calendarr.ui.LocalAppSettings
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex

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
                Divider(Modifier.padding(vertical = 16.dp))

                Section(tr("settings.language"))
                ChipRow(
                    options = listOf("system" to tr("lang.system"), "de" to tr("lang.german"), "en" to tr("lang.english")),
                    selected = settings.language,
                    onSelect = { update(settings.copy(language = it)) },
                )
                Divider(Modifier.padding(vertical = 16.dp))

                Section(tr("settings.colors"))
                ColorChooser(tr("settings.color.primary"), settings.primaryColor) { update(settings.copy(primaryColor = it)) }
                ColorChooser(tr("settings.color.accent"), settings.accentColor) { update(settings.copy(accentColor = it)) }
                ColorChooser(tr("settings.color.today"), settings.todayColor) { update(settings.copy(todayColor = it)) }
                Divider(Modifier.padding(vertical = 16.dp))

                Section(tr("settings.hourheight"))
                Text("${settings.hourHeight} dp", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Slider(
                    value = settings.hourHeight.toFloat(),
                    onValueChange = { settings = settings.copy(hourHeight = it.toInt()) },
                    onValueChangeFinished = { update(settings) },
                    valueRange = 28f..100f,
                )
                Spacer(Modifier.size(8.dp))

                Section(tr("settings.textcontrast"))
                ContrastStepper(settings.textContrast) { update(settings.copy(textContrast = it)) }
                Section(tr("settings.linecontrast"))
                ContrastStepper(settings.lineContrast) { update(settings.copy(lineContrast = it)) }
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
private fun ColorChooser(label: String, current: String, onPick: (String) -> Unit) {
    Column(Modifier.padding(vertical = 6.dp)) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PALETTE.forEach { hex ->
                val selected = hex.equals(current, ignoreCase = true)
                Box(
                    Modifier.size(28.dp).clip(CircleShape).background(colorFromHex(hex))
                        .then(if (selected) Modifier.border(2.dp, Color.White, CircleShape) else Modifier)
                        .clickable { onPick(hex) },
                )
            }
        }
    }
}

@Composable
private fun ContrastStepper(value: Int, onChange: (Int) -> Unit) {
    Slider(
        value = value.toFloat(),
        onValueChange = { onChange(it.toInt().coerceIn(1, 4)) },
        valueRange = 1f..4f,
        steps = 2,
    )
}
