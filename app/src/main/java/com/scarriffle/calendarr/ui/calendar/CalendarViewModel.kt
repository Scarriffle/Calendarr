package com.scarriffle.calendarr.ui.calendar

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.data.SettingsStore
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.domain.model.CalViewType
import com.scarriffle.calendarr.domain.model.WritableCalendar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
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
)

@HiltViewModel
class CalendarViewModel @Inject constructor(
    private val repository: CalendarRepository,
    private val settingsStore: SettingsStore,
) : ViewModel() {

    private val zone: ZoneId = ZoneId.systemDefault()

    private val _state = MutableStateFlow(initialState())
    val state: StateFlow<CalendarUiState> = _state.asStateFlow()

    // Cache bookkeeping
    private var cachedStart: Instant? = null
    private var cachedEnd: Instant? = null
    private var allCachedEvents: List<CalEvent> = emptyList()

    init {
        loadVisible()
        loadWritableCalendars()
        prefetchBackground()
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
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            runCatching { repository.fetchEvents(start, end) }
                .onSuccess { fetched ->
                    mergeIntoCache(fetched, start, end)
                    refreshFromCache()
                    _state.update { it.copy(isLoading = false) }
                }
                .onFailure { e ->
                    _state.update { it.copy(isLoading = false, error = e.message) }
                }
        }
    }

    /** On-demand load for a month the user scrolled to in the continuous calendar. */
    fun ensureMonthLoaded(monthAnchor: LocalDate) {
        val first = monthAnchor.withDayOfMonth(1)
        val start = instant(first.minusMonths(1))
        val end = instant(first.plusMonths(2))
        if (isCached(start, end)) return
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            runCatching { repository.fetchEvents(start, end) }
                .onSuccess { mergeIntoCache(it, start, end); refreshFromCache() }
                .onFailure { e -> _state.update { it.copy(error = e.message) } }
            _state.update { it.copy(isLoading = false) }
        }
    }

    private fun prefetchBackground() {
        val months = settingsStore.cacheMonths
        val today = LocalDate.now().withDayOfMonth(1)
        val start = instant(today.minusMonths(months.toLong()))
        val end = instant(today.plusMonths((months + 1).toLong()))
        if (isCached(start, end)) return
        viewModelScope.launch {
            _state.update { it.copy(isBackgroundCaching = true) }
            runCatching { repository.fetchEvents(start, end) }
                .onSuccess { fetched ->
                    mergeIntoCache(fetched, start, end)
                    refreshFromCache()
                }
            _state.update { it.copy(isBackgroundCaching = false) }
        }
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
        val hidden = _state.value.hiddenKeys
        val banished = _state.value.banishedKeys
        val visible = allCachedEvents.filter { ev ->
            val key = calendarKey(ev.source, ev.calendarId)
            key !in hidden && key !in banished
        }
        _state.update { it.copy(events = visible) }
    }

    private fun invalidateCache() {
        cachedStart = null
        cachedEnd = null
        allCachedEvents = emptyList()
    }

    fun syncWithServer() {
        invalidateCache()
        loadVisible(force = true)
        prefetchBackground()
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
        loadVisible(force = true)
        prefetchBackground()
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
        onResult: (String?) -> Unit,
    ) {
        viewModelScope.launch {
            val result = runCatching {
                if (existing != null && existing.source == calendar.source) {
                    when (existing.source) {
                        "local" -> repository.updateLocalEvent(existing.id, title, start, end, isAllDay, location, description, color)
                        "caldav" -> repository.updateCalDAVEvent(existing.id, existing.url, calendar.numericId, title, start, end, isAllDay, location, description, color)
                        "homeassistant" -> repository.updateHAEvent(calendar.numericId, existing.id, title, start, end, isAllDay, location, description)
                        "google" -> repository.updateGoogleEvent(calendar.numericId, existing.id, title, start, end, isAllDay, location, description)
                        else -> createForSource(calendar, title, start, end, isAllDay, location, description, color)
                    }
                } else {
                    createForSource(calendar, title, start, end, isAllDay, location, description, color)
                }
            }
            result.onSuccess { afterMutation(); onResult(null) }
                .onFailure { onResult(it.message ?: "Fehler") }
        }
    }

    private suspend fun createForSource(
        calendar: WritableCalendar, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String, color: String?,
    ) {
        when (calendar.source) {
            "local" -> repository.createLocalEvent(calendar.numericId, title, start, end, isAllDay, location, description, color)
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
