package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Composable
fun AgendaView(
    state: CalendarUiState,
    vm: CalendarViewModel,
    onEventClick: (CalEvent) -> Unit,
) {
    val lang = LocalLang.current
    val dimPast = com.scarriffle.calendarr.ui.LocalAppSettings.current.dimPastEvents
    val now = java.time.Instant.now()
    val today = LocalDate.now()
    val days = (0 until 90).map { today.plusDays(it.toLong()) }
        .map { it to vm.eventsOn(it, state.events) }
        .filter { it.second.isNotEmpty() }

    if (days.isEmpty()) {
        Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(tr("cal.no_events_title"), style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(6.dp))
                Text(
                    tr("cal.no_events_body"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        return
    }

    val headerFmt = DateTimeFormatter.ofPattern("EEEE, d. MMMM", com.scarriffle.calendarr.ui.L10n.locale(lang))

    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 12.dp)) {
        days.forEach { (date, events) ->
            item(key = "h-$date") {
                Text(
                    headerFmt.format(date).replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = if (date == today) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onBackground,
                    modifier = Modifier.padding(top = 16.dp, bottom = 6.dp),
                )
            }
            items(events, key = { "${date}-${it.id}" }) { ev ->
                AgendaRow(ev, lang, dimmed = dimPast && ev.endDate.isBefore(now), onClick = { onEventClick(ev) })
            }
        }
        item { Spacer(Modifier.height(80.dp)) }
    }
}

@Composable
private fun AgendaRow(event: CalEvent, lang: String, dimmed: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .alpha(if (dimmed) 0.45f else 1f)
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.surface)
            .clickable(onClick = onClick)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(10.dp).clip(CircleShape).background(colorFromHex(event.effectiveColor)))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(event.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            if (event.location.isNotBlank()) {
                Text(event.location, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Spacer(Modifier.width(8.dp))
        Text(
            eventTimeRange(event, lang),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
