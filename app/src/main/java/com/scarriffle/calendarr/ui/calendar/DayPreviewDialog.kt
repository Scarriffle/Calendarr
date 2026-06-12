package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarViewWeek
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.toRect
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.ui.L10n
import com.scarriffle.calendarr.ui.LocalLang
import com.scarriffle.calendarr.ui.tr
import com.scarriffle.calendarr.util.colorFromHex
import com.scarriffle.calendarr.util.contrastingTextColor
import java.time.LocalDate
import java.time.format.TextStyle

/**
 * Long-press day preview (mirrors the iOS DayContextPreviewView): all-day
 * events as colored bars with tapered ends when they continue beyond this day,
 * timed events as dot + time + title rows, followed by quick actions.
 */
@Composable
fun DayPreviewDialog(
    date: LocalDate,
    events: List<CalEvent>,
    onDismiss: () -> Unit,
    onEventClick: (CalEvent) -> Unit,
    onCreateEvent: () -> Unit,
    onOpenDay: () -> Unit,
    onOpenWeek: () -> Unit,
) {
    val lang = LocalLang.current
    val sorted = remember(events) {
        events.sortedWith(compareByDescending<CalEvent> { it.isAllDay }.thenBy { it.startDate })
    }
    val weekdayAbbr = remember(date, lang) {
        date.dayOfWeek.getDisplayName(TextStyle.SHORT, L10n.locale(lang)).uppercase()
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = RoundedCornerShape(20.dp),
            color = MaterialTheme.colorScheme.surface,
            tonalElevation = 3.dp,
        ) {
            Column(
                Modifier
                    .width(290.dp)
                    .padding(vertical = 14.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                Row(
                    Modifier.padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.Bottom,
                ) {
                    Text(
                        weekdayAbbr,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(end = 6.dp, bottom = 3.dp),
                    )
                    Text(
                        "${date.dayOfMonth}",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                    )
                }
                Divider(Modifier.padding(horizontal = 16.dp, vertical = 8.dp))

                if (sorted.isEmpty()) {
                    Text(
                        tr("cal.no_events_day"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                } else {
                    sorted.forEach { ev ->
                        if (ev.isAllDay) {
                            AllDayPreviewBar(event = ev, date = date, onClick = { onEventClick(ev) })
                        } else {
                            TimedPreviewRow(event = ev, lang = lang, onClick = { onEventClick(ev) })
                        }
                    }
                }

                Divider(Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                PreviewAction(Icons.Filled.Add, tr("cal.new_event"), onCreateEvent)
                PreviewAction(Icons.Filled.CalendarViewWeek, tr("cal.show_in_week_view"), onOpenWeek)
                PreviewAction(Icons.Filled.WbSunny, tr("cal.show_in_day_view"), onOpenDay)
            }
        }
    }
}

@Composable
private fun AllDayPreviewBar(event: CalEvent, date: LocalDate, onClick: () -> Unit) {
    val color = colorFromHex(event.effectiveColor)
    val startDay = localDate(event.startDate)
    val lastDay = localDate(event.endDate.minusSeconds(1)) // all-day end is exclusive
    val cLeft = startDay.isBefore(date)
    val cRight = lastDay.isAfter(date)
    val shape = remember(cLeft, cRight) { ChevronBarShape(cLeft, cRight) }

    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 2.dp)
            .clip(shape)
            .background(color)
            .clickable(onClick = onClick)
            .padding(
                start = if (cLeft) 14.dp else 8.dp,
                end = if (cRight) 14.dp else 8.dp,
                top = 4.dp,
                bottom = 4.dp,
            ),
    ) {
        Text(
            event.title,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = color.contrastingTextColor(),
        )
    }
}

@Composable
private fun TimedPreviewRow(event: CalEvent, lang: String, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(7.dp)
                .clip(CircleShape)
                .background(colorFromHex(event.effectiveColor)),
        )
        Text(
            timeLabel(event.startDate, lang),
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 8.dp).width(42.dp),
        )
        Text(
            event.title,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun PreviewAction(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(18.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(12.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium)
    }
}

/**
 * Bar shape with tapered (pointed) ends on the sides where the event continues
 * beyond the shown day — port of the iOS ChevronBarShape.
 */
private class ChevronBarShape(
    private val continuesLeft: Boolean,
    private val continuesRight: Boolean,
) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val r = with(density) { 4.dp.toPx() }
        if (!continuesLeft && !continuesRight) {
            return Outline.Rounded(RoundRect(size.toRect(), CornerRadius(r)))
        }
        val t = with(density) { 8.dp.toPx() }.coerceAtMost(size.width / 2)
        val p = Path()
        if (continuesLeft && continuesRight) {
            p.moveTo(t, 0f)
            p.lineTo(size.width - t, 0f)
            p.lineTo(size.width, size.height / 2)
            p.lineTo(size.width - t, size.height)
            p.lineTo(t, size.height)
            p.lineTo(0f, size.height / 2)
        } else if (continuesLeft) {
            p.moveTo(t, 0f)
            p.lineTo(size.width, 0f)
            p.lineTo(size.width, size.height)
            p.lineTo(t, size.height)
            p.lineTo(0f, size.height / 2)
        } else {
            p.moveTo(0f, 0f)
            p.lineTo(size.width - t, 0f)
            p.lineTo(size.width, size.height / 2)
            p.lineTo(size.width - t, size.height)
            p.lineTo(0f, size.height)
        }
        p.close()
        return Outline.Generic(p)
    }
}
