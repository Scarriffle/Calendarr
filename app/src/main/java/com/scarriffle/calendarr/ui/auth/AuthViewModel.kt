package com.scarriffle.calendarr.ui.auth

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.data.CredentialStore
import com.scarriffle.calendarr.data.remote.ApiProvider
import com.scarriffle.calendarr.data.remote.TwoFactorRequiredException
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val repository: CalendarRepository,
    private val credentialStore: CredentialStore,
) : ViewModel() {

    // Server setup
    var serverUrl by mutableStateOf(credentialStore.serverUrl ?: "")
        private set
    var checking by mutableStateOf(false)
        private set
    var setupError by mutableStateOf<String?>(null)
        private set

    // Login
    var username by mutableStateOf("")
        private set
    var password by mutableStateOf("")
        private set
    var totpCode by mutableStateOf("")
        private set
    var showTotp by mutableStateOf(false)
        private set
    var rememberMe by mutableStateOf(true)
        private set
    var loggingIn by mutableStateOf(false)
        private set
    var loginError by mutableStateOf<String?>(null)
        private set

    fun onServerUrlChange(v: String) { serverUrl = v; setupError = null }
    fun onUsernameChange(v: String) { username = v; loginError = null }
    fun onPasswordChange(v: String) { password = v; loginError = null }
    fun onTotpChange(v: String) { totpCode = v; loginError = null }
    fun onRememberChange(v: Boolean) { rememberMe = v }

    fun checkServer(onConfigured: () -> Unit) {
        val url = serverUrl.trim()
        if (url.isEmpty()) { setupError = "URL erforderlich"; return }
        viewModelScope.launch {
            checking = true
            setupError = null
            runCatching { repository.setupRequired(url) }
                .onSuccess {
                    credentialStore.serverUrl = ApiProvider.normalize(url)
                    onConfigured()
                }
                .onFailure { setupError = it.message ?: "Verbindung fehlgeschlagen" }
            checking = false
        }
    }

    fun login(onSuccess: () -> Unit) {
        val base = credentialStore.serverUrl ?: return
        if (username.isBlank() || password.isBlank()) {
            loginError = "Benutzername und Passwort erforderlich"
            return
        }
        viewModelScope.launch {
            loggingIn = true
            loginError = null
            runCatching {
                repository.login(
                    baseUrl = base,
                    username = username.trim(),
                    password = password,
                    totpCode = totpCode.trim().takeIf { it.isNotEmpty() },
                    rememberMe = rememberMe,
                )
            }.onSuccess { onSuccess() }
                .onFailure { e ->
                    if (e is TwoFactorRequiredException) {
                        showTotp = true
                        loginError = null
                    } else {
                        loginError = e.message ?: "Anmeldung fehlgeschlagen"
                    }
                }
            loggingIn = false
        }
    }
}
