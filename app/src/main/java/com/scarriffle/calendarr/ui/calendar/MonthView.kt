package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Divider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
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
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit

private const val MONTHS_BACK = 18L
private const val MONTHS_AHEAD = 18L

/**
 * Continuous, vertically scrolling month calendar (matches the iOS app).
 * There are no prev/next buttons — the user scrolls through weeks and the
 * top-bar title follows the currently visible month.
 */
@Composable
fun MonthView(
    state: CalendarUiState,
    vm: CalendarViewModel,
    listState: LazyListState,
    scrollToTodaySignal: Int,
    onVisibleMonthChange: (LocalDate) -> Unit,
    onDayClick: (LocalDate) -> Unit,
    onDayLongPress: (LocalDate) -> Unit,
    onEventClick: (CalEvent) -> Unit,
) {
    val lang = LocalLang.current
    val mondayFirst = state.weekStartsOnMonday
    val today = LocalDate.now()

    val firstVisible = remember(mondayFirst) {
        startOfWeek(today.withDayOfMonth(1).minusMonths(MONTHS_BACK), mondayFirst)
    }
    val end = remember(mondayFirst) {
        startOfWeek(today.withDayOfMonth(1).plusMonths(MONTHS_AHEAD), mondayFirst)
    }
    val weekCount = remember(firstVisible, end) {
        (ChronoUnit.WEEKS.between(firstVisible, end).toInt() + 1).coerceAtLeast(1)
    }
    val todayIndex = remember(firstVisible) {
        ChronoUnit.WEEKS.between(firstVisible, startOfWeek(today, mondayFirst)).toInt()
    }

    // Initial scroll to today's week.
    LaunchedEffect(Unit) {
        listState.scrollToItem((todayIndex - 1).coerceAtLeast(0))
    }
    // "Today" button.
    LaunchedEffect(scrollToTodaySignal) {
        if (scrollToTodaySignal > 0) listState.animateScrollToItem((todayIndex - 1).coerceAtLeast(0))
    }
    // Track visible month + trigger on-demand loads.
    LaunchedEffect(listState, weekCount) {
        snapshotFlow { listState.firstVisibleItemIndex }.collect { idx ->
            val weekStart = firstVisible.plusWeeks(idx.toLong())
            val month = weekStart.plusDays(3) // mid-week → representative month
            onVisibleMonthChange(month)
            vm.ensureMonthLoaded(month)
        }
    }

    Column(Modifier.fillMaxSize()) {
        // Fixed weekday header
        Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
            weekdayLabels(mondayFirst, lang).forEach { label ->
                Text(
                    label,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Divider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))

        LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
            items(weekCount) { index ->
                val weekStart = firstVisible.plusWeeks(index.toLong())
                WeekRow(
                    weekStart = weekStart,
                    today = today,
                    events = state.events,
                    vm = vm,
                    lang = lang,
                    onDayClick = onDayClick,
                    onDayLongPress = onDayLongPress,
                    onEventClick = onEventClick,
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun WeekRow(
    weekStart: LocalDate,
    today: LocalDate,
    events: List<CalEvent>,
    vm: CalendarViewModel,
    lang: String,
    onDayClick: (LocalDate) -> Unit,
    onDayLongPress: (LocalDate) -> Unit,
    onEventClick: (CalEvent) -> Unit,
) {
    val days = (0 until 7).map { weekStart.plusDays(it.toLong()) }
    Row(
        Modifier
            .fillMaxWidth()
            .height(78.dp),
    ) {
        days.forEach { day ->
            DayCell(
                day = day,
                isToday = day == today,
                events = vm.eventsOn(day, events),
                lang = lang,
                onClick = { onDayClick(day) },
                onLongClick = { onDayLongPress(day) },
                onEventClick = onEventClick,
                modifier = Modifier.weight(1f).fillMaxSize(),
            )
        }
    }
    Divider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DayCell(
    day: LocalDate,
    isToday: Boolean,
    events: List<CalEvent>,
    lang: String,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onEventClick: (CalEvent) -> Unit,
    modifier: Modifier = Modifier,
) {
    val settings = LocalAppSettings.current
    val todayColor = colorFromHex(settings.todayColor)
    val monthLabelColor = colorFromHex(settings.monthLabelColor, MaterialTheme.colorScheme.onSurfaceVariant)
    val isFirst = day.dayOfMonth == 1

    Column(
        modifier = modifier
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 1.dp, vertical = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (isFirst) {
                Text(
                    day.month.getDisplayName(TextStyle.SHORT, com.scarriffle.calendarr.ui.L10n.locale(lang)),
                    fontSize = 8.sp,
                    color = monthLabelColor,
                    modifier = Modifier.padding(end = 2.dp),
                )
            }
            Box(contentAlignment = Alignment.Center) {
                if (isToday) {
                    Box(
                        Modifier
                            .height(18.dp)
                            .width(18.dp)
                            .clip(RoundedCornerShape(9.dp))
                            .background(todayColor),
                    )
                }
                Text(
                    "${day.dayOfMonth}",
                    fontSize = 11.sp,
                    fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal,
                    color = if (isToday) todayColor.contrastingTextColor() else MaterialTheme.colorScheme.onBackground,
                )
            }
        }
        events.take(3).forEach { ev -> EventChip(ev) { onEventClick(ev) } }
        if (events.size > 3) {
            Text("+${events.size - 3}", fontSize = 8.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun EventChip(event: CalEvent, onClick: () -> Unit) {
    val color = colorFromHex(event.effectiveColor)
    Surface(
        color = color,
        shape = RoundedCornerShape(3.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 1.dp, vertical = 0.5.dp)
            .clickable(onClick = onClick),
    ) {
        Text(
            event.title,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            fontSize = 8.sp,
            color = color.contrastingTextColor(),
            modifier = Modifier.padding(horizontal = 3.dp, vertical = 1.dp),
        )
    }
}

private fun startOfWeek(date: LocalDate, mondayFirst: Boolean): LocalDate {
    val dow = date.dayOfWeek.value
    val offset = if (mondayFirst) dow - 1 else dow % 7
    return date.minusDays(offset.toLong())
}
