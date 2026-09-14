package com.scarriffle.calendarr.ui.groups

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.domain.model.DirectoryUser
import com.scarriffle.calendarr.domain.model.Group
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class GroupsViewModel @Inject constructor(
    private val repository: CalendarRepository,
) : ViewModel() {

    var loading by mutableStateOf(true)
        private set
    var groups by mutableStateOf<List<Group>>(emptyList())
        private set
    var directory by mutableStateOf<List<DirectoryUser>>(emptyList())
        private set
    var error by mutableStateOf<String?>(null)
        private set

    val currentUserId: Int get() = repository.currentUserId

    init { load() }

    fun load() {
        viewModelScope.launch {
            loading = true
            error = null
            groups = runCatching { repository.getGroups() }.getOrDefault(emptyList())
            directory = runCatching { repository.getUserDirectory() }.getOrDefault(emptyList())
            loading = false
        }
    }

    suspend fun groupDetail(id: Int): Group? = runCatching { repository.getGroup(id) }.getOrNull()

    fun createGroup(name: String, icon: String, memberIds: List<Int>, onDone: () -> Unit) {
        viewModelScope.launch {
            runCatching { repository.createGroup(name, memberIds, icon) }
                .onSuccess { load(); onDone() }
                .onFailure { error = it.message }
        }
    }

    /** Save name/icon, then reconcile membership against [existingMemberIds]. */
    fun saveGroup(id: Int, name: String, icon: String, desired: Set<Int>, existing: Set<Int>, onDone: () -> Unit) {
        viewModelScope.launch {
            runCatching {
                repository.updateGroup(id, name, icon)
                for (uid in desired - existing) repository.addGroupMember(id, uid)
                for (uid in existing - desired) repository.removeGroupMember(id, uid)
            }
                .onSuccess { load(); onDone() }
                .onFailure { error = it.message }
        }
    }

    fun setMemberColor(groupId: Int, userId: Int, color: String) {
        viewModelScope.launch { runCatching { repository.setGroupMemberColor(groupId, userId, color) } }
    }

    fun deleteGroup(id: Int, onDone: () -> Unit) {
        viewModelScope.launch {
            runCatching { repository.deleteGroup(id) }
                .onSuccess { load(); onDone() }
                .onFailure { error = it.message }
        }
    }
}
