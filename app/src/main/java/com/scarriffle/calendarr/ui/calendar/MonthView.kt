package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.ui.LocalAppSettings
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex
import com.scarriffle.calendarr.util.contrastingTextColor
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.time.temporal.IsoFields
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

private const val MONTHS_BACK = 18L
private const val MONTHS_AHEAD = 18L
private val ROW_HEIGHT = 82.dp

private enum class DividerEdge { NONE, TOP, BOTTOM }

/** Continuous, vertically scrolling month calendar (matches the iOS app). */
@Composable
fun MonthView(
    state: CalendarUiState,
    vm: CalendarViewModel,
    listState: LazyListState,
    scrollToTodaySignal: Int,
    monthJumpSignal: Int,
    monthJumpTarget: LocalDate?,
    onVisibleMonthChange: (LocalDate) -> Unit,
    onDayClick: (LocalDate) -> Unit,
    onDayLongPress: (LocalDate) -> Unit,
    onEventClick: (CalEvent) -> Unit,
) {
    val lang = LocalLang.current
    val settings = LocalAppSettings.current
    val mondayFirst = state.weekStartsOnMonday
    val today = LocalDate.now()

    val dividerColor = colorFromHex(settings.monthDividerColor, Color(0xFF7090C0))
    val labelColor = colorFromHex(settings.monthLabelColor, MaterialTheme.colorScheme.onSurfaceVariant)
    val gridColor = MaterialTheme.colorScheme.outline.copy(alpha = gridLineOpacity(settings.lineContrast))
    val secondaryText = MaterialTheme.colorScheme.onBackground.copy(alpha = secondaryTextOpacity(settings.textContrast))

    val firstVisible = remember(mondayFirst) {
        startOfWeek(today.withDayOfMonth(1).minusMonths(MONTHS_BACK), mondayFirst)
    }
    val end = remember(mondayFirst) {
        startOfWeek(today.withDayOfMonth(1).plusMonths(MONTHS_AHEAD), mondayFirst)
    }
    val weekCount = remember(firstVisible, end) {
        (ChronoUnit.WEEKS.between(firstVisible, end).toInt() + 1).coerceAtLeast(1)
    }
    fun weekIndexOf(date: LocalDate): Int =
        ChronoUnit.WEEKS.between(firstVisible, startOfWeek(date, mondayFirst)).toInt().coerceIn(0, weekCount - 1)

    val todayIndex = remember(firstVisible) { weekIndexOf(today) }

    LaunchedEffect(Unit) { listState.scrollToItem((todayIndex - 1).coerceAtLeast(0)) }
    LaunchedEffect(scrollToTodaySignal) {
        if (scrollToTodaySignal > 0) listState.animateScrollToItem((todayIndex - 1).coerceAtLeast(0))
    }
    LaunchedEffect(monthJumpSignal) {
        if (monthJumpSignal > 0 && monthJumpTarget != null) {
            listState.animateScrollToItem(weekIndexOf(monthJumpTarget.withDayOfMonth(1)))
        }
    }
    LaunchedEffect(listState, weekCount) {
        snapshotFlow { listState.firstVisibleItemIndex }
            .map { firstVisible.plusWeeks(it.toLong()).plusDays(3).withDayOfMonth(1) }
            .distinctUntilChanged()
            .collect { month ->
                onVisibleMonthChange(month)
                vm.ensureMonthLoaded(month)
            }
    }

    val eventsByDay = remember(state.events) { buildEventsByDay(state.events) }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(vertical = 3.dp)) {
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

        LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
            items(weekCount) { index ->
                WeekRow(
                    weekStart = firstVisible.plusWeeks(index.toLong()),
                    today = today,
                    eventsByDay = eventsByDay,
                    lang = lang,
                    dividerColor = dividerColor,
                    gridColor = gridColor,
                    labelColor = labelColor,
                    secondaryText = secondaryText,
                    todayColor = colorFromHex(settings.todayColor),
                    onDayClick = onDayClick,
                    onDayLongPress = onDayLongPress,
                    onEventClick = onEventClick,
                )
            }
        }
    }
}

