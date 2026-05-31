package com.scarriffle.calendarr.domain.model

/** Lightweight user from /api/users/directory (for sharing/group pickers). */
data class DirectoryUser(val id: Int, val displayName: String)

/** A share entry on a local calendar. */
data class CalendarShareEntry(val userId: Int, val displayName: String, val permission: String)

/** A member of a group, with their server-defined colour. */
data class GroupMember(
    val id: Int,
    val displayName: String,
    val role: String,
    val color: String? = null,
)

/** A user group + its shared group calendar. */
data class Group(
    val id: Int,
    val name: String,
    val icon: String? = null,
    val role: String,
    val memberCount: Int,
    val groupCalendarId: Int?,
    val groupCalendarColor: String? = null,
    val members: List<GroupMember>,
)
