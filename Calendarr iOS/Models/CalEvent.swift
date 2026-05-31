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

    // Group view supplies a server-resolved colour; otherwise per-event then calendar colour.
    var effectiveColor: String { displayColor ?? color ?? calendarColor }

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

        let isAllDay = json["allDay"] as? Bool ?? false
        let startDate = parseDate(startStr, allDay: isAllDay)
        let endDate = parseDate(endStr, allDay: isAllDay)
        guard let s = startDate, let e = endDate else { return nil }

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
            displayColor: (json["display_color"] as? String).flatMap { $0.isEmpty ? nil : $0 }
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