@Composable
private fun WeekRow(
    weekStart: LocalDate,
    today: LocalDate,
    eventsByDay: Map<LocalDate, List<CalEvent>>,
    lang: String,
    dividerColor: Color,
    gridColor: Color,
    labelColor: Color,
    secondaryText: Color,
    todayColor: Color,
    onDayClick: (LocalDate) -> Unit,
    onDayLongPress: (LocalDate) -> Unit,
    onEventClick: (CalEvent) -> Unit,
) {
    val days = (0 until 7).map { weekStart.plusDays(it.toLong()) }
    val boundaryCol = (1 until 7).firstOrNull { days[it].dayOfMonth == 1 }
    val rowStartsNewMonth = days[0].dayOfMonth == 1
    val cwLabel = tr("cal.cw")

    BoxWithConstraints(Modifier.fillMaxWidth().height(ROW_HEIGHT)) {
        val cellW = maxWidth / 7
        Row(Modifier.fillMaxSize()) {
            days.forEachIndexed { idx, day ->
                val edge = when {
                    boundaryCol != null -> if (idx < boundaryCol) DividerEdge.BOTTOM else DividerEdge.TOP
                    rowStartsNewMonth -> DividerEdge.TOP
                    else -> DividerEdge.NONE
                }
                DayCell(
                    day = day,
                    isToday = day == today,
                    isMonday = day.dayOfWeek == DayOfWeek.MONDAY,
                    weekNumber = day.get(IsoFields.WEEK_OF_WEEK_BASED_YEAR),
                    cwLabel = cwLabel,
                    events = eventsByDay[day] ?: emptyList(),
                    lang = lang,
                    edge = edge,
                    dividerColor = dividerColor,
                    gridColor = gridColor,
                    labelColor = labelColor,
                    secondaryText = secondaryText,
                    todayColor = todayColor,
                    onClick = { onDayClick(day) },
                    onLongClick = { onDayLongPress(day) },
                    onEventClick = onEventClick,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                )
            }
        }
        // Vertical connector at the month boundary column (the "step").
        if (boundaryCol != null) {
            Box(
                Modifier
                    .offset(x = cellW * boundaryCol)
                    .width(1.5.dp)
                    .fillMaxHeight()
                    .background(dividerColor),
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DayCell(
    day: LocalDate,
    isToday: Boolean,
    isMonday: Boolean,
    weekNumber: Int,
    cwLabel: String,
    events: List<CalEvent>,
    lang: String,
    edge: DividerEdge,
    dividerColor: Color,
    gridColor: Color,
    labelColor: Color,
    secondaryText: Color,
    todayColor: Color,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onEventClick: (CalEvent) -> Unit,
    modifier: Modifier = Modifier,
) {
    val isFirst = day.dayOfMonth == 1
    val onBg = MaterialTheme.colorScheme.onBackground

    Box(
        modifier = modifier
            .drawBehind {
                val gridW = 0.5.dp.toPx()
                val divW = 1.5.dp.toPx()
                // top border (thick divider on a month boundary, otherwise thin grid)
                if (edge == DividerEdge.TOP) {
                    drawLine(dividerColor, Offset(0f, 0f), Offset(size.width, 0f), divW)
                } else {
                    drawLine(gridColor, Offset(0f, 0f), Offset(size.width, 0f), gridW)
                }
                // bottom border only when the month ends inside this row
                if (edge == DividerEdge.BOTTOM) {
                    drawLine(dividerColor, Offset(0f, size.height), Offset(size.width, size.height), divW)
                }
                // right grid line
                drawLine(gridColor, Offset(size.width, 0f), Offset(size.width, size.height), gridW)
            }
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 1.dp),
    ) {
        Column(
            Modifier.fillMaxSize().padding(top = 3.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (isFirst) {
                    Text(
                        day.month.getDisplayName(TextStyle.SHORT, com.scarriffle.calendarr.ui.L10n.locale(lang)).uppercase(),
                        fontSize = 8.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = labelColor,
                        modifier = Modifier.padding(end = 2.dp),
                    )
                }
                Box(contentAlignment = Alignment.Center) {
                    if (isToday) {
                        Box(Modifier.height(18.dp).width(18.dp).clip(RoundedCornerShape(9.dp)).background(todayColor))
                    }
                    Text(
                        "${day.dayOfMonth}",
                        fontSize = 11.sp,
                        fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal,
                        color = if (isToday) todayColor.contrastingTextColor() else onBg,
                    )
                }
            }
            events.take(3).forEach { ev -> EventChip(ev) { onEventClick(ev) } }
            if (events.size > 3) {
                Text("+${events.size - 3}", fontSize = 8.sp, color = secondaryText)
            }
        }
        // Calendar week number, bottom-right of the Monday cell.
        if (isMonday) {
            Text(
                "$cwLabel $weekNumber",
                fontSize = 8.sp,
                color = secondaryText,
                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 3.dp, bottom = 2.dp),
            )
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

/** Index events by each local day they overlap, for O(1) lookup while scrolling. */
private fun buildEventsByDay(events: List<CalEvent>): Map<LocalDate, List<CalEvent>> {
    val map = HashMap<LocalDate, MutableList<CalEvent>>()
    for (ev in events) {
        val first = localDate(ev.startDate)
        val last = localDate(ev.endDate.minusSeconds(1)).coerceAtLeast(first)
        var d = first
        var guard = 0
        while (!d.isAfter(last) && guard < 400) {
            map.getOrPut(d) { mutableListOf() }.add(ev)
            d = d.plusDays(1)
            guard++
        }
    }
    map.values.forEach { list -> list.sortBy { it.startDate } }
    return map
}
