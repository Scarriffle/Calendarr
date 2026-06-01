package com.scarriffle.calendarr.ui.calendar

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.data.SettingsStore
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.domain.model.CalViewType
import com.scarriffle.calendarr.domain.model.Group
import com.scarriffle.calendarr.domain.model.GroupMember
import com.scarriffle.calendarr.domain.model.WritableCalendar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject

/** Build the "source:id" visibility key, stripping any "<source>-" prefix. */
fun calendarKey(source: String, calendarId: String): String {
    val prefix = "$source-"
    val id = if (calendarId.startsWith(prefix)) calendarId.removePrefix(prefix) else calendarId
    return "$source:$id"
}

data class CalendarUiState(
    val viewType: CalViewType = CalViewType.MONTH,
    val currentDate: LocalDate = LocalDate.now(),
    val events: List<CalEvent> = emptyList(),
    val isLoading: Boolean = false,
    val isBackgroundCaching: Boolean = false,
    val error: String? = null,
    val weekStartsOnMonday: Boolean = true,
    val writableCalendars: List<WritableCalendar> = emptyList(),
    val hiddenKeys: Set<String> = emptySet(),
    val banishedKeys: Set<String> = emptySet(),
    // Group overlay: when non-null the calendar shows the group's combined view.
    val groups: List<Group> = emptyList(),
    val activeGroup: Group? = null,
    // Group overlay: full member list (for the filter) + per-member / group-cal
    // hidden keys ("gm:<userId>" / "gc"). In-memory; reset when switching group.
    val activeGroupMembers: List<GroupMember> = emptyList(),
    val hiddenGroupKeys: Set<String> = emptySet(),
)

fun groupMemberKey(ownerId: Int): String = "gm:$ownerId"
const val GROUP_CALENDAR_KEY = "gc"

