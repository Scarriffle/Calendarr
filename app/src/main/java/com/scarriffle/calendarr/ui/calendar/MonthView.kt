package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.ui.LocalAppSettings
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.util.colorFromHex
import com.scarriffle.calendarr.util.contrastingTextColor
import java.time.LocalDate
import java.time.temporal.IsoFields

@Composable
fun MonthView(
    state: CalendarUiState,
    vm: CalendarViewModel,
    onDayClick: (LocalDate) -> Unit,
    onEventClick: (CalEvent) -> Unit,
) {
    val lang = LocalLang.current
    val mondayFirst = state.weekStartsOnMonday
    val today = LocalDate.now()
    val firstOfMonth = state.currentDate.withDayOfMonth(1)
    val firstVisible = startOfWeekFor(firstOfMonth, mondayFirst)
    val weeks = (0 until 6).map { w -> (0 until 7).map { d -> firstVisible.plusDays((w * 7 + d).toLong()) } }

    Column(Modifier.fillMaxSize()) {
        // Header: CW + weekdays
        Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
            Box(Modifier.width(28.dp))
            weekdayLabels(mondayFirst, lang).forEach { label ->
                Text(
                    label,
                    modifier = Modifier.weight(1f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        weeks.forEach { week ->
            Row(Modifier.fillMaxWidth().weight(1f)) {
                val cw = week.first().get(IsoFields.WEEK_OF_WEEK_BASED_YEAR)
                Box(Modifier.width(28.dp).fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                    Text(
                        "$cw",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.outline,
                        fontSize = 9.sp,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
                week.forEach { day ->
                    DayCell(
                        day = day,
                        inMonth = day.month == firstOfMonth.month,
                        isToday = day == today,
                        events = vm.eventsOn(day, state.events),
                        onClick = { onDayClick(day) },
                        onEventClick = onEventClick,
                        modifier = Modifier.weight(1f).fillMaxSize(),
                    )
                }
            }
        }
    }
}

@Composable
private fun DayCell(
    day: LocalDate,
    inMonth: Boolean,
    isToday: Boolean,
    events: List<CalEvent>,
    onClick: () -> Unit,
    onEventClick: (CalEvent) -> Unit,
    modifier: Modifier = Modifier,
) {
    val todayColor = colorFromHex(LocalAppSettings.current.todayColor)
    Column(
        modifier = modifier
            .padding(1.dp)
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.padding(top = 2.dp)) {
            if (isToday) {
                Box(
                    Modifier
                        .height(22.dp).width(22.dp)
                        .clip(RoundedCornerShape(11.dp))
                        .background(todayColor),
                )
            }
            Text(
                "${day.dayOfMonth}",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal,
                color = when {
                    isToday -> todayColor.contrastingTextColor()
                    inMonth -> MaterialTheme.colorScheme.onBackground
                    else -> MaterialTheme.colorScheme.outline
                },
            )
        }
        events.take(3).forEach { ev ->
            EventChip(ev, onClick = { onEventClick(ev) })
        }
        if (events.size > 3) {
            Text(
                "+${events.size - 3}",
                style = MaterialTheme.typography.labelSmall,
                fontSize = 8.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun EventChip(event: CalEvent, onClick: () -> Unit) {
    val color = colorFromHex(event.effectiveColor)
    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 1.dp, vertical = 1.dp)
            .clip(RoundedCornerShape(3.dp))
            .background(color)
            .clickable(onClick = onClick)
            .padding(horizontal = 3.dp, vertical = 1.dp),
    ) {
        Text(
            event.title,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            fontSize = 9.sp,
            color = color.contrastingTextColor(),
        )
    }
}

private fun startOfWeekFor(date: LocalDate, mondayFirst: Boolean): LocalDate {
    val dow = date.dayOfWeek.value
    val offset = if (mondayFirst) dow - 1 else dow % 7
    return date.minusDays(offset.toLong())
}
