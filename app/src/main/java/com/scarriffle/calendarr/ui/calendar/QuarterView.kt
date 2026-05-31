package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.scarriffle.calendarr.ui.LocalAppSettings
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.util.colorFromHex
import com.scarriffle.calendarr.util.contrastingTextColor
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Composable
fun QuarterView(state: CalendarUiState, onDayClick: (LocalDate) -> Unit) {
    val lang = LocalLang.current
    val months = (0 until 3).map { state.currentDate.withDayOfMonth(1).plusMonths(it.toLong()) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp)) {
        months.forEach { month ->
            MiniMonth(month, state, lang, onDayClick)
        }
    }
}

@Composable
private fun MiniMonth(month: LocalDate, state: CalendarUiState, lang: String, onDayClick: (LocalDate) -> Unit) {
    val mondayFirst = state.weekStartsOnMonday
    val today = LocalDate.now()
    val titleFmt = DateTimeFormatter.ofPattern("LLLL yyyy", com.scarriffle.calendarr.ui.L10n.locale(lang))
    val dow = month.dayOfWeek.value
    val offset = if (mondayFirst) dow - 1 else dow % 7
    val firstVisible = month.minusDays(offset.toLong())
    val cells = (0 until 42).map { firstVisible.plusDays(it.toLong()) }

    Column(Modifier.padding(bottom = 16.dp)) {
        Text(
            titleFmt.format(month).replaceFirstChar { it.uppercase() },
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(bottom = 4.dp),
        )
        Row(Modifier.fillMaxWidth()) {
            weekdayLabels(mondayFirst, lang).forEach {
                Text(it, Modifier.weight(1f), textAlign = TextAlign.Center, fontSize = 9.sp, color = MaterialTheme.colorScheme.outline)
            }
        }
        cells.chunked(7).forEach { week ->
            Row(Modifier.fillMaxWidth()) {
                week.forEach { day ->
                    val hasEvents = state.events.any {
                        localDate(it.startDate) <= day && localDate(it.endDate) >= day
                    }
                    val firstColor = state.events.firstOrNull {
                        localDate(it.startDate) <= day && localDate(it.endDate) >= day
                    }?.effectiveColor
                    Box(
                        Modifier.weight(1f).aspectRatio(1f).clickable { onDayClick(day) },
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            val isToday = day == today
                            Box(contentAlignment = Alignment.Center) {
                                if (isToday) {
                                    Box(
                                        Modifier.clip(CircleShape)
                                            .background(colorFromHex(LocalAppSettings.current.todayColor))
                                            .padding(horizontal = 5.dp, vertical = 2.dp),
                                    ) { Text("${day.dayOfMonth}", fontSize = 10.sp, color = colorFromHex(LocalAppSettings.current.todayColor).contrastingTextColor()) }
                                } else {
                                    Text(
                                        "${day.dayOfMonth}",
                                        fontSize = 10.sp,
                                        color = if (day.month == month.month) MaterialTheme.colorScheme.onBackground else MaterialTheme.colorScheme.outline,
                                    )
                                }
                            }
                            if (hasEvents) {
                                Box(Modifier.padding(top = 1.dp).clip(CircleShape).background(colorFromHex(firstColor)).padding(2.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}
