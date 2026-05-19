import Foundation
import SwiftUI

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
    var isLoading = false
    var isCachingBackground = false
    var lastError: String? = nil
    var weekStartsOnMonday = true
    var writableCalendars: [WritableCalendar] = []

    // Cache bookkeeping
    private var cachedStart: Date? = nil
    private var cachedEnd: Date? = nil
    private var allCachedEvents: [CalEvent] = []

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

    /// Fast in-memory refresh of `events` for the current visible range.
    /// Call this after navigation without hitting the network.
    func refreshFromCache(start: Date, end: Date) {
        events = allCachedEvents.filter { ev in
            ev.startDate < end && ev.endDate > start
        }
    }

    // MARK: – Network loading

    /// Load events for a specific range – skips network if already cached.
    func loadEvents(api: CalendarrAPI, start: Date, end: Date) async {
        if isCached(start: start, end: end) {
            refreshFromCache(start: start, end: end)
            return
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let fetched = try await api.fetchEvents(start: start, end: end)
            mergeIntoCache(fetched, rangeStart: start, rangeEnd: end)
            refreshFromCache(start: start, end: end)
        } catch {
            lastError = error.localizedDescription
        }
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
            let fetched = try await api.fetchEvents(start: start, end: end)
            mergeIntoCache(fetched, rangeStart: start, rangeEnd: end)
            // Refresh visible range from newly expanded cache
            let (vs, ve) = rangeForCurrentView()
            refreshFromCache(start: vs, end: ve)
        } catch {
            // Background fetch failure is silent
        }
    }

    /// Trigger a full cache reload (e.g. when cache-range setting changes).
    func invalidateCache() {
        cachedStart = nil
        cachedEnd = nil
        allCachedEvents = []
        events = []
    }

    private func mergeIntoCache(_ newEvents: [CalEvent], rangeStart: Date, rangeEnd: Date) {
        // Remove old events that overlap with the newly fetched range (avoid duplicates)
        let retained = allCachedEvents.filter { ev in
            ev.startDate >= rangeEnd || ev.endDate <= rangeStart
        }
        allCachedEvents = retained + newEvents

        // Extend cached range
        if let cs = cachedStart, let ce = cachedEnd {
            cachedStart = min(cs, rangeStart)
            cachedEnd   = max(ce, rangeEnd)
        } else {
            cachedStart = rangeStart
            cachedEnd   = rangeEnd
        }
    }

    // MARK: – Writable calendars

    func loadWritableCalendars(api: CalendarrAPI) async {
        async let localCals  = (try? await api.getLocalCalendars()) ?? []
        async let caldavAccs = (try? await api.getCalDAVAccounts()) ?? []
        async let googleCals = (try? await api.getGoogleCalendars()) ?? []
        async let haCals     = (try? await api.getHACalendars()) ?? []

        var result: [WritableCalendar] = []
        for cal in await localCals {
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
