package com.scarriffle.calendarr.ui.calendar

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.scarriffle.calendarr.data.CalendarRepository
import com.scarriffle.calendarr.data.SettingsStore
import com.scarriffle.calendarr.data.SyncError
import com.scarriffle.calendarr.domain.model.CalEvent
import com.scarriffle.calendarr.domain.model.CalViewType
import com.scarriffle.calendarr.domain.model.Group
import com.scarriffle.calendarr.domain.model.GroupMember
import com.scarriffle.calendarr.domain.model.LocalCalendar
import com.scarriffle.calendarr.domain.model.WritableCalendar
import com.scarriffle.calendarr.util.Dates
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
    // Per-calendar sync failures from the last successful /events fetch (e.g.
    // expired CalDAV credentials) — the fetch as a whole succeeded, but one or
    // more enabled calendars silently returned nothing. Additive to `error`.
    val syncErrors: List<SyncError> = emptyList(),
    val weekStartsOnMonday: Boolean = true,
    val writableCalendars: List<WritableCalendar> = emptyList(),
    val hiddenKeys: Set<String> = emptySet(),
    val banishedKeys: Set<String> = emptySet(),
    // Calendars ("source:id") the user muted for reminders — events keep their
    // reminders but the scheduler skips them.
    val reminderDisabledKeys: Set<String> = emptySet(),
    // Group overlay: when non-null the calendar shows the group's combined view.
    val groups: List<Group> = emptyList(),
    val activeGroup: Group? = null,
    // Group overlay: full member list (for the filter) + per-member / group-cal
    // hidden keys ("gm:<userId>" / "gc"). In-memory; reset when switching group.
    val activeGroupMembers: List<GroupMember> = emptyList(),
    val hiddenGroupKeys: Set<String> = emptySet(),
    // Full calendar list across all sources (loaded on demand) so the filter
    // shows every calendar, including ones with no events in the loaded range.
    val allCalendars: List<CalendarFilterEntry> = emptyList(),
    // Device-local: month view as horizontal paged (swipe) vs. scroll feed.
    val monthViewPaged: Boolean = false,
    // Device-local: hide the top-bar menu button (drawer opens via edge-swipe).
    val hideMenuButton: Boolean = false,
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
        initialLoad(reconcile = true)
    }

    /**
     * Load the full ±cacheMonths window once, behind the splash, and only then
     * mark ready. Entering the app fully-loaded avoids the first-open jank of
     * loading a big batch while the user is already scrolling.
     */
    private fun initialLoad(reconcile: Boolean = false) {
        val months = settingsStore.cacheMonths.toLong()
        val today = LocalDate.now().withDayOfMonth(1)
        val start = instant(today.minusMonths(months))
        val end = instant(today.plusMonths(months + 1))
        viewModelScope.launch {
            // Honour a calendar hidden/shown on the web BEFORE the first load so
            // the visibility filter is correct before events are rendered.
            if (reconcile) reconcileCalendarVisibility()
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
            reminderDisabledKeys = settingsStore.reminderDisabledCalendarKeys,
            monthViewPaged = settingsStore.monthViewPaged,
            hideMenuButton = settingsStore.hideMenuButton,
        )
    }

    /** Re-read the device-local view prefs (called when settings close). */
    fun refreshMonthViewMode() {
        _state.update { it.copy(
            monthViewPaged = settingsStore.monthViewPaged,
            hideMenuButton = settingsStore.hideMenuButton,
        ) }
    }

    // Device-local calendar order ("source:id"), mirrors the web cal_order.
    val calendarOrder: List<String> get() = settingsStore.calendarOrder
    fun setCalendarOrder(keys: List<String>) { settingsStore.calendarOrder = keys }

    // ---- Contacts birthday import (mirrors the iOS BirthdaysImporter) ----

    var birthdaysSyncEnabled: Boolean
        get() = settingsStore.birthdaysSyncEnabled
        set(value) { settingsStore.birthdaysSyncEnabled = value }

    /** Mirror this device's contact birthdays into the (existing) birthday
     *  calendar: reconcile rows scoped to this device's external_uid prefix
     *  (add / update / delete), then report the device. No-op if disabled or
     *  the birthday calendar hasn't been created. */
    fun syncContactBirthdays(contacts: List<com.scarriffle.calendarr.data.ContactBirthday>, deviceName: String) {
        if (!settingsStore.birthdaysSyncEnabled) return
        viewModelScope.launch {
            runCatching {
                val cal = repository.getLocalCalendars().firstOrNull { it.isBirthday && it.owned }
                    ?: return@runCatching
                val existing = repository.getBirthdayEntries(cal.id)
                val deviceId = settingsStore.birthdaysDeviceId
                val prefix = "contact:$deviceId:"
                val byExt = existing.filter { it.externalUid?.startsWith(prefix) == true }
                    .associateBy { it.externalUid!! }
                val seen = mutableSetOf<String>()
                for (c in contacts) {
                    val ext = prefix + c.contactId
                    seen.add(ext)
                    val (start, end) = birthdayRange(c.month, c.day, c.year)
                    val match = byExt[ext]
                    if (match != null) {
                        val changed = match.title != c.name || match.month != c.month ||
                            match.day != c.day || match.birthYear != c.year
                        if (changed) repository.updateLocalEvent(
                            uid = match.uid, title = c.name, start = start, end = end,
                            isAllDay = true, location = "", description = "", color = null,
                            rrule = "FREQ=YEARLY", birthYear = c.year, externalUid = ext,
                        )
                    } else {
                        repository.createLocalEvent(
                            calendarId = cal.id, title = c.name, start = start, end = end,
                            isAllDay = true, location = "", description = "", color = null,
                            rrule = "FREQ=YEARLY", birthYear = c.year, externalUid = ext,
                        )
                    }
                }
                byExt.filterKeys { it !in seen }.values.forEach { repository.deleteLocalEvent(it.uid) }
                repository.reportBirthdaySync(deviceId, deviceName, contacts.size)
            }
            loadVisible(force = true)
        }
    }

    private fun birthdayRange(month: Int, day: Int, year: Int?): Pair<Instant, Instant> {
        val anchor = year ?: 2000 // leap-safe anchor for Feb 29 with unknown year
        val date = LocalDate.of(anchor, month, day)
        val start = date.atTime(12, 0).atZone(zone).toInstant()
        val end = date.plusDays(1).atTime(12, 0).atZone(zone).toInstant()
        return start to end
    }

    /** Default duration (minutes) for a new event's end time. */
    val defaultEventDurationMinutes: Int get() = settingsStore.loadSettings().defaultEventDurationMinutes

    /** Default reminder offset (minutes before start), or -1 when off. */
    val defaultReminderMinutes: Int get() = settingsStore.loadSettings().defaultReminderMinutes ?: -1

    /** Toggle a calendar's reminders without deleting any event reminders. */
    fun setCalendarRemindersDisabled(key: String, disabled: Boolean) {
        val keys = settingsStore.reminderDisabledCalendarKeys.toMutableSet()
        if (disabled) keys.add(key) else keys.remove(key)
        settingsStore.reminderDisabledCalendarKeys = keys
        _state.update { it.copy(reminderDisabledKeys = keys) }
        val parts = key.split(":")
        val source = parts.getOrNull(0) ?: return
        val id = parts.getOrNull(1)?.toIntOrNull() ?: return
        viewModelScope.launch { runCatching { repository.setCalendarRemindersEnabled(source, id, enabled = !disabled) } }
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
            loadRange(start, end, background = false, force = force)
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
    private suspend fun loadRange(start: Instant, end: Instant, background: Boolean, force: Boolean = false) {
        loadMutex.withLock {
            // Another load (e.g. the background prefetch) may have covered this range.
            // `force` bypasses this so callers can explicitly re-fetch an already-cached
            // range (e.g. to pick up a mutation) without wiping the whole cache first.
            if (!force && isCached(start, end)) return
            val group = _state.value.activeGroup
            val flag = if (background) "bg" else "fg"
            _state.update { if (flag == "bg") it.copy(isBackgroundCaching = true) else it.copy(isLoading = true, error = null) }
            runCatching {
                if (group != null) decorateGroup(repository.fetchGroupCombined(group.id, start, end)) to emptyList<SyncError>()
                else repository.fetchEvents(start, end).let { it.events to it.errors }
            }
                .onSuccess { (events, errors) ->
                    val (keepKeys, keepSources) = failedCalendarKeys(errors)
                    mergeIntoCache(events, start, end, keepKeys, keepSources)
                    refreshFromCache()
                    _state.update { it.copy(syncErrors = errors) }
                }
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

    /**
     * Split sync errors into per-calendar keys and whole sources whose cached
     * events must NOT be evicted on a partial sync — stale data beats an empty
     * calendar. An error carrying a calendar_id protects just that calendar; an
     * account-level error without one (e.g. an HA / Google token-refresh
     * failure, which aborts the whole account fetch) protects every cached
     * calendar of that source.
     */
    private fun failedCalendarKeys(errors: List<SyncError>): Pair<Set<String>, Set<String>> {
        val keys = mutableSetOf<String>()
        val sources = mutableSetOf<String>()
        for (err in errors) {
            val cid = err.calendarId
            if (cid != null) keys.add(calendarKey(err.source, cid.toString()))
            else sources.add(err.source)
        }
        return keys to sources
    }

    private fun mergeIntoCache(
        newEvents: List<CalEvent>, rangeStart: Instant, rangeEnd: Instant,
        keepKeysInRange: Set<String> = emptySet(),
        keepSourcesInRange: Set<String> = emptySet(),
    ) {
        // Remove old events in the fetched range to avoid duplicates — but
        // PRESERVE events from calendars / sources that had sync errors so a
        // transient CalDAV / Google / HA failure doesn't wipe the visible calendar.
        val retained = allCachedEvents.filter { ev ->
            val outsideRange = !ev.startDate.isBefore(rangeEnd) || !ev.endDate.isAfter(rangeStart)
            when {
                outsideRange -> true
                ev.source in keepSourcesInRange -> true
                keepKeysInRange.isEmpty() -> false
                else -> calendarKey(ev.source, ev.calendarId) in keepKeysInRange
            }
        }
        allCachedEvents = retained + newEvents
        // Only extend the cached range on a fully clean fetch. When some
        // calendars/sources failed, leave cachedStart/End unchanged so
        // isCached() stays false and they're retried on the next load rather
        // than being silently treated as "done" with empty data.
        if (keepKeysInRange.isEmpty() && keepSourcesInRange.isEmpty()) {
            cachedStart = cachedStart?.let { minOf(it, rangeStart) } ?: rangeStart
            cachedEnd = cachedEnd?.let { maxOf(it, rangeEnd) } ?: rangeEnd
        }
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
            if (hidden.isEmpty() && banished.isEmpty()) allCachedEvents
            else allCachedEvents.filter { ev ->
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
        initialLoad(reconcile = true)
    }

    /**
     * Called when the app returns to the foreground. Re-checks the server's
     * per-calendar visibility (a calendar may have been hidden/shown on the web
     * or another device meanwhile) and reloads only if something changed.
     */
    fun onAppResumed() {
        viewModelScope.launch {
            if (reconcileCalendarVisibility()) {
                invalidateCache()
                loadGroups()
                initialLoad(reconcile = false) // just reconciled above
            }
        }
    }

    /**
     * Reconcile the local **banished** set with the server's per-calendar
     * `sidebar_hidden` flags for external calendars (CalDAV / Google / HA).
     * Returns `true` if the set changed, so the caller can force a refetch — a
     * calendar re-enabled on the web has NO events in the cache (the server
     * excludes a hidden calendar's events entirely).
     *
     * NOTE: This deliberately drives `banishedKeys`, NOT `hiddenKeys`. The
     * quick-hide (`hiddenKeys`) is a device-local filter and must never be
     * overwritten from the server; only the "banish / permanently hide" state
     * maps to the server's `sidebar_hidden` (mirrors iOS).
     */
    private suspend fun reconcileCalendarVisibility(): Boolean {
        val caldav = runCatching { repository.getCalDAVAccounts() }.getOrDefault(emptyList())
        val google = runCatching { repository.getGoogleAccounts() }.getOrDefault(emptyList())
        val ha = runCatching { repository.getHomeAssistantAccounts() }.getOrDefault(emptyList())

        val banished = settingsStore.banishedCalendarKeys.toMutableSet()
        fun apply(source: String, id: Int, serverHidden: Boolean) {
            val key = calendarKey(source, id.toString())
            if (serverHidden) banished.add(key) else banished.remove(key)
        }
        caldav.forEach { acc -> acc.calendars?.forEach { apply("caldav", it.id, it.sidebarHidden) } }
        google.forEach { acc -> acc.calendars?.forEach { apply("google", it.id, it.sidebarHidden) } }
        ha.forEach { acc -> acc.calendars?.forEach { apply("homeassistant", it.id, it.sidebarHidden) } }

        if (banished == settingsStore.banishedCalendarKeys) return false
        settingsStore.banishedCalendarKeys = banished
        _state.update { it.copy(banishedKeys = banished) }
        return true
    }

    fun clearError() = _state.update { it.copy(error = null) }

    fun clearSyncErrors() = _state.update { it.copy(syncErrors = emptyList()) }

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

    /** Distinct calendars present in the full cache, IGNORING the device-local
     *  quick-hide filter but excluding banished ones — for the filter sheet, so
     *  a locally hidden calendar still appears there and can be toggled back on. */
    fun knownCalendars(): List<CalEvent> {
        val banished = _state.value.banishedKeys
        return allCachedEvents
            .distinctBy { calendarKey(it.source, it.calendarId) }
            .filter { calendarKey(it.source, it.calendarId) !in banished }
    }

    /**
     * Load the full calendar list across all sources into [CalendarUiState.allCalendars]
     * so the filter shows every calendar, even ones with no events in the loaded
     * range. Called when the filter sheet opens. Read-only flag for shared local
     * calendars from owned/permission; banished calendars are dropped.
     */
    fun loadAllCalendars() {
        viewModelScope.launch {
            val banished = _state.value.banishedKeys
            val entries = mutableListOf<CalendarFilterEntry>()
            runCatching { repository.getLocalCalendars() }.getOrDefault(emptyList()).forEach { c ->
                entries += CalendarFilterEntry(
                    key = calendarKey("local", c.id.toString()),
                    name = if (c.owned) c.name else (c.sharedBy ?: c.name),
                    color = c.color,
                    source = "local",
                    readOnly = !c.owned && c.permission != "read_write",
                )
            }
            runCatching { repository.getCalDAVAccounts() }.getOrDefault(emptyList()).forEach { acc ->
                acc.calendars.orEmpty().forEach { c ->
                    entries += CalendarFilterEntry(calendarKey("caldav", c.id.toString()), c.name, c.color ?: acc.color, "caldav")
                }
            }
            runCatching { repository.getGoogleAccounts() }.getOrDefault(emptyList()).forEach { acc ->
                acc.calendars.orEmpty().forEach { c ->
                    entries += CalendarFilterEntry(calendarKey("google", c.id.toString()), c.name, c.color ?: "#4285f4", "google")
                }
            }
            runCatching { repository.getHomeAssistantAccounts() }.getOrDefault(emptyList()).forEach { acc ->
                acc.calendars.orEmpty().forEach { c ->
                    entries += CalendarFilterEntry(calendarKey("homeassistant", c.id.toString()), c.name, c.color ?: "#46bdc6", "homeassistant")
                }
            }
            runCatching { repository.getICalSubscriptions() }.getOrDefault(emptyList()).forEach { s ->
                entries += CalendarFilterEntry(calendarKey("ical", s.id.toString()), s.name, s.color, "ical")
            }
            _state.update { st -> st.copy(allCalendars = entries.filter { it.key !in banished }) }
        }
    }

    /** The user's single birthday calendar, or null if not activated yet. */
    suspend fun birthdayCalendar(): LocalCalendar? =
        runCatching { repository.getLocalCalendars() }.getOrDefault(emptyList())
            .firstOrNull { it.isBirthday && it.owned }

    /** The birthday calendar, creating the single one (named [name]) if none. */
    suspend fun ensureBirthdayCalendar(name: String): LocalCalendar? {
        birthdayCalendar()?.let { return it }
        return runCatching {
            repository.addLocalCalendar(name, "#E0407F", isBirthday = true)
        }.getOrNull()
    }

    /**
     * Create a manual birthday: an all-day, yearly-recurring local event whose
     * age suffix and cake icon are added server-side. When the year is unknown
     * we anchor to 1970 and send no birth_year (so no age is shown).
     */
    fun createBirthday(
        calendarId: Int, name: String, date: LocalDate, yearKnown: Boolean, onDone: () -> Unit,
    ) {
        viewModelScope.launch {
            val anchor = LocalDate.of(if (yearKnown) date.year else 1970, date.monthValue, date.dayOfMonth)
            val start = Dates.startOfDay(anchor)
            val end = Dates.startOfDay(anchor.plusDays(1))
            runCatching {
                repository.createLocalEvent(
                    calendarId, name, start, end, isAllDay = true,
                    location = "", description = "", color = null,
                    rrule = "FREQ=YEARLY", birthYear = if (yearKnown) date.year else null,
                )
            }.onSuccess { loadVisible(force = true); onDone() }
        }
    }

    /**
     * Banish ("permanently hide") a calendar, or lift the banish. Unlike the
     * quick-hide, this DOES sync to the server (`sidebar_hidden`/`enabled`) for
     * external calendars, matching iOS. Banishing also clears any local
     * quick-hide flag for the same key (redundant once banished).
     */
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

        val parts = key.split(":")
        val source = parts.getOrNull(0)
        val id = parts.getOrNull(1)?.toIntOrNull()
        if (source != null && id != null && source in listOf("caldav", "google", "homeassistant")) {
            viewModelScope.launch {
                runCatching { repository.setCalendarSidebarHidden(source, id, banished) }
                    .onFailure { e -> _state.update { it.copy(error = e.message ?: "Fehler beim Speichern") } }
                // Un-banishing re-enables the calendar on the server, but its
                // events were excluded while hidden — force a refetch so they
                // reappear without a manual sync.
                if (!banished) {
                    invalidateCache()
                    initialLoad(reconcile = false)
                }
            }
        }
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

    /**
     * Re-fetch just the already-cached range after a create/update so the edit is
     * reflected everywhere it's currently loaded, without nuking and reloading the
     * whole ±cacheMonths window (which caused a full-screen freeze on every save).
     * Falls back to [initialLoad] if nothing was cached yet.
     */
    private fun afterMutation() {
        val start = cachedStart
        val end = cachedEnd
        if (start == null || end == null) {
            initialLoad()
            return
        }
        viewModelScope.launch {
            loadRange(start, end, background = false, force = true)
            markReady()
        }
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
        reminders: List<Int> = emptyList(),
        onResult: (String?) -> Unit,
    ) {
        viewModelScope.launch {
            val result = runCatching {
                if (existing != null && existing.source == calendar.source) {
                    when (existing.source) {
                        "local" -> repository.updateLocalEvent(existing.id, title, start, end, isAllDay, location, description, color, isPrivate, reminders)
                        "caldav" -> repository.updateCalDAVEvent(existing.id, existing.url, calendar.numericId, title, start, end, isAllDay, location, description, color)
                        "homeassistant" -> repository.updateHAEvent(calendar.numericId, existing.id, title, start, end, isAllDay, location, description)
                        "google" -> repository.updateGoogleEvent(calendar.numericId, existing.id, title, start, end, isAllDay, location, description)
                        else -> createForSource(calendar, title, start, end, isAllDay, location, description, color, isPrivate, reminders)
                    }
                } else {
                    createForSource(calendar, title, start, end, isAllDay, location, description, color, isPrivate, reminders)
                }
            }
            result.onSuccess { afterMutation(); onResult(null) }
                .onFailure { onResult(it.message ?: "Fehler") }
        }
    }

    private suspend fun createForSource(
        calendar: WritableCalendar, title: String, start: Instant, end: Instant,
        isAllDay: Boolean, location: String, description: String, color: String?, isPrivate: Boolean,
        reminders: List<Int> = emptyList(),
    ) {
        when (calendar.source) {
            "local" -> repository.createLocalEvent(calendar.numericId, title, start, end, isAllDay, location, description, color, isPrivate, reminders)
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
