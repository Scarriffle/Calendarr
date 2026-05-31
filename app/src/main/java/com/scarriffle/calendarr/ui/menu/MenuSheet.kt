package com.scarriffle.calendarr.ui.menu

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.scarriffle.calendarr.ui.tr

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MenuSheet(
    isAdmin: Boolean,
    onDismiss: () -> Unit,
    onProfile: () -> Unit,
    onAppearance: () -> Unit,
    onAccounts: () -> Unit,
    onSync: () -> Unit,
    onLogout: () -> Unit,
    onSwitchServer: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            Text(
                "Calendarr",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
            )
            MenuRow(Icons.Filled.AccountCircle, tr("menu.profile"), onProfile)
            MenuRow(Icons.Filled.Palette, tr("menu.appearance"), onAppearance)
            MenuRow(Icons.Filled.CalendarMonth, tr("menu.accounts"), onAccounts)
            Divider(Modifier.padding(vertical = 4.dp))
            MenuRow(Icons.Filled.Sync, tr("menu.sync"), onSync)
            Divider(Modifier.padding(vertical = 4.dp))
            MenuRow(Icons.Filled.Logout, tr("menu.logout"), onLogout)
            MenuRow(Icons.Filled.Dns, tr("server.switch"), onSwitchServer)
        }
    }
}

@Composable
private fun MenuRow(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(18.dp))
        Text(label, style = MaterialTheme.typography.bodyLarge)
    }
}
