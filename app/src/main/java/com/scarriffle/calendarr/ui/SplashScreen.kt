package com.scarriffle.calendarr.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.scarriffle.calendarr.R

/**
 * Branded startup screen shown right after the system splash hands off (same
 * black background + same centred logo, so the logo doesn't jump); the app name
 * and copyright fade in. Stays until the first events have loaded.
 */
@Composable
fun SplashScreen() {
    // Fade the texts in so the handoff from the (text-less) system splash is smooth.
    val textAlpha by animateFloatAsState(targetValue = 1f, animationSpec = tween(350), label = "splashText")

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Text(
            "Calendarr",
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 110.dp).alpha(textAlpha),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
        )
        // Match the system splash icon size (~150dp) so it stays put across the handoff.
        Image(
            painter = painterResource(R.drawable.ic_splash_logo),
            contentDescription = null,
            modifier = Modifier.align(Alignment.Center).size(150.dp).clip(RoundedCornerShape(34.dp)),
        )
        Text(
            "© Scarriffle",
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 40.dp).alpha(textAlpha),
            style = MaterialTheme.typography.bodySmall,
            color = Color.White.copy(alpha = 0.6f),
        )
    }
}
