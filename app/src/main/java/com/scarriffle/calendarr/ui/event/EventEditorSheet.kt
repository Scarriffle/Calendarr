package com.scarriffle.calendarr.ui.event

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.IconButton
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.domain.model.ReminderOptions
import com.scarriffle.calendarr.domain.model.WritableCalendar
import com.scarriffle.calendarr.ui.L10n
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.ui.calendar.EditorRequest
import com.scarriffle.calendarr.ui.calendar.calendarKey
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val PRESET_COLORS = listOf(
    "#4285f4", "#ea4335", "#34a853", "#fbbc05",
    "#46bdc6", "#9c27b0", "#ff7043", "#7090c0",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventEditorSheet(
    request: EditorRequest,
    writableCalendars: List<WritableCalendar>,
    onDismiss: () -> Unit,
    defaultDurationMinutes: Int = 60,
    reminderDisabledKeys: Set<String> = emptySet(),
    onSave: (WritableCalendar, String, Instant, Instant, Boolean, String, String, String?, Boolean, List<Int>) -> Unit,
) {
    val zone = ZoneId.systemDefault()
    val context = LocalContext.current
    val lang = LocalLang.current
    val existing = request.existing
    // Fields are prefilled from the event being edited OR copied.
    val template = existing ?: request.prefill
    val isCopy = existing == null && request.prefill != null
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var title by remember { mutableStateOf(template?.title ?: "") }
    var allDay by remember { mutableStateOf(template?.isAllDay ?: false) }
    var location by remember { mutableStateOf(template?.location ?: "") }
    var description by remember { mutableStateOf(template?.notes ?: "") }
    var color by remember { mutableStateOf(template?.color) }
    var isPrivate by remember { mutableStateOf(template?.isPrivate ?: false) }

    val initialStart = template?.startDate
    val initialEnd = template?.endDate
    var startDate by remember {
        mutableStateOf(initialStart?.let { LocalDate.ofInstant(it, zone) } ?: request.date)
    }
    var startTime by remember {
        mutableStateOf(initialStart?.let { LocalTime.ofInstant(it, zone).withSecond(0).withNano(0) } ?: LocalTime.of(9, 0))
    }
    // New events default to start (09:00) + the user's default duration.
    val defaultEnd = request.date.atTime(9, 0).plusMinutes(defaultDurationMinutes.toLong())
    var endDate by remember {
        mutableStateOf(
            initialEnd?.let {
                val d = LocalDate.ofInstant(it, zone)
                if (template?.isAllDay == true) d.minusDays(1) else d
            } ?: defaultEnd.toLocalDate()
        )
    }
    var endTime by remember {
        mutableStateOf(initialEnd?.let { LocalTime.ofInstant(it, zone).withSecond(0).withNano(0) } ?: defaultEnd.toLocalTime())
    }
    var reminders by remember { mutableStateOf(template?.reminders ?: emptyList<Int>()) }

    val preselected = template?.let { ev ->
        val id = calendarKey(ev.source, ev.calendarId).substringAfter(":").toIntOrNull()
        writableCalendars.firstOrNull { it.source == ev.source && it.numericId == id }
    }
    var calendar by remember { mutableStateOf(preselected ?: writableCalendars.firstOrNull()) }
    var calMenuOpen by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    val dateFmt = DateTimeFormatter.ofPattern("EEE, d. MMM yyyy")
    val timeFmt = DateTimeFormatter.ofPattern("HH:mm")

    fun pickDate(current: LocalDate, onPicked: (LocalDate) -> Unit) {
        DatePickerDialog(
            context,
            { _, y, m, d -> onPicked(LocalDate.of(y, m + 1, d)) },
            current.year, current.monthValue - 1, current.dayOfMonth,
        ).show()
    }

    fun pickTime(current: LocalTime, onPicked: (LocalTime) -> Unit) {
        TimePickerDialog(
            context,
            { _, h, min -> onPicked(LocalTime.of(h, min)) },
            current.hour, current.minute, true,
        ).show()
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            Text(
                when {
                    existing != null -> tr("event.edit_title")
                    isCopy -> tr("event.copy_title")
                    else -> tr("event.new_title")
                },
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(vertical = 8.dp),
            )

            OutlinedTextField(
                value = title,
                onValueChange = { title = it; error = null },
                label = { Text(tr("event.title_placeholder")) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.size(12.dp))

            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                Text(tr("event.allday"), style = MaterialTheme.typography.bodyLarge)
                Switch(checked = allDay, onCheckedChange = { allDay = it })
            }
            Spacer(Modifier.size(8.dp))

            // Start
            Text(tr("event.start"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { pickDate(startDate) { startDate = it; if (endDate.isBefore(it)) endDate = it } }) {
                    Text(dateFmt.format(startDate))
                }
                if (!allDay) {
                    OutlinedButton(onClick = { pickTime(startTime) { startTime = it } }) { Text(timeFmt.format(startTime)) }
                }
            }
            Spacer(Modifier.size(8.dp))

            // End
            Text(tr("event.end"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { pickDate(endDate) { endDate = it } }) { Text(dateFmt.format(endDate)) }
                if (!allDay) {
                    OutlinedButton(onClick = { pickTime(endTime) { endTime = it } }) { Text(timeFmt.format(endTime)) }
                }
            }
            Spacer(Modifier.size(12.dp))

            OutlinedTextField(
                value = location,
                onValueChange = { location = it },
                label = { Text(tr("event.location")) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.size(12.dp))
            OutlinedTextField(
                value = description,
                onValueChange = { description = it },
                label = { Text(tr("event.description")) },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.size(12.dp))

            // Calendar picker
            Text(tr("event.calendar_section"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (writableCalendars.isEmpty()) {
                Text(tr("event.no_writable"), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            } else {
                Box {
                    OutlinedButton(onClick = { calMenuOpen = true }, modifier = Modifier.fillMaxWidth()) {
                        Box(Modifier.size(12.dp).clip(CircleShape).background(colorFromHex(calendar?.color)))
                        Spacer(Modifier.size(8.dp))
                        Text(calendar?.name ?: tr("event.calendar_picker"), modifier = Modifier.weight(1f))
                        Icon(Icons.Filled.ArrowDropDown, contentDescription = null)
                    }
                    DropdownMenu(expanded = calMenuOpen, onDismissRequest = { calMenuOpen = false }) {
                        writableCalendars.forEach { c ->
                            DropdownMenuItem(
                                text = { Text(c.name) },
                                leadingIcon = { Box(Modifier.size(12.dp).clip(CircleShape).background(colorFromHex(c.color))) },
                                onClick = { calendar = c; calMenuOpen = false },
                            )
                        }
                    }
                }
            }
            Spacer(Modifier.size(12.dp))

            // Private + reminders (local calendars only)
            if (calendar?.source == "local") {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(tr("event.private"), style = MaterialTheme.typography.bodyLarge)
                    Switch(checked = isPrivate, onCheckedChange = { isPrivate = it })
                }
                Spacer(Modifier.size(12.dp))

                val remindersDisabled = calendar?.let {
                    reminderDisabledKeys.contains(calendarKey(it.source, it.numericId.toString()))
                } ?: false
                Text(tr("event.reminders"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (remindersDisabled) {
                    Text(
                        tr("event.reminders_disabled"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.tertiary,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
                reminders.forEachIndexed { idx, min ->
                    ReminderRow(
                        minutes = min,
                        enabled = !remindersDisabled,
                        onChange = { v -> reminders = reminders.toMutableList().also { it[idx] = v } },
                        onRemove = { reminders = reminders.toMutableList().also { it.removeAt(idx) } },
                    )
                }
                androidx.compose.material3.TextButton(
                    enabled = !remindersDisabled,
                    onClick = {
                        val next = ReminderOptions.presets.firstOrNull { it !in reminders } ?: ReminderOptions.customDefault
                        reminders = reminders + next
                    },
                ) { Text(tr("event.reminder_add")) }
                Spacer(Modifier.size(12.dp))
            }

            // Color
            Text(tr("event.color_section"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PRESET_COLORS.forEach { hex ->
                    val selected = color?.equals(hex, ignoreCase = true) == true
                    Box(
                        Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(colorFromHex(hex))
                            .then(if (selected) Modifier.border(2.dp, Color.White, CircleShape) else Modifier)
                            .clickable { color = hex },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (selected) Icon(Icons.Filled.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                    }
                }
            }
            if (color != null) {
                androidx.compose.material3.TextButton(onClick = { color = null }) { Text(tr("event.reset_color")) }
            }

            error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 8.dp))
            }
            Spacer(Modifier.size(16.dp))
            Button(
                onClick = {
                    val cal = calendar
                    if (title.isBlank()) { error = L10n.t("event.title_placeholder", lang); return@Button }
                    if (cal == null) { error = L10n.t("event.no_writable", lang); return@Button }
                    val start: Instant
                    val end: Instant
                    if (allDay) {
                        start = startDate.atStartOfDay(zone).toInstant()
                        end = endDate.plusDays(1).atStartOfDay(zone).toInstant()
                    } else {
                        start = startDate.atTime(startTime).atZone(zone).toInstant()
                        end = endDate.atTime(endTime).atZone(zone).toInstant()
                    }
                    val rem = if (cal.source == "local") reminders else emptyList()
                    onSave(cal, title.trim(), start, end, allDay, location.trim(), description.trim(), color, isPrivate && cal.source == "local", rem)
                },
                enabled = writableCalendars.isNotEmpty(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (existing == null) tr("event.add") else tr("event.save"))
            }
        }
    }
}

/** One reminder row: a preset dropdown plus, in custom mode, a number field +
 *  unit dropdown. The value is always emitted as minutes-before-start. */
@Composable
private fun ReminderRow(
    minutes: Int,
    enabled: Boolean,
    onChange: (Int) -> Unit,
    onRemove: () -> Unit,
) {
    val isPreset = minutes in ReminderOptions.presets
    var presetMenu by remember { mutableStateOf(false) }
    var unitMenu by remember { mutableStateOf(false) }

    @Composable
    fun label(min: Int): String =
        if (min == 0) tr("event.reminder_at_start")
        else ReminderOptions.split(min).let { (v, u) -> "$v ${tr(u.labelKey)} ${tr("event.reminder_before")}" }

    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f)) {
                OutlinedButton(onClick = { presetMenu = true }, enabled = enabled, modifier = Modifier.fillMaxWidth()) {
                    Text(if (isPreset) label(minutes) else tr("event.reminder_custom"), modifier = Modifier.weight(1f))
                    Icon(Icons.Filled.ArrowDropDown, contentDescription = null)
                }
                DropdownMenu(expanded = presetMenu, onDismissRequest = { presetMenu = false }) {
                    ReminderOptions.presets.forEach { p ->
                        DropdownMenuItem(text = { Text(label(p)) }, onClick = { onChange(p); presetMenu = false })
                    }
                    DropdownMenuItem(text = { Text(tr("event.reminder_custom")) }, onClick = {
                        if (minutes in ReminderOptions.presets) onChange(ReminderOptions.customDefault)
                        presetMenu = false
                    })
                }
            }
            IconButton(onClick = onRemove, enabled = enabled) {
                Icon(Icons.Filled.Close, contentDescription = null)
            }
        }
        if (!isPreset) {
            val (value, unit) = ReminderOptions.split(minutes)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = value.toString(),
                    onValueChange = { txt ->
                        val n = txt.filter { it.isDigit() }.toIntOrNull()?.coerceAtLeast(1) ?: 1
                        onChange(n * unit.mult)
                    },
                    enabled = enabled,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.width(96.dp),
                )
                Box {
                    OutlinedButton(onClick = { unitMenu = true }, enabled = enabled) {
                        Text(tr(unit.labelKey))
                        Icon(Icons.Filled.ArrowDropDown, contentDescription = null)
                    }
                    DropdownMenu(expanded = unitMenu, onDismissRequest = { unitMenu = false }) {
                        ReminderOptions.Unit.values().forEach { u ->
                            DropdownMenuItem(text = { Text(tr(u.labelKey)) }, onClick = { onChange(value * u.mult); unitMenu = false })
                        }
                    }
                }
                Text(tr("event.reminder_before"), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
