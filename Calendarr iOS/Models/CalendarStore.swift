import Foundation
import SwiftUI
import CalendarrCore

extension Notification.Name {
    /// Posted whenever the persistent "banished calendars" set is mutated from
    /// outside the active `CalendarStore` (e.g. by `AccountsView`). The store
    /// listens for this in `CalendarHostView` and refreshes its filter.
    static let banishedCalendarsChanged = Notification.Name("banishedCalendarsChanged")

    /// Posted when the user taps the manual "sync with server" button in the
    /// menu. `CalendarHostView` responds by invalidating the cache and
    /// re-fetching events from the server.
    static let manualSyncRequested = Notification.Name("manualSyncRequested")
}

enum CalViewType: String, CaseIterable {
    case month, week, day, quarter, agenda

    func label(_ lang: String) -> String {
        switch self {
        case .month:   return L10n.t("view.month",   lang)
        case .week:    return L10n.t("view.week",    lang)
        case .day:     return L10n.t("view.day",     lang)
        case .quarter: return L10n.t("view.quarter", lang)
        case .agenda:  return L10n.t("view.agenda",  lang)
        }
    }

    var systemImage: String {
        switch self {
        case .month:   return "calendar"
        case .week:    return "calendar.day.timeline.leading"
        case .day:     return "sun.max"
        case .quarter: return "calendar.badge.clock"
        case .agenda:  return "list.bullet"
        }
    }
}

struct WritableCalendar: Identifiable {
    let id: String
    let name: String
    let color: String
    let source: String
    let numericId: Int
}

@Observable
class CalendarStore {
    // Visible state
    var events: [CalEvent] = []
    var viewType: CalViewType = .month
    var currentDate: Date = .now
    // The month currently scrolled into view (month view). Lives in the store so
    // the Liquid-Glass navigation title — read in the system toolbar — updates
    // via @Observable tracking (a plain @State did not refresh the toolbar).
    var visibleMonth: Date = .now
    var isLoading = false
    var isCachingBackground = false
    var lastError: String? = nil
    /// Per-calendar sync failures reported alongside the last successful
    /// personal `/events` fetch (e.g. expired CalDAV credentials on one
    /// account) — distinct from `lastError`, which means the whole fetch
    /// failed. Not populated in group-overlay mode. Left untouched on a hard
    /// fetch failure (see `loadEvents`), so a stale-but-real warning doesn't
    /// get wiped by an unrelated network hiccup.
    var syncErrors: [SyncError] = []
    var weekStartsOnMonday = true
    var writableCalendars: [WritableCalendar] = []
    // When set, the calendar shows the group's combined overlay instead of the
    // user's own events. nil = personal view.
    var activeGroup: CalGroup? = nil

    /// Set of `"source:calendarId"` keys the user has chosen to hide from the
    /// calendar views. Persisted in UserDefaults as a JSON array. Events whose
    /// key matches one of these are filtered out before being rendered.
    var hiddenCalendarKeys: Set<String> = CalendarStore.loadHiddenKeys()

    /// "Banished" calendars – like `hiddenCalendarKeys` but expressing a
    /// stronger user intent: the calendar should not even appear in the quick
    /// show/hide list. Re-activation happens in AccountsView.
    var banishedCalendarKeys: Set<String> = CalendarStore.loadBanishedKeys()

    /// Set of `"source:calendarId"` keys whose events must NOT generate reminder
    /// notifications (mirrors the server `reminders_enabled=false` flag). Persisted
    /// in UserDefaults; reconciled from the server in the filter sheet.
    var reminderDisabledKeys: Set<String> = CalendarStore.loadReminderDisabledKeys()

    /// Group-overlay visibility: which members' calendars (`gm:<userId>`) and the
    /// group calendar (`gc`) are hidden in the combined view — like hiding
    /// individual people in Outlook. In-memory; resets when leaving/switching a
    /// group (the per-calendar hide/banish sets are for the personal view only).
    var hiddenGroupKeys: Set<String> = []

