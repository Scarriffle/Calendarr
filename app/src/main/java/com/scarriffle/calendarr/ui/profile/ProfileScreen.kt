package com.scarriffle.calendarr.ui.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.scarriffle.calendarr.ui.tr

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(onClose: () -> Unit, vm: ProfileViewModel = hiltViewModel()) {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(tr("profile.title")) },
                    navigationIcon = {
                        IconButton(onClick = onClose) { Icon(Icons.Filled.Close, contentDescription = tr("common.close")) }
                    },
                )
            },
        ) { padding ->
            if (vm.loading) {
                Column(Modifier.fillMaxSize().padding(padding), verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator()
                }
                return@Scaffold
            }
            Column(
                Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(20.dp),
            ) {
                val p = vm.profile
                SectionTitle(tr("profile.account"))
                InfoRow(tr("profile.username"), p?.username ?: "—")
                InfoRow(tr("profile.role"), if (p?.isAdmin == true) tr("profile.role.admin") else tr("profile.role.user"))
                Spacer(Modifier.size(20.dp))

                SectionTitle(tr("profile.email"))
                OutlinedTextField(
                    value = vm.email,
                    onValueChange = vm::onEmailChange,
                    label = { Text(tr("profile.email")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.size(8.dp))
                Button(onClick = vm::saveEmail) { Text(tr("profile.save_email")) }

                Spacer(Modifier.size(24.dp))
                Divider()
                Spacer(Modifier.size(16.dp))
                PasswordSection(vm)

                Spacer(Modifier.size(24.dp))
                Divider()
                Spacer(Modifier.size(16.dp))
                TwoFactorSection(vm)

                vm.message?.let {
                    Spacer(Modifier.size(16.dp))
                    Text(it, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

@Composable
private fun PasswordSection(vm: ProfileViewModel) {
    val mismatchMsg = tr("profile.password_mismatch")
    var current by remember { mutableStateOf("") }
    var new1 by remember { mutableStateOf("") }
    var new2 by remember { mutableStateOf("") }
    var localError by remember { mutableStateOf<String?>(null) }

    SectionTitle(tr("profile.change_password"))
    OutlinedTextField(value = current, onValueChange = { current = it }, label = { Text(tr("profile.current_password")) }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
    Spacer(Modifier.size(8.dp))
    OutlinedTextField(value = new1, onValueChange = { new1 = it }, label = { Text(tr("profile.new_password")) }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
    Spacer(Modifier.size(8.dp))
    OutlinedTextField(value = new2, onValueChange = { new2 = it }, label = { Text(tr("profile.new_password_repeat")) }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
    localError?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
    Spacer(Modifier.size(8.dp))
    Button(onClick = {
        if (new1 != new2) { localError = mismatchMsg; return@Button }
        localError = null
        vm.changePassword(current, new1) { ok -> if (ok) { current = ""; new1 = ""; new2 = "" } }
    }) { Text(tr("profile.change_password")) }
}

@Composable
private fun TwoFactorSection(vm: ProfileViewModel) {
    val enabled = vm.profile?.totpEnabled == true
    var disablePw by remember { mutableStateOf("") }
    SectionTitle(tr("profile.twofa"))
    Text(if (enabled) tr("profile.twofa.active") else tr("profile.twofa.inactive"), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
    Spacer(Modifier.size(8.dp))
    if (enabled) {
        OutlinedTextField(value = disablePw, onValueChange = { disablePw = it }, label = { Text(tr("twofa.password_placeholder")) }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.size(8.dp))
        OutlinedButton(onClick = { vm.disable2fa(disablePw); disablePw = "" }) { Text(tr("profile.twofa.disable")) }
    } else {
        val setup = vm.totpSetup
        if (setup == null) {
            Button(onClick = vm::begin2fa) { Text(tr("profile.twofa.enable")) }
        } else {
            Text(tr("twofa.scan_hint"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.size(8.dp))
            Text(setup.secret, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.size(8.dp))
            OutlinedTextField(value = vm.totpCode, onValueChange = vm::onTotpChange, label = { Text(tr("twofa.code_placeholder")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.size(8.dp))
            Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
                Button(onClick = vm::confirm2fa) { Text(tr("twofa.activate")) }
                OutlinedButton(onClick = vm::cancel2fa) { Text(tr("common.cancel")) }
            }
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 8.dp))
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Text(label, modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontWeight = FontWeight.Medium)
    }
}
