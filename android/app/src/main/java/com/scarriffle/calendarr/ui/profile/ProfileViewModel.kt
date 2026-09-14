package com.scarriffle.calendarr.ui.profile

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.data.TotpSetup
import com.scarriffle.calendarr.domain.model.UserProfile
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val repository: CalendarRepository,
) : ViewModel() {

    var profile by mutableStateOf<UserProfile?>(null)
        private set
    var email by mutableStateOf("")
        private set
    var loading by mutableStateOf(true)
        private set
    var message by mutableStateOf<String?>(null)
        private set

    // 2FA enrolment
    var totpSetup by mutableStateOf<TotpSetup?>(null)
        private set
    var totpCode by mutableStateOf("")
        private set

    init { load() }

    fun load() {
        viewModelScope.launch {
            loading = true
            runCatching { repository.getProfile() }
                .onSuccess { p -> profile = p; email = p.email ?: "" }
                .onFailure { message = it.message }
            loading = false
        }
    }

    fun onEmailChange(v: String) { email = v }
    fun onTotpChange(v: String) { totpCode = v }

    fun saveEmail() {
        viewModelScope.launch {
            runCatching { repository.updateEmail(email.trim()) }
                .onSuccess { message = "✓"; load() }
                .onFailure { message = it.message }
        }
    }

    fun changePassword(current: String, new: String, onDone: (Boolean) -> Unit) {
        viewModelScope.launch {
            runCatching { repository.changePassword(current, new) }
                .onSuccess { message = "✓"; onDone(true) }
                .onFailure { message = it.message; onDone(false) }
        }
    }

    fun begin2fa() {
        viewModelScope.launch {
            runCatching { repository.setup2fa() }
                .onSuccess { totpSetup = it }
                .onFailure { message = it.message }
        }
    }

    fun confirm2fa() {
        viewModelScope.launch {
            runCatching { repository.enable2fa(totpCode.trim()) }
                .onSuccess { totpSetup = null; totpCode = ""; load() }
                .onFailure { message = it.message }
        }
    }

    fun disable2fa(password: String) {
        viewModelScope.launch {
            runCatching { repository.disable2fa(password) }
                .onSuccess { load() }
                .onFailure { message = it.message }
        }
    }

    fun cancel2fa() { totpSetup = null; totpCode = "" }
}
