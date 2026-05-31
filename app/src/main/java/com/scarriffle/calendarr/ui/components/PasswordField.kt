package com.scarriffle.calendarr.ui.components

import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import kotlinx.coroutines.delay

/**
 * Password input with two affordances the plain field lacks:
 *  - an eye toggle to reveal the full value, and
 *  - a brief reveal of the most recently typed character (~1.2s) so the user
 *    can tell whether a keystroke landed as intended.
 */
@Composable
fun PasswordField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    imeAction: ImeAction = ImeAction.Done,
) {
    var fullyVisible by remember { mutableStateOf(false) }
    var revealLast by remember { mutableStateOf(false) }

    // Reveal the last character briefly after each change.
    LaunchedEffect(value) {
        if (value.isNotEmpty() && !fullyVisible) {
            revealLast = true
            delay(1200)
            revealLast = false
        } else {
            revealLast = false
        }
    }

    val transformation = when {
        fullyVisible -> VisualTransformation.None
        revealLast -> LastCharVisibleTransformation
        else -> PasswordVisualTransformation()
    }

    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        singleLine = true,
        visualTransformation = transformation,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = imeAction),
        trailingIcon = {
            IconButton(onClick = { fullyVisible = !fullyVisible }) {
                Icon(
                    imageVector = if (fullyVisible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                    contentDescription = null,
                )
            }
        },
        modifier = modifier,
    )
}

/** Masks every character except the last with a bullet. 1:1 char mapping → identity offsets. */
private val LastCharVisibleTransformation = object : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val masked = buildString {
            for (i in text.indices) append(if (i == text.lastIndex) text[i] else '•')
        }
        return TransformedText(AnnotatedString(masked), OffsetMapping.Identity)
    }
}
