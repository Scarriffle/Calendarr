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
private const val MAX_LANES = 4
private val DAY_NUM_H = 22.dp
private val LANE_H = 15.dp
private val LANE_SPACE = 2.dp
private val ROW_HEIGHT = DAY_NUM_H + (LANE_H + LANE_SPACE) * MAX_LANES + 6.dp

private enum class DividerEdge { NONE, TOP, BOTTOM }

/** One placed event bar within a week: which lane and which columns it spans. */
private data class PlacedBar(val event: CalEvent, val lane: Int, val startCol: Int, val span: Int)

/** Continuous, vertically scrolling month calendar with multi-day event bars (iOS-style). */
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
    val todayColor = colorFromHex(settings.todayColor)

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

    // One pass: bucket events into the weeks they overlap (keyed by week-start).
    val eventsByWeek = remember(state.events, mondayFirst) { buildEventsByWeek(state.events, mondayFirst) }

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
                val weekStart = firstVisible.plusWeeks(index.toLong())
                WeekRow(
                    weekStart = weekStart,
                    today = today,
                    weekEvents = eventsByWeek[weekStart] ?: emptyList(),
                    lang = lang,
                    dividerColor = dividerColor,
                    gridColor = gridColor,
                    labelColor = labelColor,
                    secondaryText = secondaryText,
                    todayColor = todayColor,
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
    weekEvents: List<CalEvent>,
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

    // Greedy first-fit lane packing for this week (memoized).
    val packed = remember(weekStart, weekEvents) { packEvents(weekStart, weekEvents) }

    BoxWithConstraints(Modifier.fillMaxWidth().height(ROW_HEIGHT)) {
        val cellW = maxWidth / 7

        // Layer 1: day cell backgrounds (borders, day number, KW, overflow count)
        Row(Modifier.fillMaxSize()) {
            days.forEachIndexed { idx, day ->
                val edge = when {
                    boundaryCol != null -> if (idx < boundaryCol) DividerEdge.BOTTOM else DividerEdge.TOP
                    rowStartsNewMonth -> DividerEdge.TOP
                    else -> DividerEdge.NONE
                }
                DayCellBackground(
                    day = day,
                    isToday = day == today,
                    isMonday = day.dayOfWeek == DayOfWeek.MONDAY,
                    weekNumber = day.get(IsoFields.WEEK_OF_WEEK_BASED_YEAR),
                    cwLabel = cwLabel,
                    overflow = packed.overflowPerCol[idx],
                    lang = lang,
                    edge = edge,
                    dividerColor = dividerColor,
                    gridColor = gridColor,
                    labelColor = labelColor,
                    secondaryText = secondaryText,
                    todayColor = todayColor,
                    onClick = { onDayClick(day) },
                    onLongClick = { onDayLongPress(day) },
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                )
            }
        }

        // Layer 2: event bars (absolute, span multiple columns)
        packed.bars.forEach { bar ->
            EventBar(
                bar = bar,
                cellW = cellW,
                onClick = { onEventClick(bar.event) },
            )
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

@Composable
private fun EventBar(bar: PlacedBar, cellW: androidx.compose.ui.unit.Dp, onClick: () -> Unit) {
    val color = colorFromHex(bar.event.effectiveColor)
    Box(
        Modifier
            .offset(
                x = cellW * bar.startCol + 1.dp,
                y = DAY_NUM_H + (LANE_H + LANE_SPACE) * bar.lane,
            )
            .width(cellW * bar.span - 2.dp)
            .height(LANE_H)
            .clip(RoundedCornerShape(3.dp))
            .background(color)
            .clickable(onClick = onClick)
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(
            bar.event.title,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            fontSize = 10.sp,
            fontWeight = FontWeight.Medium,
            color = color.contrastingTextColor(),
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DayCellBackground(
    day: LocalDate,
    isToday: Boolean,
    isMonday: Boolean,
    weekNumber: Int,
    cwLabel: String,
    overflow: Int,
    lang: String,
    edge: DividerEdge,
    dividerColor: Color,
    gridColor: Color,
    labelColor: Color,
    secondaryText: Color,
    todayColor: Color,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isFirst = day.dayOfMonth == 1
    val onBg = MaterialTheme.colorScheme.onBackground

    Box(
        modifier = modifier
            .drawBehind {
                val gridW = 0.5.dp.toPx()
                val divW = 1.5.dp.toPx()
                if (edge == DividerEdge.TOP) {
                    drawLine(dividerColor, Offset(0f, 0f), Offset(size.width, 0f), divW)
                } else {
                    drawLine(gridColor, Offset(0f, 0f), Offset(size.width, 0f), gridW)
                }
                if (edge == DividerEdge.BOTTOM) {
                    drawLine(dividerColor, Offset(0f, size.height), Offset(size.width, size.height), divW)
                }
                drawLine(gridColor, Offset(size.width, 0f), Offset(size.width, size.height), gridW)
            }
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 1.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().height(DAY_NUM_H).padding(top = 3.dp),
            horizontalArrangement = Arrangement_Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
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
        if (overflow > 0) {
            Text(
                "+$overflow",
                fontSize = 8.sp,
                color = secondaryText,
                modifier = Modifier.align(Alignment.BottomStart).padding(start = 3.dp, bottom = 1.dp),
            )
        }
        if (isMonday) {
            Text(
                "$cwLabel $weekNumber",
                fontSize = 8.sp,
                color = secondaryText,
                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 3.dp, bottom = 1.dp),
            )
        }
    }
}

private val Arrangement_Center = androidx.compose.foundation.layout.Arrangement.Center

private fun startOfWeek(date: LocalDate, mondayFirst: Boolean): LocalDate {
    val dow = date.dayOfWeek.value
    val offset = if (mondayFirst) dow - 1 else dow % 7
    return date.minusDays(offset.toLong())
}

/** Result of packing one week: placed bars + per-column overflow count. */
private class WeekLayout(val bars: List<PlacedBar>, val overflowPerCol: IntArray)

/** Columns [startCol, startCol+span-1] this event occupies within the given week. */
private fun columnRange(weekStart: LocalDate, ev: CalEvent): Pair<Int, Int> {
    val weekEnd = weekStart.plusDays(7)
    val evStartDay = maxOf(localDate(ev.startDate), weekStart)
    // last day the event covers (end is exclusive): the day before the end instant
    val lastDay = localDate(ev.endDate.minusSeconds(1))
    val evEndDay = minOf(lastDay, weekEnd.minusDays(1))
    val sc = ChronoUnit.DAYS.between(weekStart, evStartDay).toInt().coerceIn(0, 6)
    val ec = ChronoUnit.DAYS.between(weekStart, evEndDay).toInt().coerceIn(0, 6)
    return sc to (ec - sc + 1).coerceAtLeast(1)
}

/** Greedy first-fit lane packing (mirrors iOS packEvents). */
private fun packEvents(weekStart: LocalDate, weekEvents: List<CalEvent>): WeekLayout {
    val sorted = weekEvents.sortedWith(compareBy<CalEvent> { it.startDate }.thenByDescending { it.endDate })
    val laneLastEnd = ArrayList<Int>()
    val bars = ArrayList<PlacedBar>()
    val overflow = IntArray(7)
    for (ev in sorted) {
        val (sc, span) = columnRange(weekStart, ev)
        val lastCol = (sc + span - 1).coerceAtMost(6)
        var assigned = -1
        for (i in laneLastEnd.indices) {
            if (laneLastEnd[i] < sc) { laneLastEnd[i] = lastCol; assigned = i; break }
        }
        if (assigned == -1 && laneLastEnd.size < MAX_LANES) {
            laneLastEnd.add(lastCol); assigned = laneLastEnd.size - 1
        }
        if (assigned >= 0) {
            bars.add(PlacedBar(ev, assigned, sc, span))
        } else {
            for (c in sc..lastCol) overflow[c]++
        }
    }
    return WeekLayout(bars, overflow)
}

/** Bucket events into every week (week-start key) they overlap. */
private fun buildEventsByWeek(events: List<CalEvent>, mondayFirst: Boolean): Map<LocalDate, List<CalEvent>> {
    val map = HashMap<LocalDate, MutableList<CalEvent>>()
    for (ev in events) {
        val firstWeek = startOfWeek(localDate(ev.startDate), mondayFirst)
        val lastDay = localDate(ev.endDate.minusSeconds(1)).let { if (it.isBefore(localDate(ev.startDate))) localDate(ev.startDate) else it }
        val lastWeek = startOfWeek(lastDay, mondayFirst)
        var w = firstWeek
        var guard = 0
        while (!w.isAfter(lastWeek) && guard < 120) {
            map.getOrPut(w) { mutableListOf() }.add(ev)
            w = w.plusWeeks(1)
            guard++
        }
    }
    return map
}
