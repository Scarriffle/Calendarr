package com.scarriffle.calendarr.ui.calendar

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cake
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.scarriffle.calendarr.domain.model.CalEvent

/**
 * Event label for the calendar grids: an optional leading cake icon for
 * birthday events, followed by the render title (which carries the
 * server-computed age). The icon inherits the text colour/size so the label
 * matches whatever bar it's dropped into.
 */
@Composable
fun EventLabel(
    event: CalEvent,
    color: Color,
    fontSize: TextUnit = 10.sp,
    fontWeight: FontWeight = FontWeight.Medium,
    maxLines: Int = 1,
    modifier: Modifier = Modifier,
) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = modifier) {
        if (event.isBirthday) {
            Icon(
                Icons.Filled.Cake,
                contentDescription = null,
                tint = color,
                modifier = Modifier
                    .size(fontSize.value.dp)
                    .padding(end = 2.dp),
            )
        }
        Text(
            event.renderTitle,
            maxLines = maxLines,
            overflow = TextOverflow.Ellipsis,
            fontSize = fontSize,
            fontWeight = fontWeight,
            color = color,
            modifier = Modifier.weight(1f, fill = false),
        )
    }
}
