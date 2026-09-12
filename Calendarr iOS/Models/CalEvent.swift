import Foundation
import SwiftUI

/// Creator (or owner, in the group combined view) of an event.
/// `id` is nil for imported events.
struct EventPerson: Hashable {
    let id: Int?
    let displayName: String

    static func from(_ json: Any?) -> EventPerson? {
        guard let obj = json as? [String: Any],
              let name = obj["display_name"] as? String, !name.isEmpty else { return nil }
        let id: Int?
        if let n = obj["id"] as? Int { id = n }
        else if let s = obj["id"] as? String { id = Int(s) }
        else { id = nil }
        return EventPerson(id: id, displayName: name)
    }
}

/// A partial-sync failure reported alongside an otherwise-successful
/// `/api/caldav/events` response: one specific calendar didn't sync (e.g.
/// expired credentials) even though it's still enabled. Distinct from a
/// hard fetch failure (`CalendarStore.lastError`) — the request itself
/// succeeded, just not every source within it.
struct SyncError: Hashable {
    let source: String
    let calendarId: String?   // nil on older server responses without calendar_id
    let name: String
    let message: String

    static func from(json: [String: Any]) -> SyncError? {
        guard
            let source  = json["source"]  as? String,
            let name    = json["name"]    as? String,
            let message = json["message"] as? String
        else { return nil }
        let calendarId = json["calendar_id"].map { "\($0)" }
        return SyncError(source: source, calendarId: calendarId, name: name, message: message)
    }
}

struct CalEvent: Identifiable, Hashable {
    let id: String
    let url: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var location: String
    var notes: String
    var color: String?
    var calendarId: String
    var calendarName: String
    var calendarColor: String
    var source: String
    var creator: EventPerson? = nil
    var isPrivate: Bool = false
    // Only set in the group combined view:
    var owner: EventPerson? = nil
    var isGroupEvent: Bool = false
    var displayColor: String? = nil
    // Server-decorated title for the group combined view (group icon / owner
    // prefix); rendered in group mode while `title` stays raw for editing.
    var displayTitle: String? = nil
    // Reminder offsets in minutes-before-start (0 = at start). Local events only.
    var reminders: [Int] = []
    // True for events from a calendar shared with the user read-only.
    var readOnly: Bool = false
    // True for events from a birthday calendar — clients show a cake icon and the
    // server bakes the age into `displayTitle`.
    var isBirthday: Bool = false

    // Group view supplies a server-resolved colour; otherwise per-event then calendar colour.
    var effectiveColor: String { displayColor ?? color ?? calendarColor }

    // Title to render: the server-decorated one (birthday age, group prefix) wins
    // over the raw title, which is kept for editing.
    var renderTitle: String { displayTitle ?? title }

