import EventKit
import Foundation
import UIKit

/// The calendars iOS itself manages — iCloud, Outlook/Exchange, Google — read
/// and written through EventKit.
///
/// These never reach the Calendarr server: they live on the device, so they
/// show up in this app only. That is the point. Publishing an Outlook calendar
/// is often blocked by company policy, and the phone already has the account.
///
/// Off until the user turns it on in Accounts, so nobody is asked for calendar
/// access they did not ask for.
@MainActor
final class DeviceCalendarService {
    static let shared = DeviceCalendarService()

    /// `CalEvent.source` for device events; also the prefix of their calendar key.
    static let source = "device"
    static let enabledKey = "deviceCalendarsEnabled"

    private let store = EKEventStore()

    private init() {}

    // MARK: - Access

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// True once the user granted access. Write access needs full access —
    /// `.writeOnly` would let us add events but never show them.
    @discardableResult
    func requestAccess() async -> Bool {
        if hasAccess { return true }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        if granted { Self.generation += 1 }
        return granted
    }

    /// Both switches on: the user enabled the feature *and* granted access.
    var isActive: Bool { Self.isEnabled && hasAccess }

    /// Bumped when access is granted. The event cache was filled before the
    /// device calendars existed, so the store treats a changed generation as a
    /// cache miss — otherwise the new calendars would only turn up after a
    /// restart. Cheaper than threading the store through the accounts screen.
    private(set) static var generation = 0

    // MARK: - Reading

    /// Every calendar the device knows, writable ones included.
    func calendars() -> [EKCalendar] {
        guard isActive else { return [] }
        return store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func calendar(id: String) -> EKCalendar? {
        guard isActive else { return nil }
        return store.calendar(withIdentifier: id)
    }

    /// Device events in the range, mapped onto the app's own event type so the
    /// existing views, filters and ordering treat them like any other source.
    func events(start: Date, end: Date) -> [CalEvent] {
        guard isActive else { return [] }
        let cals = store.calendars(for: .event)
        guard !cals.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        return store.events(matching: predicate).compactMap(Self.map)
    }

    private static func map(_ ek: EKEvent) -> CalEvent? {
        // A recurring event's occurrences share one eventIdentifier, so append
        // the start date to keep SwiftUI's per-event identity unique.
        guard let ident = ek.eventIdentifier,
              let start = ek.startDate, let end = ek.endDate else { return nil }
        let cal = ek.calendar
        return CalEvent(
            id: "\(ident)|\(Int(start.timeIntervalSince1970))",
            url: "",
            title: ek.title ?? "",
            startDate: start,
            endDate: end,
            isAllDay: ek.isAllDay,
            location: ek.location ?? "",
            notes: ek.notes ?? "",
            color: hex(cal?.cgColor),
            calendarId: cal?.calendarIdentifier ?? "",
            calendarName: cal?.title ?? "",
            calendarColor: hex(cal?.cgColor) ?? "#8E8E93",
            source: source,
            readOnly: !(cal?.allowsContentModifications ?? false)
        )
    }

    /// The EKEvent behind one of our composite ids (see `map`).
    private func ekEvent(for calEventId: String) -> EKEvent? {
        let ident = calEventId.split(separator: "|").first.map(String.init) ?? calEventId
        return store.event(withIdentifier: ident)
    }

    // MARK: - Writing

    func create(calendarId: String, title: String, start: Date, end: Date,
                isAllDay: Bool, location: String, notes: String) throws {
        guard let cal = store.calendar(withIdentifier: calendarId) else {
            throw DeviceCalendarError.calendarGone
        }
        let ev = EKEvent(eventStore: store)
        ev.calendar = cal
        apply(ev, title: title, start: start, end: end,
              isAllDay: isAllDay, location: location, notes: notes)
        try store.save(ev, span: .thisEvent, commit: true)
    }

    func update(eventId: String, title: String, start: Date, end: Date,
                isAllDay: Bool, location: String, notes: String) throws {
        guard let ev = ekEvent(for: eventId) else { throw DeviceCalendarError.eventGone }
        apply(ev, title: title, start: start, end: end,
              isAllDay: isAllDay, location: location, notes: notes)
        // .thisEvent on a recurring series edits only the occurrence the user
        // opened, which is what tapping a single day implies.
        try store.save(ev, span: .thisEvent, commit: true)
    }

    func delete(eventId: String) throws {
        guard let ev = ekEvent(for: eventId) else { throw DeviceCalendarError.eventGone }
        try store.remove(ev, span: .thisEvent, commit: true)
    }

    private func apply(_ ev: EKEvent, title: String, start: Date, end: Date,
                       isAllDay: Bool, location: String, notes: String) {
        ev.title = title
        ev.startDate = start
        ev.endDate = end
        ev.isAllDay = isAllDay
        ev.location = location.isEmpty ? nil : location
        ev.notes = notes.isEmpty ? nil : notes
    }

    // MARK: - Helpers

    private static func hex(_ color: CGColor?) -> String? {
        guard let color, let c = UIColor(cgColor: color).cgColor.components, c.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((c[0] * 255).rounded()),
                      Int((c[1] * 255).rounded()),
                      Int((c[2] * 255).rounded()))
    }
}

enum DeviceCalendarError: LocalizedError {
    case calendarGone
    case eventGone

    var errorDescription: String? {
        switch self {
        case .calendarGone: return "Dieser Gerätekalender existiert nicht mehr."
        case .eventGone:    return "Dieser Termin existiert auf dem Gerät nicht mehr."
        }
    }
}
