package com.scarriffle.calendarr.ui.auth

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.Divider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.scarriffle.calendarr.data.CredentialStore
import com.scarriffle.calendarr.ui.components.PasswordField
import com.scarriffle.calendarr.ui.tr

@Composable
fun LoginScreen(
    serverUrl: String,
    onLoggedIn: () -> Unit,
    onBack: () -> Unit,
    vm: AuthViewModel = hiltViewModel(),
) {
    // Browser round-trip for SSO. AppAuth returns the authorization response
    // as an Activity result, so nothing has to be wired into MainActivity.
    val ssoLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result -> vm.finishSso(result.data, onLoggedIn) }

    LaunchedEffect(Unit) { vm.loadSsoProviders() }

    Column(modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 12.dp)) {
            IconButton(onClick = onBack) {
                Icon(Icons.Filled.ArrowBack, contentDescription = tr("auth.back"))
            }
            Spacer(Modifier.height(0.dp))
            Text(serverUrl, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(tr("auth.login_title"), style = MaterialTheme.typography.headlineMedium)
            Spacer(Modifier.height(24.dp))
            OutlinedTextField(
                value = vm.username,
                onValueChange = vm::onUsernameChange,
                label = { Text(tr("auth.username")) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(12.dp))
            PasswordField(
                value = vm.password,
                onValueChange = vm::onPasswordChange,
                label = tr("auth.password"),
                modifier = Modifier.fillMaxWidth(),
            )
            AnimatedVisibility(vm.showTotp) {
                Column {
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(
                        value = vm.totpCode,
                        onValueChange = vm::onTotpChange,
                        label = { Text(tr("auth.totp")) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(tr("auth.remember"), style = MaterialTheme.typography.bodyMedium)
                Switch(checked = vm.rememberMe, onCheckedChange = vm::onRememberChange)
            }
            vm.loginError?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            vm.ssoErrorSlug?.let { slug ->
                // Unknown slugs fall through to the generic message rather than
                // showing the raw key.
                val key = "sso.err.$slug"
                val msg = tr(key).takeIf { it != key } ?: tr("sso.err.generic")
                Spacer(Modifier.height(8.dp))
                Text(msg, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            Spacer(Modifier.height(20.dp))
            Button(
                onClick = { vm.login(onLoggedIn) },
                enabled = !vm.loggingIn,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (vm.loggingIn) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Text(tr("auth.login"))
                }
            }
            if (vm.ssoProviders.isNotEmpty()) {
                Spacer(Modifier.height(20.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Divider(modifier = Modifier.weight(1f))
                    Text(
                        tr("sso.or"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 12.dp),
                    )
                    Divider(modifier = Modifier.weight(1f))
                }
                Spacer(Modifier.height(12.dp))
                vm.ssoProviders.forEach { provider ->
                    OutlinedButton(
                        onClick = { vm.startSso(provider) { intent -> ssoLauncher.launch(intent) } },
                        enabled = vm.ssoBusyKey == null && !vm.loggingIn,
                        modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                    ) {
                        if (vm.ssoBusyKey == provider.key) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        } else {
                            Text(tr("sso.login_with", provider.name))
                        }
                    }
                }
            }
            TextButton(onClick = onBack) { Text(tr("server.switch")) }
        }
    }
}

/** Read the configured server URL for display. */
@Composable
fun rememberServerUrl(credentialStore: CredentialStore): String =
    credentialStore.serverUrl ?: ""