    static func from(json: [String: Any]) -> CalEvent? {
        guard
            let title = json["title"] as? String,
            let startStr = json["start"] as? String,
            let endStr = json["end"] as? String
        else { return nil }

        // id can be String (local UUID) or Int (CalDAV numeric)
        let id: String
        if let s = json["id"] as? String { id = s }
        else if let n = json["id"] as? Int { id = String(n) }
        else { return nil }

        // A date-only string is an all-day event whether or not the flag says
        // so — `parseDate` already treats it that way. Trusting the flag alone
        // is what put "00:00" in front of birthdays everywhere they are shown.
        let startIsDateOnly: Bool = {
            let clean = startStr.trimmingCharacters(in: .whitespaces)
            return clean.count == 10 && !clean.contains("T")
        }()
        let declaredAllDay = (json["allDay"] as? Bool ?? false) || startIsDateOnly
        let startDate = parseDate(startStr, allDay: declaredAllDay)
        let endDate = parseDate(endStr, allDay: declaredAllDay)
        guard let s = startDate, let e = endDate else { return nil }

        // An event running midnight to midnight across one or more whole days
        // is all-day whatever the payload claims. Without this, a six-day
        // holiday sent without the flag renders as "00:00 – 00:00" — a time
        // range that is technically true and tells the reader nothing.
        let cal = Calendar.current
        // Requiring the end to land exactly on midnight too was too strict: a
        // holiday stored as 16th 00:00 to 21st 01:00 slipped through and showed
        // up as a one-hour slot. Starting on a day boundary and running into a
        // later day is enough.
        let spansWholeDays = e > s
            && cal.startOfDay(for: s) == s
            && cal.startOfDay(for: e) > cal.startOfDay(for: s)
        let isAllDay = declaredAllDay || spansWholeDays

        return CalEvent(
            id: id,
            url: json["url"] as? String ?? "",
            title: title,
            startDate: s,
            endDate: e,
            isAllDay: isAllDay,
            location: json["location"] as? String ?? "",
            notes: json["description"] as? String ?? "",
            color: (json["color"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            calendarId: json["calendar_id"].map { "\($0)" } ?? "",
            calendarName: json["calendar_name"] as? String ?? "",
            calendarColor: json["calendarColor"] as? String ?? "#4285f4",
            source: json["source"] as? String ?? "local",
            creator: EventPerson.from(json["creator"]),
            isPrivate: json["private"] as? Bool ?? false,
            owner: EventPerson.from(json["owner"]),
            isGroupEvent: json["is_group_event"] as? Bool ?? false,
            displayColor: (json["display_color"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            displayTitle: (json["display_title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            reminders: (json["reminders"] as? [Int]) ?? (json["reminders"] as? [Any])?.compactMap { ($0 as? Int) ?? Int("\($0)") } ?? [],
            readOnly: json["read_only"] as? Bool ?? false,
            isBirthday: json["is_birthday"] as? Bool ?? false
        )
    }
}

private let isoFull: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let isoBasic: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private let dateOnly: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = .current
    return f
}()

// Handles all date formats the backend may produce:
// "2026-05-17"  "2026-05-17T10:00:00Z"  "2026-05-17T10:00:00+02:00"
// "2026-05-17T10:00:00.000Z"  "2026-05-17T10:00:00"  "2026-05-17 10:00:00+00:00"
private let noTZFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    f.timeZone = TimeZone(abbreviation: "UTC")
    return f
}()

private let spaceSepFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
    return f
}()

func parseDate(_ s: String, allDay: Bool) -> Date? {
    let clean = s.trimmingCharacters(in: .whitespaces)
    if allDay || (clean.count == 10 && !clean.contains("T")) {
        return dateOnly.date(from: String(clean.prefix(10)))
    }
    // Try each formatter in order of likelihood
    if let d = isoFull.date(from: clean) { return d }
    if let d = isoBasic.date(from: clean) { return d }
    // Python isoformat uses space separator: "2026-05-17 10:00:00+00:00"
    if let d = spaceSepFormatter.date(from: clean) { return d }
    // No timezone → treat as UTC
    if let d = noTZFormatter.date(from: String(clean.prefix(19))) { return d }
    // Last resort: just parse the date part
    return dateOnly.date(from: String(clean.prefix(10)))
}

func formatISO(_ date: Date, allDay: Bool) -> String {
    if allDay {
        return dateOnly.string(from: date)
    }
    return isoBasic.string(from: date)
}

/// Inline label for an event in a calendar grid: a leading birthday (cake) icon
/// when the event is a birthday, followed by the render title (which carries the
/// server-computed age). Icon and text inherit the surrounding font/colour, so
/// the label matches whatever bar it's dropped into.
struct EventLabel: View {
    let event: CalEvent
    var body: some View {
        if event.isBirthday {
            HStack(spacing: 3) {
                Image(systemName: "birthday.cake.fill").imageScale(.small)
                Text(event.renderTitle)
            }
        } else {
            Text(event.renderTitle)
        }
    }
}
