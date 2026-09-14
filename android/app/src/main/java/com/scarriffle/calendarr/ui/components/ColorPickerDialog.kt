package com.scarriffle.calendarr.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.scarriffle.calendarr.util.colorFromHex
import com.scarriffle.calendarr.util.toHex

/**
 * Full HSV colour picker: saturation/value field + hue slider + hex input.
 * Returns a "#RRGGBB" string via [onConfirm].
 */
@Composable
fun ColorPickerDialog(
    initial: String,
    title: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    val initHsv = remember(initial) {
        FloatArray(3).also { android.graphics.Color.colorToHSV(colorFromHex(initial).toArgb(), it) }
    }
    var hue by remember { mutableFloatStateOf(initHsv[0]) }
    var sat by remember { mutableFloatStateOf(initHsv[1]) }
    var value by remember { mutableFloatStateOf(initHsv[2]) }
    var hexText by remember { mutableStateOf(colorFromHex(initial).toHex()) }

    val current = Color.hsv(hue, sat, value)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(Modifier.fillMaxWidth()) {
                // Saturation / Value field
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(170.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(Brush.horizontalGradient(listOf(Color.White, Color.hsv(hue, 1f, 1f))))
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black)))
                        .pointerInput(Unit) {
                            detectTapGestures { o ->
                                sat = (o.x / size.width).coerceIn(0f, 1f)
                                value = (1f - o.y / size.height).coerceIn(0f, 1f)
                                hexText = Color.hsv(hue, sat, value).toHex()
                            }
                        }
                        .pointerInput(Unit) {
                            detectDragGestures { change, _ ->
                                change.consume()
                                sat = (change.position.x / size.width).coerceIn(0f, 1f)
                                value = (1f - change.position.y / size.height).coerceIn(0f, 1f)
                                hexText = Color.hsv(hue, sat, value).toHex()
                            }
                        },
                ) {
                    Canvas(Modifier.matchParentSize()) {
                        val cx = sat * size.width
                        val cy = (1f - value) * size.height
                        drawCircle(Color.White, radius = 9f, center = Offset(cx, cy), style = Stroke(width = 3f))
                        drawCircle(Color.Black, radius = 12f, center = Offset(cx, cy), style = Stroke(width = 1f))
                    }
                }
                Spacer(Modifier.height(14.dp))

                // Hue slider
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(26.dp)
                        .clip(RoundedCornerShape(13.dp))
                        .background(Brush.horizontalGradient((0..6).map { Color.hsv(it * 60f, 1f, 1f) }))
                        .pointerInput(Unit) {
                            detectTapGestures { o ->
                                hue = (o.x / size.width * 360f).coerceIn(0f, 360f)
                                hexText = Color.hsv(hue, sat, value).toHex()
                            }
                        }
                        .pointerInput(Unit) {
                            detectDragGestures { change, _ ->
                                change.consume()
                                hue = (change.position.x / size.width * 360f).coerceIn(0f, 360f)
                                hexText = Color.hsv(hue, sat, value).toHex()
                            }
                        },
                ) {
                    Canvas(Modifier.matchParentSize()) {
                        val cx = (hue / 360f) * size.width
                        drawCircle(Color.White, radius = 10f, center = Offset(cx, size.height / 2f), style = Stroke(width = 3f))
                    }
                }
                Spacer(Modifier.height(14.dp))

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(40.dp).clip(CircleShape).background(current).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape))
                    Spacer(Modifier.size(12.dp))
                    OutlinedTextField(
                        value = hexText,
                        onValueChange = { raw ->
                            hexText = raw
                            val parsed = colorFromHex(raw, Color.Unspecified)
                            if (parsed != Color.Unspecified) {
                                val hsv = FloatArray(3)
                                android.graphics.Color.colorToHSV(parsed.toArgb(), hsv)
                                hue = hsv[0]; sat = hsv[1]; value = hsv[2]
                            }
                        },
                        label = { Text("Hex") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        },
        confirmButton = { TextButton(onClick = { onConfirm(current.toHex()) }) { Text("OK") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Abbrechen") } },
    )
}
