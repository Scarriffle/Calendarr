package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Divider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.ui.LocalAppSettings
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.util.colorFromHex
import com.scarriffle.calendarr.util.contrastingTextColor
import java.time.LocalDate
import java.time.format.DateTimeFormatter

private val GUTTER = 48.dp

@Composable
fun TimeGridView(
    days: List<LocalDate>,
    state: CalendarUiState,
    vm: CalendarViewModel,
    onEventClick: (CalEvent) -> Unit,
) {
    val hourHeight = LocalAppSettings.current.hourHeight.coerceIn(28, 100).dp
    val dimPast = LocalAppSettings.current.dimPastEvents
    val today = LocalDate.now()
    // Recomputed once per day (not on every recomposition/frame) — Instant.now()
    // was previously called fresh each recomposition, causing visible flicker in
    // the "is this now" past-dimming and wasted allocation.
    val now = remember(today) { java.time.Instant.now() }
    val lang = LocalLang.current

    Column(Modifier.fillMaxSize()) {
        // Day headers (only for multi-day / week view)
        if (days.size > 1) {
            Row(Modifier.fillMaxWidth()) {
                Box(Modifier.width(GUTTER))
                val dayFmt = remember(lang) {
                    DateTimeFormatter.ofPattern("EEE d", com.scarriffle.calendarr.ui.L10n.locale(lang))
                }
                days.forEach { day ->
                    Text(
                        dayFmt.format(day),
                        modifier = Modifier.weight(1f).padding(vertical = 4.dp),
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = if (day == today) FontWeight.Bold else FontWeight.Normal,
                        color = if (day == today) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        // All-day row
        val allDay = days.map { d -> d to vm.eventsOn(d, state.events).filter { it.isAllDay } }
        if (allDay.any { it.second.isNotEmpty() }) {
            Row(Modifier.fillMaxWidth().padding(bottom = 2.dp)) {
                Box(Modifier.width(GUTTER), contentAlignment = Alignment.Center) {
                    Text(com.scarriffle.calendarr.ui.tr("cal.allday"), fontSize = 8.sp, color = MaterialTheme.colorScheme.outline)
                }
                allDay.forEach { (_, evs) ->
                    Column(Modifier.weight(1f).padding(horizontal = 1.dp)) {
                        evs.forEach { ev -> AllDayChip(ev, dimmed = dimPast && ev.endDate.isBefore(now), onClick = { onEventClick(ev) }) }
                    }
                }
            }
            Divider()
        }

        // Scrollable hour grid
        Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Box(Modifier.fillMaxWidth().height(hourHeight * 24)) {
                // Hour lines + labels
                for (h in 0..24) {
                    val y = hourHeight * h.toFloat()
                    Divider(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = GUTTER)
                            .offset(y = y),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                    )
                    if (h < 24) {
                        Text(
                            "%02d:00".format(h),
                            modifier = Modifier.width(GUTTER).offset(y = y + 2.dp).padding(end = 4.dp),
                            textAlign = TextAlign.End,
                            fontSize = 9.sp,
                            color = MaterialTheme.colorScheme.outline,
                        )
                    }
                }

                // Timed events per day column
                days.forEachIndexed { index, day ->
                    val timed = vm.eventsOn(day, state.events).filter { !it.isAllDay }
                    timed.forEach { ev ->
                        TimedEvent(
                            event = ev,
                            day = day,
                            index = index,
                            dayCount = days.size,
                            hourHeight = hourHeight,
                            dimmed = dimPast && ev.endDate.isBefore(now),
                            onClick = { onEventClick(ev) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TimedEvent(
    event: CalEvent,
    day: LocalDate,
    index: Int,
    dayCount: Int,
    hourHeight: androidx.compose.ui.unit.Dp,
    dimmed: Boolean,
    onClick: () -> Unit,
) {
    val startMin = if (localDate(event.startDate).isBefore(day)) 0 else minutesOfDay(event.startDate)
    val endMin = if (localDate(event.endDate).isAfter(day)) 24 * 60 else minutesOfDay(event.endDate)
    val duration = (endMin - startMin).coerceAtLeast(30)
    val top = hourHeight * (startMin / 60f)
    val height = (hourHeight * (duration / 60f))
    val color = colorFromHex(event.effectiveColor)
    val lang = LocalLang.current

    Box(
        modifier = Modifier
            .offset(y = top)
            .columnSlot(index, dayCount)
            .height(height)
            .padding(horizontal = 1.dp, vertical = 0.5.dp)
            .alpha(if (dimmed) 0.45f else 1f)
            .clip(RoundedCornerShape(4.dp))
            .background(color)
            .clickable(onClick = onClick)
            .padding(horizontal = 4.dp, vertical = 2.dp),
    ) {
        Column {
            EventLabel(
                event = event,
                color = color.contrastingTextColor(),
                fontSize = 10.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 2,
            )
            if (height > 36.dp) {
                Text(
                    eventTimeRange(event, lang),
                    fontSize = 8.sp,
                    color = color.contrastingTextColor().copy(alpha = 0.85f),
                )
            }
        }
    }
}

/** Position a child in column [index] of [dayCount] columns, after the gutter. */
private fun Modifier.columnSlot(index: Int, dayCount: Int): Modifier = layout { measurable, constraints ->
    val gutterPx = GUTTER.roundToPx()
    val available = (constraints.maxWidth - gutterPx).coerceAtLeast(0)
    val colWidth = available / dayCount
    val placeable = measurable.measure(
        constraints.copy(minWidth = colWidth, maxWidth = colWidth)
    )
    layout(constraints.maxWidth, placeable.height) {
        placeable.place(gutterPx + colWidth * index, 0)
    }
}

@Composable
private fun AllDayChip(event: CalEvent, dimmed: Boolean, onClick: () -> Unit) {
    val color = colorFromHex(event.effectiveColor)
    Box(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 1.dp)
            .alpha(if (dimmed) 0.45f else 1f)
            .clip(RoundedCornerShape(3.dp))
            .background(color)
            .clickable(onClick = onClick)
            .padding(horizontal = 3.dp, vertical = 1.dp),
    ) {
        EventLabel(event = event, color = color.contrastingTextColor(), fontSize = 9.sp)
    }
}

@Composable
fun DayView(state: CalendarUiState, vm: CalendarViewModel, onEventClick: (CalEvent) -> Unit) {
    TimeGridView(listOf(state.currentDate), state, vm, onEventClick)
}

@Composable
fun WeekView(state: CalendarUiState, vm: CalendarViewModel, onEventClick: (CalEvent) -> Unit) {
    val mondayFirst = state.weekStartsOnMonday
    val dow = state.currentDate.dayOfWeek.value
    val offset = if (mondayFirst) dow - 1 else dow % 7
    val weekStart = state.currentDate.minusDays(offset.toLong())
    val days = (0 until 7).map { weekStart.plusDays(it.toLong()) }
    TimeGridView(days, state, vm, onEventClick)
}