@HiltViewModel
class CalendarViewModel @Inject constructor(
    private val repository: CalendarRepository,
    private val settingsStore: SettingsStore,
) : ViewModel() {

    private val zone: ZoneId = ZoneId.systemDefault()

    /** Current user id (for creator/owner comparisons in the UI). */
    val currentUserId: Int get() = repository.currentUserId

    /** Serializes network loads so overlapping fetches don't thrash the UI. */
    private val loadMutex = Mutex()

    private val _state = MutableStateFlow(initialState())
    val state: StateFlow<CalendarUiState> = _state.asStateFlow()

    /** True once the first event load has completed — used to gate the splash. */
    private val _ready = MutableStateFlow(false)
    val ready: StateFlow<Boolean> = _ready.asStateFlow()

    // Cache bookkeeping
    private var cachedStart: Instant? = null
    private var cachedEnd: Instant? = null
    private var allCachedEvents: List<CalEvent> = emptyList()

    init {
        loadWritableCalendars()
        loadGroups()
        initialLoad()
    }

    /**
     * Load the full ±cacheMonths window once, behind the splash, and only then
     * mark ready. Entering the app fully-loaded avoids the first-open jank of
     * loading a big batch while the user is already scrolling.
     */
    private fun initialLoad() {
        val months = settingsStore.cacheMonths.toLong()
        val today = LocalDate.now().withDayOfMonth(1)
        val start = instant(today.minusMonths(months))
        val end = instant(today.plusMonths(months + 1))
        viewModelScope.launch {
            loadRange(start, end, background = false)
            markReady()
        }
    }

    private fun initialState(): CalendarUiState {
        val s = settingsStore.loadSettings()
        return CalendarUiState(
            viewType = CalViewType.fromKey(s.defaultView),
            weekStartsOnMonday = s.weekStartsOnMonday,
            hiddenKeys = settingsStore.hiddenCalendarKeys,
            banishedKeys = settingsStore.banishedCalendarKeys,
        )
    }

    // ---- Navigation ----

    fun setViewType(type: CalViewType) {
        _state.update { it.copy(viewType = type) }
        loadVisible()
    }

    fun moveToToday() {
        _state.update { it.copy(currentDate = LocalDate.now()) }
        loadVisible()
    }

    fun navigatePrev() = navigate(-1)
    fun navigateNext() = navigate(+1)

    private fun navigate(direction: Int) {
        val st = _state.value
        val date = st.currentDate
        val newDate = when (st.viewType) {
            CalViewType.WEEK -> date.plusWeeks(direction.toLong())
            CalViewType.DAY -> date.plusDays(direction.toLong())
            CalViewType.QUARTER -> date.plusMonths((3 * direction).toLong())
            else -> date.plusMonths(direction.toLong())
        }
        _state.update { it.copy(currentDate = newDate) }
        loadVisible()
    }

    fun goToDate(date: LocalDate, viewType: CalViewType? = null) {
        _state.update { it.copy(currentDate = date, viewType = viewType ?: it.viewType) }
        loadVisible()
    }

    // ---- Range ----

    fun rangeForCurrentView(): Pair<Instant, Instant> {
        val st = _state.value
        val date = st.currentDate
        return when (st.viewType) {
            CalViewType.MONTH -> {
                val start = date.withDayOfMonth(1)
                instant(start.minusMonths(1)) to instant(start.plusMonths(2))
            }
            CalViewType.QUARTER -> {
                val start = date.withDayOfMonth(1)
                instant(start) to instant(start.plusMonths(4))
            }
            CalViewType.WEEK -> {
                val weekStart = startOfWeek(date, st.weekStartsOnMonday)
                instant(weekStart) to instant(weekStart.plusDays(8))
            }
            CalViewType.DAY -> instant(date) to instant(date.plusDays(1))
            CalViewType.AGENDA -> {
                val today = LocalDate.now()
                instant(today) to instant(today.plusDays(90))
            }
        }
    }

    private fun instant(date: LocalDate): Instant = date.atStartOfDay(zone).toInstant()

    private fun startOfWeek(date: LocalDate, mondayFirst: Boolean): LocalDate {
        val dow = date.dayOfWeek.value // Mon=1 .. Sun=7
        val offset = if (mondayFirst) dow - 1 else dow % 7
        return date.minusDays(offset.toLong())
    }

    // ---- Loading ----

    fun loadVisible(force: Boolean = false) {
        val (start, end) = rangeForCurrentView()
        if (!force && isCached(start, end)) {
            refreshFromCache()
            markReady()
            return
        }
        viewModelScope.launch {
            loadRange(start, end, background = false)
            markReady()
        }
    }

    /** On-demand load for a month the user scrolled to in the continuous calendar. */
    fun ensureMonthLoaded(monthAnchor: LocalDate) {
        val first = monthAnchor.withDayOfMonth(1)
        val start = instant(first.minusMonths(1))
        val end = instant(first.plusMonths(2))
        if (isCached(start, end)) return
        viewModelScope.launch { loadRange(start, end, background = false) }
    }

    /** Single serialized loader: avoids overlapping fetches that cause scroll jank. */
    private suspend fun loadRange(start: Instant, end: Instant, background: Boolean) {
        loadMutex.withLock {
            // Another load (e.g. the background prefetch) may have covered this range.
            if (isCached(start, end)) return
            val group = _state.value.activeGroup
            val flag = if (background) "bg" else "fg"
            _state.update { if (flag == "bg") it.copy(isBackgroundCaching = true) else it.copy(isLoading = true, error = null) }
            runCatching {
                if (group != null) decorateGroup(repository.fetchGroupCombined(group.id, start, end))
                else repository.fetchEvents(start, end)
            }
                .onSuccess { mergeIntoCache(it, start, end); refreshFromCache() }
                .onFailure { e -> if (!background) _state.update { it.copy(error = e.message) } }
            _state.update { it.copy(isLoading = false, isBackgroundCaching = false) }
        }
    }

    /** Prefix combined-view events with the owner's / creator's first name (and 👥 for group events). */
    private fun decorateGroup(events: List<CalEvent>): List<CalEvent> {
        val me = currentUserId
        return events.map { ev ->
            // Prefer the server-decorated title (group icon + owner prefix) so
            // web, iOS and Android render identically; fall back for old servers.
            val serverTitle = ev.displayTitle?.takeIf { it.isNotEmpty() }
            if (serverTitle != null) return@map ev.copy(title = serverTitle)
            val prefix = when {
                ev.isGroupEvent && ev.creator != null && ev.creator.id != me -> "${firstName(ev.creator.displayName)}: "
                ev.owner != null && ev.owner.id != me -> "${firstName(ev.owner.displayName)}: "
                else -> ""
            }
            if (prefix.isEmpty()) ev else ev.copy(title = prefix + ev.title)
        }
    }

    private fun firstName(s: String): String = s.trim().substringBefore(' ').ifBlank { s }

    private fun markReady() {
        _ready.value = true
    }

    private fun isCached(start: Instant, end: Instant): Boolean {
        val cs = cachedStart ?: return false
        val ce = cachedEnd ?: return false
        return !cs.isAfter(start) && !ce.isBefore(end)
    }

    private fun mergeIntoCache(newEvents: List<CalEvent>, rangeStart: Instant, rangeEnd: Instant) {
        val retained = allCachedEvents.filter {
            !it.startDate.isBefore(rangeEnd) || !it.endDate.isAfter(rangeStart)
        }
        allCachedEvents = retained + newEvents
        cachedStart = cachedStart?.let { minOf(it, rangeStart) } ?: rangeStart
        cachedEnd = cachedEnd?.let { maxOf(it, rangeEnd) } ?: rangeEnd
    }

    private fun refreshFromCache() {
        val st = _state.value
        // In group mode: server scopes/filters by privacy; locally honour the
        // per-member / group-calendar hide toggles (hiddenGroupKeys).
        val visible = if (st.activeGroup != null) {
            val hg = st.hiddenGroupKeys
            if (hg.isEmpty()) allCachedEvents
            else allCachedEvents.filter { ev ->
                when {
                    ev.isGroupEvent -> GROUP_CALENDAR_KEY !in hg
                    ev.owner != null -> groupMemberKey(ev.owner.id ?: -1) !in hg
                    else -> true
                }
            }
        } else {
            val hidden = st.hiddenKeys
            val banished = st.banishedKeys
            allCachedEvents.filter { ev ->
                val key = calendarKey(ev.source, ev.calendarId)
                key !in hidden && key !in banished
            }
        }
        // Skip the state write (and resulting recomposition) when nothing changed.
        _state.update { if (it.events == visible) it else it.copy(events = visible) }
    }

    private fun invalidateCache() {
        cachedStart = null
        cachedEnd = null
        allCachedEvents = emptyList()
    }

    fun syncWithServer() {
        invalidateCache()
        loadGroups()
        initialLoad()
    }

    fun clearError() = _state.update { it.copy(error = null) }

    // ---- Visibility filters ----

    fun setCalendarHidden(key: String, hidden: Boolean) {
        val next = _state.value.hiddenKeys.toMutableSet().apply {
            if (hidden) add(key) else remove(key)
        }
        settingsStore.hiddenCalendarKeys = next
        _state.update { it.copy(hiddenKeys = next) }
        refreshFromCache()
    }

    fun setHiddenCalendars(keys: Set<String>) {
        settingsStore.hiddenCalendarKeys = keys
        _state.update { it.copy(hiddenKeys = keys) }
        refreshFromCache()
    }

    fun setCalendarBanished(key: String, banished: Boolean) {
        val nextBanished = _state.value.banishedKeys.toMutableSet().apply {
            if (banished) add(key) else remove(key)
        }
        val nextHidden = _state.value.hiddenKeys.toMutableSet().apply {
            if (banished) remove(key)
        }
        settingsStore.banishedCalendarKeys = nextBanished
        settingsStore.hiddenCalendarKeys = nextHidden
        _state.update { it.copy(banishedKeys = nextBanished, hiddenKeys = nextHidden) }
        refreshFromCache()
    }

    // ---- Groups ----

    fun loadGroups() {
        viewModelScope.launch {
            runCatching { repository.getGroups() }
                .onSuccess { gs ->
                    _state.update { st ->
                        // If the active group was deleted elsewhere, drop back to personal.
                        val stillActive = st.activeGroup?.let { a -> gs.firstOrNull { it.id == a.id } }
                        st.copy(groups = gs, activeGroup = stillActive)
                    }
                }
        }
    }

    /** Flip between personal and a group's combined overlay; reloads the wide window. */
    fun switchGroup(group: Group?) {
        if (_state.value.activeGroup?.id == group?.id) return
        _state.update {
            it.copy(activeGroup = group, hiddenGroupKeys = emptySet(), activeGroupMembers = emptyList())
        }
        invalidateCache()
        initialLoad()
        // Load the full member list (with server colours) for the filter sheet.
        if (group != null) {
            viewModelScope.launch {
                runCatching { repository.getGroup(group.id) }
                    .onSuccess { g -> _state.update { it.copy(activeGroupMembers = g.members) } }
            }
        }
    }

    /** Toggle a single member's calendar / the group calendar in the overlay. */
    fun setGroupKeyHidden(key: String, hidden: Boolean) {
        _state.update {
            val next = it.hiddenGroupKeys.toMutableSet().apply { if (hidden) add(key) else remove(key) }
            it.copy(hiddenGroupKeys = next)
        }
        refreshFromCache()
    }

    /** Replace the group-overlay hidden set (bulk show/hide all). */
    fun setHiddenGroupKeys(keys: Set<String>) {
        _state.update { it.copy(hiddenGroupKeys = keys) }
        refreshFromCache()
    }

    // ---- Writable calendars ----

    fun loadWritableCalendars() {
        viewModelScope.launch {
            runCatching { repository.getWritableCalendars() }
                .onSuccess { cals -> _state.update { it.copy(writableCalendars = cals) } }
        }
    }

    // ---- Event mutations ----

    private fun afterMutation() {
        invalidateCache()
        initialLoad()
    }

    fun saveEvent(
        calendar: WritableCalendar,
        existing: CalEvent?,
        title: String,
        start: Instant,
        end: Instant,
        isAllDay: Boolean,
        location: String,
        description: String,
        color: String?,
        isPrivate: Boolean,
        onResult: (String?) -> Unit,
    ) {
        viewModelScope.launch {
            val result = runCatching {
                if (existing != null && existing.source == calendar.source) {
                    when (existing.source) {
                        "local" -> repository.updateLocalEvent(existing.id, title, start, end, isAllDay, location, description, color, isPrivate)
                        "caldav" -> repository.updateCalDAVEvent(existing.id, existing.url, calendar.numericId, title, start, end, isAllDay, location, description, color)
                        "homeassistant" -> repository.updateHAEvent(calendar.numericId, existing.id, title, start, end, isAllDay, location, description)
                        "google" -> repository.updateGoogleEvent(calendar.numericId, existing.id, title, start, end, isAllDay, location, description)
                        else -> createForSource(calendar, title, start, end, isAllDay, location, description, color, isPrivate)
                    }
                } else {
                    createForSource(calendar, title, start, end, isAllDay, location, description, color, isPrivate)
                }
            }
            result.onSuccess { afterMutation(); onResult(null) }
                .onFailure { onResult(it.message ?: "Fehler") }
        }
    }

    private suspend fun createForSource(
        calendar: WritableCalendar, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String, color: String?, isPrivate: Boolean,
    ) {
        when (calendar.source) {
            "local" -> repository.createLocalEvent(calendar.numericId, title, start, end, isAllDay, location, description, color, isPrivate)
            "caldav" -> repository.createCalDAVEvent(calendar.numericId, title, start, end, isAllDay, location, description, color)
            "google" -> repository.createGoogleEvent(calendar.numericId, title, start, end, isAllDay, location, description)
            "homeassistant" -> repository.createHAEvent(calendar.numericId, title, start, end, isAllDay, location, description)
        }
    }

    fun deleteEvent(event: CalEvent, onResult: (String?) -> Unit) {
        viewModelScope.launch {
            val result = runCatching {
                when (event.source) {
                    "local" -> repository.deleteLocalEvent(event.id)
                    "caldav" -> repository.deleteCalDAVEvent(event.id, event.url, calendarNumericId(event))
                    "homeassistant" -> repository.deleteHAEvent(calendarNumericId(event) ?: 0, event.id)
                    "google" -> repository.deleteGoogleEvent(calendarNumericId(event) ?: 0, event.id)
                    else -> Unit
                }
            }
            result.onSuccess {
                removeCachedEvent(event.id)
                onResult(null)
            }.onFailure { onResult(it.message ?: "Fehler") }
        }
    }

    private fun calendarNumericId(event: CalEvent): Int? {
        val key = calendarKey(event.source, event.calendarId)
        return key.substringAfter(":").toIntOrNull()
    }

    private fun removeCachedEvent(id: String) {
        allCachedEvents = allCachedEvents.filterNot { it.id == id }
        refreshFromCache()
    }

    /** Events overlapping a single day, sorted by start. */
    fun eventsOn(date: LocalDate, events: List<CalEvent>): List<CalEvent> {
        val dayStart = instant(date)
        val dayEnd = instant(date.plusDays(1))
        return events.filter { it.startDate.isBefore(dayEnd) && it.endDate.isAfter(dayStart) }
            .sortedBy { it.startDate }
    }
}
