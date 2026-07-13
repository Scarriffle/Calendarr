package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.scarriffle.calendarr.domain.model.LocalCalendar
import com.scarriffle.calendarr.ui.tr
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Minimal "new birthday" mask (parity with iOS/web): pick a birthday calendar,
 * enter a name and a date (with an optional "year unknown"). Saves an all-day,
 * yearly-recurring local event; the server adds the age suffix and cake icon.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BirthdayDialog(
    calendars: List<LocalCalendar>,
    onDismiss: () -> Unit,
    onSave: (name: String, date: LocalDate, yearKnown: Boolean, calendarId: Int) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var yearUnknown by remember { mutableStateOf(false) }
    var selectedCalId by remember { mutableStateOf(calendars.firstOrNull()?.id ?: -1) }
    var pickedDate by remember { mutableStateOf(LocalDate.now()) }
    var showPicker by remember { mutableStateOf(false) }
    var calMenu by remember { mutableStateOf(false) }

    val hasCalendars = calendars.isNotEmpty()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(tr("birthday.new_title")) },
        text = {
            Column {
                if (!hasCalendars) {
                    Text(tr("birthday.no_calendars"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    OutlinedTextField(
                        name, { name = it },
                        label = { Text(tr("birthday.person")) },
                        singleLine = true, modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.size(8.dp))
                    FilterChip(
                        selected = true, onClick = { showPicker = true },
                        label = { Text("${tr("birthday.date")}: ${formatBirthday(pickedDate, yearUnknown)}") },
                    )
                    Spacer(Modifier.size(8.dp))
                    FilterChip(
                        selected = yearUnknown, onClick = { yearUnknown = !yearUnknown },
                        label = { Text(tr("birthday.year_unknown")) },
                    )
                    if (calendars.size > 1) {
                        Spacer(Modifier.size(8.dp))
                        Box {
                            FilterChip(
                                selected = false, onClick = { calMenu = true },
                                label = { Text(calendars.firstOrNull { it.id == selectedCalId }?.name ?: tr("birthday.target")) },
                            )
                            DropdownMenu(expanded = calMenu, onDismissRequest = { calMenu = false }) {
                                calendars.forEach { c ->
                                    DropdownMenuItem(text = { Text(c.name) }, onClick = { selectedCalId = c.id; calMenu = false })
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = hasCalendars && name.isNotBlank(),
                onClick = { onSave(name.trim(), pickedDate, !yearUnknown, selectedCalId) },
            ) { Text(tr("common.save")) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(tr("common.cancel")) } },
    )

    if (showPicker) {
        val dpState = rememberDatePickerState(
            initialSelectedDateMillis = pickedDate.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { showPicker = false },
            confirmButton = {
                TextButton(onClick = {
                    dpState.selectedDateMillis?.let { millis ->
                        pickedDate = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                    }
                    showPicker = false
                }) { Text(tr("common.save")) }
            },
            dismissButton = { TextButton(onClick = { showPicker = false }) { Text(tr("common.cancel")) } },
        ) { DatePicker(state = dpState) }
    }
}

private val DAY_MONTH = DateTimeFormatter.ofPattern("dd.MM.")
private val DAY_MONTH_YEAR = DateTimeFormatter.ofPattern("dd.MM.yyyy")

private fun formatBirthday(date: LocalDate, yearUnknown: Boolean): String =
    date.format(if (yearUnknown) DAY_MONTH else DAY_MONTH_YEAR)