    static func groupMemberKey(_ ownerId: Int) -> String { "gm:\(ownerId)" }
    static let groupCalendarKey = "gc"

    // Cache bookkeeping
    private var cachedStart: Date? = nil
    private var cachedEnd: Date? = nil
    private var allCachedEvents: [CalEvent] = []

    // MARK: – Hidden-calendar persistence

    private static let hiddenKeysDefaultsKey = "hiddenCalendarKeys"

    private static func loadHiddenKeys() -> Set<String> {
        guard let raw = UserDefaults.standard.string(forKey: hiddenKeysDefaultsKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }

    private func saveHiddenKeys() {
        let arr = Array(hiddenCalendarKeys)
        if let data = try? JSONEncoder().encode(arr),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: Self.hiddenKeysDefaultsKey)
        }
    }

    /// Toggle visibility of a single calendar and immediately refresh the
    /// visible event list + widget snapshot.
    func setCalendarHidden(_ key: String, hidden: Bool) {
        if hidden { hiddenCalendarKeys.insert(key) } else { hiddenCalendarKeys.remove(key) }
        saveHiddenKeys()
        let (s, e) = rangeForCurrentView()
        refreshFromCache(start: s, end: e)
        publishWidgetSnapshot()
    }

    /// Replace the entire set (used by the filter sheet's bulk show/hide).
    func setHiddenCalendars(_ keys: Set<String>) {
        hiddenCalendarKeys = keys
        saveHiddenKeys()
        let (s, e) = rangeForCurrentView()
        refreshFromCache(start: s, end: e)
        publishWidgetSnapshot()
    }

    /// Toggle / replace group-overlay visibility (members or the group calendar).
    func setGroupKeyHidden(_ key: String, hidden: Bool) {
        if hidden { hiddenGroupKeys.insert(key) } else { hiddenGroupKeys.remove(key) }
        let (s, e) = rangeForCurrentView()
        refreshFromCache(start: s, end: e)
    }

    func setHiddenGroupKeys(_ keys: Set<String>) {
        hiddenGroupKeys = keys
        let (s, e) = rangeForCurrentView()
        refreshFromCache(start: s, end: e)
    }

    static func calendarKey(source: String, calendarId: String) -> String {
        // The events API returns `calendar_id` inconsistently: a raw numeric for
        // CalDAV, but "<source>-<id>" for local / ical / google / homeassistant
        // (e.g. "local-3", "google-5"). The filter UI keys off the numeric DB id,
        // so strip any leading "<source>-" prefix to make event keys and filter
        // keys comparable — otherwise local hiding/banishing silently does nothing
        // for those sources.
        var id = calendarId
        let prefix = "\(source)-"
        if id.hasPrefix(prefix) { id = String(id.dropFirst(prefix.count)) }
        return "\(source):\(id)"
    }

    // MARK: – Calendar order (device-local, mirrors the web `cal_order`)

    private static let orderDefaultsKey = "calendarOrder"

    /// Persisted display order of calendar keys ("source:id"). Device-local; the
    /// drawer's flat calendar list is sorted by this.
    private(set) var calendarOrder: [String] = CalendarStore.loadOrder()

    private static func loadOrder() -> [String] {
        guard let raw = UserDefaults.standard.string(forKey: orderDefaultsKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return arr
    }

    private func saveOrder() {
        if let data = try? JSONEncoder().encode(calendarOrder),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: Self.orderDefaultsKey)
        }
    }

    /// Replace the stored order (after a drag-reorder).
    func setCalendarOrder(_ keys: [String]) {
        calendarOrder = keys
        saveOrder()
    }

    /// Sort the given keys by the stored order (unknown keys → end), then persist
    /// the normalized order so newly-added calendars stick (mirrors the web).
    func ordered(_ keys: [String]) -> [String] {
        let current = calendarOrder
        func idx(_ key: String) -> Int { current.firstIndex(of: key) ?? Int.max }
        let sorted = keys.sorted { a, b in
            let ia = idx(a), ib = idx(b)
            return ia != ib ? ia < ib : a < b
        }
        calendarOrder = sorted
        saveOrder()
        return sorted
    }

    // MARK: – Banished-calendar persistence

    private static let banishedKeysDefaultsKey = "banishedCalendarKeys"

    static func loadBanishedKeys() -> Set<String> {
        guard let raw = UserDefaults.standard.string(forKey: banishedKeysDefaultsKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }

    static func saveBanishedKeys(_ keys: Set<String>) {
        let arr = Array(keys)
        if let data = try? JSONEncoder().encode(arr),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: banishedKeysDefaultsKey)
        }
    }

    /// Move a calendar to / out of the banished set. Also clears any quick
    /// hidden flag for that key – once banished, the dual state is redundant.
    /// Posts `.banishedCalendarsChanged` so other views in the navigation
    /// stack (e.g. AccountsView) stay in sync.
    func setCalendarBanished(_ key: String, banished: Bool) {
        if banished {
            banishedCalendarKeys.insert(key)
            hiddenCalendarKeys.remove(key)
        } else {
            banishedCalendarKeys.remove(key)
        }
        Self.saveBanishedKeys(banishedCalendarKeys)
        saveHiddenKeys()
        NotificationCenter.default.post(name: .banishedCalendarsChanged, object: nil)
        let (s, e) = rangeForCurrentView()
        refreshFromCache(start: s, end: e)
        publishWidgetSnapshot()
    }

    /// Replace the whole banished set (used when reconciling with the server's
    /// `sidebar_hidden` flags). Persists, notifies, refreshes.
    func setBanishedCalendars(_ keys: Set<String>) {
        guard keys != banishedCalendarKeys else { return }
        banishedCalendarKeys = keys
        Self.saveBanishedKeys(keys)
        NotificationCenter.default.post(name: .banishedCalendarsChanged, object: nil)
        let (s, e) = rangeForCurrentView()
        refreshFromCache(start: s, end: e)
        publishWidgetSnapshot()
    }

    /// Re-read the banished set from UserDefaults – called when an external
    /// view (AccountsView) mutated it. Refreshes visible events + widgets.
    func syncBanishedFromDefaults() {
        banishedCalendarKeys = Self.loadBanishedKeys()
        let (s, e) = rangeForCurrentView()
        refreshFromCache(start: s, end: e)
        publishWidgetSnapshot()
    }

    /// Reconcile the local "banished" set with the server's per-calendar
    /// `sidebar_hidden` flags (server wins for CalDAV / Google / HA). Returns
    /// `true` if the set changed, so the caller can force a refetch.
    ///
    /// This closes the sync gap where hiding/showing a calendar on the web (or
    /// another device) was only ever picked up when the filter sheet or the
    /// accounts screen happened to be opened — not on app launch / resume. A
    /// calendar re-enabled on the web has NO events in the cache (the server
    /// excludes a hidden calendar's events entirely), so a plain
    /// `refreshFromCache` can't bring them back: the caller must force a reload.
    func reconcileCalendarVisibility(api: CalendarrAPI) async -> Bool {
        async let c = (try? await api.getCalDAVAccounts()) ?? []
        async let g = (try? await api.getGoogleAccounts()) ?? []
        async let h = (try? await api.getHomeAssistantAccounts()) ?? []
        let (caldav, google, ha) = await (c, g, h)

        var b = banishedCalendarKeys
        func applyServerHidden(_ source: String, _ id: Int, _ hidden: Bool) {
            let key = Self.calendarKey(source: source, calendarId: "\(id)")
            if hidden { b.insert(key) } else { b.remove(key) }
        }
        for acc in caldav { for cal in acc.calendars ?? [] { applyServerHidden("caldav", cal.id, cal.sidebarHidden) } }
        for acc in google { for cal in acc.calendars ?? [] { applyServerHidden("google", cal.id, cal.sidebarHidden) } }
        for acc in ha     { for cal in acc.calendars ?? [] { applyServerHidden("homeassistant", cal.id, cal.sidebarHidden) } }

        guard b != banishedCalendarKeys else { return false }
        banishedCalendarKeys = b
        Self.saveBanishedKeys(b)
        NotificationCenter.default.post(name: .banishedCalendarsChanged, object: nil)
        return true
    }

    // MARK: – Reminder-disabled-calendar persistence

    private static let reminderDisabledKeysDefaultsKey = "reminderDisabledCalendarKeys"

    static func loadReminderDisabledKeys() -> Set<String> {
        guard let raw = UserDefaults.standard.string(forKey: reminderDisabledKeysDefaultsKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }

    static func saveReminderDisabledKeys(_ keys: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(keys)),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: reminderDisabledKeysDefaultsKey)
        }
    }

    /// Toggle whether a single calendar's events generate reminders, then
    /// reschedule notifications from the cache.
    func setReminderDisabled(_ key: String, disabled: Bool) {
        if disabled { reminderDisabledKeys.insert(key) } else { reminderDisabledKeys.remove(key) }
        Self.saveReminderDisabledKeys(reminderDisabledKeys)
        rescheduleNotifications()
    }

    /// Replace the whole set (used when reconciling with the server's
    /// `reminders_enabled` flags in the filter sheet).
    func setReminderDisabledKeys(_ keys: Set<String>) {
        guard keys != reminderDisabledKeys else { return }
        reminderDisabledKeys = keys
        Self.saveReminderDisabledKeys(keys)
        rescheduleNotifications()
    }

    /// Split a `"source:calendarId"` key back into its parts.
    static func parseCalendarKey(_ key: String) -> (source: String, id: Int)? {
        guard let colon = key.firstIndex(of: ":") else { return nil }
        let source = String(key[..<colon])
        guard let id = Int(key[key.index(after: colon)...]) else { return nil }
        return (source, id)
    }

    /// Sources whose visibility is backed by the server's `sidebar_hidden`.
    static let serverManagedSources: Set<String> = ["caldav", "google", "homeassistant"]

    var userCalendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = weekStartsOnMonday ? 2 : 1
        return cal
    }

    // MARK: – Cache helpers

    func isCached(start: Date, end: Date) -> Bool {
        guard let cs = cachedStart, let ce = cachedEnd else { return false }
        return cs <= start && ce >= end
    }

    /// Republish the full cached event set, applying only visibility filters
    /// (hidden + banished). We deliberately do NOT slice by the current view's
    /// date window: the user's chosen cache range is already loaded, and
    /// scrolling within it must not make events vanish. Per-day / per-range
    /// rendering is the responsibility of `events(on:)` / `events(in:)`.
    /// `start` / `end` are kept in the signature for call-site clarity.
    func refreshFromCache(start: Date, end: Date) {
        _ = (start, end)
        // In group overlay mode the per-calendar hide/banish toggles don't apply;
        // instead honour the per-member / group-calendar toggles (hiddenGroupKeys).
        if activeGroup != nil {
            if hiddenGroupKeys.isEmpty {
                events = allCachedEvents
            } else {
                events = allCachedEvents.filter { ev in
                    if ev.isGroupEvent { return !hiddenGroupKeys.contains(Self.groupCalendarKey) }
                    if let o = ev.owner { return !hiddenGroupKeys.contains(Self.groupMemberKey(o.id ?? -1)) }
                    return true
                }
            }
            return
        }
        events = allCachedEvents.filter { ev in
            let key = Self.calendarKey(source: ev.source, calendarId: ev.calendarId)
            return !hiddenCalendarKeys.contains(key)
                && !banishedCalendarKeys.contains(key)
        }
        // Personal events drive local reminder notifications.
        NotificationScheduler.reschedule(events: allCachedEvents, disabledCalendarKeys: reminderDisabledKeys)
    }

    /// Recompute scheduled reminder notifications from the personal cache
    /// (skipped while a group overlay is active).
    func rescheduleNotifications() {
        guard activeGroup == nil else { return }
        NotificationScheduler.reschedule(events: allCachedEvents, disabledCalendarKeys: reminderDisabledKeys)
    }

    /// Optimistically drop a just-deleted event from the cache so it disappears
    /// from the UI immediately, without waiting for a server round-trip (HA
    /// deletes can lag several seconds, and an immediate refetch could even
    /// re-add it before the source propagated the deletion).
    func removeCachedEvent(id: String) {
        allCachedEvents.removeAll { $0.id == id }
        events.removeAll { $0.id == id }
        publishWidgetSnapshot()
    }

    // MARK: – Network loading

    /// Load events for a specific range. Skips the network if already cached,
    /// unless `force` is set (used after create/edit to pull fresh server data
    /// for the visible range, bypassing the cache).
    func loadEvents(api: CalendarrAPI, start: Date, end: Date, force: Bool = false) async {
        if !force, isCached(start: start, end: end) {
            refreshFromCache(start: start, end: end)
            return
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let (fetched, errors) = try await fetchForMode(api: api, start: start, end: end)
            syncErrors = errors
            let failed = failedCalendarKeys(from: errors)
            mergeIntoCache(fetched, rangeStart: start, rangeEnd: end,
                           keepKeysInRange: failed.keys, keepSourcesInRange: failed.sources)
            refreshFromCache(start: start, end: end)
        } catch {
            // Hard failure – leave `syncErrors` as-is; it reflects the last
            // *successful* fetch and shouldn't be wiped by an unrelated
            // network error on this attempt.
            lastError = error.localizedDescription
        }
    }

    /// Fetch events for the current mode (personal vs. group overlay). Group
    /// events go through the same cache/prefetch/refresh path as personal ones,
    /// so the whole visible grid is covered (no "only the middle weeks" gaps).
    /// Per-calendar sync errors are only reported by the personal `/events`
    /// endpoint; group overlays always report none.
    private func fetchForMode(api: CalendarrAPI, start: Date, end: Date) async throws -> (events: [CalEvent], errors: [SyncError]) {
        if let g = activeGroup {
            let combined = try await api.fetchGroupCombined(groupId: g.id, start: start, end: end)
            return (combined.map { decorateGroupEvent($0) }, [])
        }
        return try await api.fetchEvents(start: start, end: end)
    }

    /// Prefix a combined-view event with its owner (others) or 👥 + creator
    /// (group calendar). Colour comes from the server's display_color.
    private func decorateGroupEvent(_ ev: CalEvent) -> CalEvent {
        // Prefer the server-decorated title (group icon + owner prefix) so web,
        // iOS and Android render group events identically. `title` stays raw.
        if let dt = ev.displayTitle, !dt.isEmpty {
            var e = ev
            e.title = dt
            return e
        }
        // Fallback for older servers without display_title.
        var e = ev
        let me = UserDefaults.standard.integer(forKey: "userId")
        let groupIcon = activeGroup?.icon ?? "👥"
        func first(_ s: String) -> String { s.split(separator: " ").first.map(String.init) ?? s }
        if ev.isGroupEvent {
            if let c = ev.creator, c.id != me { e.title = "\(groupIcon) \(first(c.displayName)): \(ev.title)" }
            else { e.title = "\(groupIcon) \(ev.title)" }
        } else if let o = ev.owner, o.id != me {
            e.title = "\(first(o.displayName)): \(ev.title)"
        }
        return e
    }

    /// Background prefetch for ±months around today – called once on startup.
    func prefetchBackground(api: CalendarrAPI, months: Int) async {
        let cal = userCalendar
        let now = Date()
        let start = cal.date(byAdding: .month, value: -months, to: cal.startOfDay(for: now))!
        let end   = cal.date(byAdding: .month, value: months + 1, to: cal.startOfDay(for: now))!
        guard !isCached(start: start, end: end) else { return }

        isCachingBackground = true
        defer { isCachingBackground = false }
        do {
            let (fetched, errors) = try await fetchForMode(api: api, start: start, end: end)
            syncErrors = errors
            let failed = failedCalendarKeys(from: errors)
            mergeIntoCache(fetched, rangeStart: start, rangeEnd: end,
                           keepKeysInRange: failed.keys, keepSourcesInRange: failed.sources)
            // Refresh visible range from newly expanded cache
            let (vs, ve) = rangeForCurrentView()
            refreshFromCache(start: vs, end: ve)
        } catch {
            // Background fetch failure is silent
        }
    }

    /// Trigger a full cache reload (e.g. when cache-range setting changes).
    /// Intentionally keeps `events` intact so the UI stays populated while
    /// the network fetch runs; `refreshFromCache` will swap in fresh data
    /// atomically once it arrives.
    func invalidateCache() {
        cachedStart = nil
        cachedEnd = nil
        allCachedEvents = []
    }

    /// Calendars / sources that reported a sync error on the last fetch. Events
    /// matching either must NOT be evicted from the cache on a partial sync —
    /// stale data beats a completely empty calendar.
    ///
    /// - `keys`:    per-calendar errors carrying a `calendar_id` (e.g. one CalDAV
    ///              calendar with bad credentials) → protect just that calendar.
    /// - `sources`: account-level errors the server couldn't pin to a single
    ///              calendar → protect every cached calendar of that source. The
    ///              key example is a Home Assistant / Google token-refresh
    ///              failure: it aborts the whole account fetch, so the error
    ///              arrives with no `calendar_id` and every HA calendar would
    ///              otherwise be wiped.
    private func failedCalendarKeys(from errors: [SyncError]) -> (keys: Set<String>, sources: Set<String>) {
        var keys = Set<String>()
        var sources = Set<String>()
        for err in errors {
            if let cid = err.calendarId {
                keys.insert(Self.calendarKey(source: err.source, calendarId: cid))
            } else {
                sources.insert(err.source)
            }
        }
        return (keys, sources)
    }

    private func mergeIntoCache(_ newEvents: [CalEvent], rangeStart: Date, rangeEnd: Date,
                                 keepKeysInRange: Set<String> = [],
                                 keepSourcesInRange: Set<String> = []) {
        // Remove old events in the fetched range to avoid duplicates — but
        // PRESERVE events from calendars / sources that had sync errors so that a
        // transient CalDAV / Google / HA failure doesn't wipe the visible calendar.
        let retained = allCachedEvents.filter { ev in
            let outsideRange = ev.startDate >= rangeEnd || ev.endDate <= rangeStart
            if outsideRange { return true }
            if keepSourcesInRange.contains(ev.source) { return true }
            guard !keepKeysInRange.isEmpty else { return false }
            let key = Self.calendarKey(source: ev.source, calendarId: ev.calendarId)
            return keepKeysInRange.contains(key)
        }
        allCachedEvents = retained + newEvents

        // Only extend the cached range when the fetch was completely clean.
        // When some calendars/sources had sync errors, leave cachedStart/End
        // unchanged: this keeps isCached() returning false for the next
        // loadEvents call so the failed calendars are retried automatically —
        // rather than being silently treated as "done" with empty data
        // (especially important on first launch or after forceReload).
        guard keepKeysInRange.isEmpty, keepSourcesInRange.isEmpty else { return }
        if let cs = cachedStart, let ce = cachedEnd {
            cachedStart = min(cs, rangeStart)
            cachedEnd   = max(ce, rangeEnd)
        } else {
            cachedStart = rangeStart
            cachedEnd   = rangeEnd
        }

        publishWidgetSnapshot()
    }

    /// Write a slim snapshot of the next ~6 weeks into the App-Group container
    /// so the widget extension can render without a network call. 42 days
    /// covers the worst-case month grid (6 rows × 7 cols) for the calendar
    /// widget. Also asks the system to refresh the widget timeline.
    private func publishWidgetSnapshot() {
        // Never write group-view data into the widget; it would show other
        // people's calendar colours and decorated event titles.
        guard activeGroup == nil else { return }

        let cal = userCalendar
        let now = Date()
        // Include the week before today so widgets that show the current week
        // (e.g. "This Week", "Up Next + Calendar") have data for Monday–today.
        // The window is published in the snapshot as coverageStart/coverageEnd:
        // outside it a reader has no information, which is not the same as
        // having no events, and only the writer knows where the edge is.
        let dayStart = cal.startOfDay(for: now)
        let from = cal.date(byAdding: .day, value: -SnapshotCoverage.daysBehind, to: dayStart) ?? now
        let to   = cal.date(byAdding: .day, value: SnapshotCoverage.daysAhead, to: dayStart) ?? from

        // Build the calendar list from all cached events (not just the window)
        // so every calendar appears in the widget configuration picker.
        var calendarMap: [String: WidgetCalendar] = [:]
        for ev in allCachedEvents {
            let key = Self.calendarKey(source: ev.source, calendarId: ev.calendarId)
            guard !banishedCalendarKeys.contains(key) else { continue }
            if calendarMap[key] == nil {
                calendarMap[key] = WidgetCalendar(id: key,
                                                  name: ev.calendarName.isEmpty ? ev.calendarId : ev.calendarName,
                                                  colorHex: ev.calendarColor)
            }
        }
        let calendars = Array(calendarMap.values).sorted { $0.name < $1.name }
        WidgetStore.writeCalendars(calendars)

        let visible = allCachedEvents
            .filter { ev in
                let key = Self.calendarKey(source: ev.source, calendarId: ev.calendarId)
                return ev.startDate < to && ev.endDate > from
                    && !hiddenCalendarKeys.contains(key)
                    && !banishedCalendarKeys.contains(key)
            }
            .sorted { $0.startDate < $1.startDate }
            .prefix(SnapshotCoverage.maxEvents)
            .map { ev in
                WidgetEvent(id: ev.id,
                            title: ev.title,
                            start: ev.startDate,
                            end: ev.endDate,
                            isAllDay: ev.isAllDay,
                            colorHex: ev.effectiveColor,
                            location: ev.location,
                            calendarKey: Self.calendarKey(source: ev.source, calendarId: ev.calendarId))
            }
        let snapshot = WidgetStore.makeSnapshot(events: Array(visible),
                                               coverageStart: from,
                                               coverageEnd: to)
        WidgetStore.write(snapshot)
        WidgetTimelineNotifier.reload()
        // The watch has its own container and cannot read the file we just
        // wrote, so it is handed the data explicitly.
        WatchSyncService.shared.push(snapshot: snapshot, calendars: calendars)
    }

    // MARK: – Writable calendars

    func loadWritableCalendars(api: CalendarrAPI) async {
        async let localCals  = (try? await api.getLocalCalendars()) ?? []
        async let caldavAccs = (try? await api.getCalDAVAccounts()) ?? []
        async let googleCals = (try? await api.getGoogleCalendars()) ?? []
        async let haCals     = (try? await api.getHACalendars()) ?? []

        var result: [WritableCalendar] = []
        // Skip read-only shared calendars — offering them in the event editor
        // only leads to a 403 on save. Own + read_write (incl. group) stay.
        for cal in await localCals where cal.owned || cal.permission == "read_write" {
            result.append(WritableCalendar(id: "local-\(cal.id)", name: cal.name, color: cal.color, source: "local", numericId: cal.id))
        }
        for acc in await caldavAccs where acc.enabled {
            for cal in acc.calendars ?? [] where cal.enabled {
                result.append(WritableCalendar(id: "caldav-\(cal.id)", name: "\(acc.name) – \(cal.name)", color: cal.color ?? acc.color, source: "caldav", numericId: cal.id))
            }
        }
        for (email, id, name, color) in await googleCals {
            result.append(WritableCalendar(id: "google-\(id)", name: "\(email) – \(name)", color: color, source: "google", numericId: id))
        }
        for (accName, id, name, color) in await haCals {
            result.append(WritableCalendar(id: "ha-\(id)", name: "\(accName) – \(name)", color: color, source: "homeassistant", numericId: id))
        }
        writableCalendars = result
    }

    // MARK: – Query helpers

    func events(on date: Date) -> [CalEvent] {
        let cal = userCalendar
        let dayStart = cal.startOfDay(for: date)
        let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart)!
        return events.filter { ev in ev.startDate < dayEnd && ev.endDate > dayStart }
            .sorted { $0.startDate < $1.startDate }
    }

    func events(in start: Date, end: Date) -> [CalEvent] {
        events.filter { ev in ev.startDate < end && ev.endDate > start }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: – Navigation

    func moveToToday() { currentDate = .now }

    func navigatePrev() {
        currentDate = userCalendar.date(byAdding: navComponent, value: navAmount * -1, to: currentDate) ?? currentDate
    }

    func navigateNext() {
        currentDate = userCalendar.date(byAdding: navComponent, value: navAmount, to: currentDate) ?? currentDate
    }

    private var navComponent: Calendar.Component {
        switch viewType {
        case .week:            return .weekOfYear
        case .day:             return .day
        default:               return .month
        }
    }
    private var navAmount: Int { viewType == .quarter ? 3 : 1 }

    func rangeForCurrentView() -> (Date, Date) {
        let cal = userCalendar
        switch viewType {
        case .month:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: currentDate))!
            return (cal.date(byAdding: .month, value: -1, to: start)!,
                    cal.date(byAdding: .month, value: 2, to: start)!)
        case .quarter:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: currentDate))!
            return (start, cal.date(byAdding: .month, value: 4, to: start)!)
        case .week:
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate))!
            return (weekStart, cal.date(byAdding: .day, value: 8, to: weekStart)!)
        case .day:
            let dayStart = cal.startOfDay(for: currentDate)
            return (dayStart, cal.date(byAdding: .day, value: 1, to: dayStart)!)
        case .agenda:
            let start = cal.startOfDay(for: .now)
            return (start, cal.date(byAdding: .day, value: 90, to: start)!)
        }
    }

    func titleForCurrentView(language: String) -> String {
        let cal = userCalendar
        let loc = L10n.locale(language)
        let fmt = DateFormatter(); fmt.locale = loc
        switch viewType {
        case .month:
            fmt.dateFormat = "LLLL yyyy"
            return fmt.string(from: currentDate).capitalized(with: loc)
        case .quarter:
            fmt.dateFormat = "LLL yyyy"
            let m3 = cal.date(byAdding: .month, value: 2, to: currentDate) ?? currentDate
            return "\(fmt.string(from: currentDate)) – \(fmt.string(from: m3))"
        case .week:
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate))!
            let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!
            fmt.dateFormat = "d. MMM"
            let ef = DateFormatter(); ef.locale = loc; ef.dateFormat = "d. MMM yyyy"
            return "\(fmt.string(from: weekStart)) – \(ef.string(from: weekEnd))"
        case .day:
            fmt.dateFormat = "EEEE, d. MMMM yyyy"
            return fmt.string(from: currentDate)
        case .agenda:
            return L10n.t("view.agenda", language)
        }
    }
}
