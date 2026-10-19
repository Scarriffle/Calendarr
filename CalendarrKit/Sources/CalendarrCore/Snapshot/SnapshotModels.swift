import Foundation

// MARK: - Coverage policy

/// How much of the calendar the writer publishes. Shared so the writer and the
/// v1-file reconstruction below can never disagree about it.
public enum SnapshotCoverage {
    /// Days before today. The current week must stay complete for widgets that
    /// render Monday–today.
    public static let daysBehind = 7
    /// Days after today.
    public static let daysAhead = 42
    /// Hard cap on events written, applied after sorting by start date.
    public static let maxEvents = 500
}

// MARK: - Event

/// One event as published to the shared container.
///
/// Deliberately lossy: notes, URL, source, creator, privacy, read-only status,
/// reminders and recurrence rules are all dropped. This is enough to *display* a
/// calendar and deliberately not enough to edit one or reason about permissions.
public struct SnapshotEvent: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let colorHex: String
    public let location: String
    /// Ties the event to a calendar. See `CalendarKey`.
    public let calendarKey: String

    public init(id: String, title: String, start: Date, end: Date,
                isAllDay: Bool, colorHex: String, location: String, calendarKey: String) {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.colorHex = colorHex
        self.location = location; self.calendarKey = calendarKey
    }

    // Lenient: caches written before calendarKey existed simply lack the field.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self, forKey: .id)
        title       = try c.decode(String.self, forKey: .title)
        start       = try c.decode(Date.self,   forKey: .start)
        end         = try c.decode(Date.self,   forKey: .end)
        isAllDay    = try c.decode(Bool.self,   forKey: .isAllDay)
        colorHex    = try c.decode(String.self, forKey: .colorHex)
        location    = try c.decode(String.self, forKey: .location)
        calendarKey = try c.decodeIfPresent(String.self, forKey: .calendarKey) ?? ""
    }
}

// MARK: - Calendar

/// A calendar available for filtering, published alongside the events so a
/// consumer can build a picker without a network call.
public struct SnapshotCalendar: Codable, Sendable, Identifiable, Hashable {
    /// A `CalendarKey`, matching `SnapshotEvent.calendarKey`.
    public let id: String
    public let name: String
    public let colorHex: String

    public init(id: String, name: String, colorHex: String) {
        self.id = id; self.name = name; self.colorHex = colorHex
    }
}

// MARK: - Theme

/// The colours the app is currently rendering with, so a consumer can match it
/// without reading the app's own preferences.
public struct SnapshotTheme: Sendable, Hashable {
    public let today: String
    public let text: String
    public let background: String
    public let line: String
    public let primary: String
    public let accent: String

    public init(today: String, text: String, background: String,
                line: String, primary: String, accent: String) {
        self.today = today; self.text = text; self.background = background
        self.line = line; self.primary = primary; self.accent = accent
    }
}

// MARK: - Snapshot

/// The published calendar snapshot.
///
/// ## Wire compatibility
///
/// The six colour values are stored **flat** at the top level rather than nested
/// under `theme`, even though `theme` is the nicer thing to read in code. That is
/// deliberate: v1 files carry them flat and a v1 reader requires them flat, so
/// nesting would break older readers on the very first v2 write. Within a major
/// version this format only ever gains optional fields — old readers ignore what
/// they do not know, new readers default what is missing. `theme` is a computed
/// view over the stored values, so callers get the clean shape anyway.
public struct CalendarrSnapshot: Codable, Sendable {
    /// Bump only for a breaking change, and see the rules in the README.
    public static let currentSchema = 2
    /// Files claiming a higher schema are refused rather than mis-decoded.
    public static let maxSupportedSchema = 2

    public let schemaVersion: Int
    public let writtenAt: Date
    /// Start of the published window. Outside `coverageStart..<coverageEnd` the
    /// snapshot carries *no information* — which is not the same as "no events".
    public let coverageStart: Date
    public let coverageEnd: Date
    /// False once the user signs out. Distinguishes "signed out" from "never ran".
    public let isLoggedIn: Bool
    /// CFBundleShortVersionString of whoever wrote the file. Diagnostics only.
    public let writerVersion: String
    public let events: [SnapshotEvent]
    public let language: String

    // Stored flat for wire compatibility — read them via `theme`.
    let todayColorHex: String
    let textColorHex: String
    let backgroundColorHex: String
    let lineColorHex: String
    let primaryColorHex: String
    let accentColorHex: String

    public var theme: SnapshotTheme {
        SnapshotTheme(today: todayColorHex, text: textColorHex,
                      background: backgroundColorHex, line: lineColorHex,
                      primary: primaryColorHex, accent: accentColorHex)
    }

    /// True when `date` falls inside the published window, i.e. when an absence
    /// of events for that date genuinely means "nothing scheduled".
    public func covers(_ date: Date) -> Bool {
        date >= coverageStart && date < coverageEnd
    }

    public init(writtenAt: Date,
                coverageStart: Date,
                coverageEnd: Date,
                isLoggedIn: Bool,
                writerVersion: String,
                events: [SnapshotEvent],
                theme: SnapshotTheme,
                language: String) {
        self.schemaVersion = Self.currentSchema
        self.writtenAt = writtenAt
        self.coverageStart = coverageStart
        self.coverageEnd = coverageEnd
        self.isLoggedIn = isLoggedIn
        self.writerVersion = writerVersion
        self.events = events
        self.language = language
        self.todayColorHex = theme.today
        self.textColorHex = theme.text
        self.backgroundColorHex = theme.background
        self.lineColorHex = theme.line
        self.primaryColorHex = theme.primary
        self.accentColorHex = theme.accent
    }

    /// Lenient decoder. Everything added after v1 is optional here, and a v1
    /// file's coverage window is reconstructed from the policy that produced it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        writtenAt     = try c.decode(Date.self, forKey: .writtenAt)
        events        = try c.decode([SnapshotEvent].self, forKey: .events)
        language      = try c.decode(String.self, forKey: .language)

        todayColorHex      = try c.decode(String.self, forKey: .todayColorHex)
        textColorHex       = try c.decode(String.self, forKey: .textColorHex)
        backgroundColorHex = try c.decode(String.self, forKey: .backgroundColorHex)
        lineColorHex       = try c.decode(String.self, forKey: .lineColorHex)
        primaryColorHex    = try c.decodeIfPresent(String.self, forKey: .primaryColorHex) ?? "#4285f4"
        accentColorHex     = try c.decodeIfPresent(String.self, forKey: .accentColorHex)  ?? "#ea4335"

        isLoggedIn    = try c.decodeIfPresent(Bool.self, forKey: .isLoggedIn) ?? true
        writerVersion = try c.decodeIfPresent(String.self, forKey: .writerVersion) ?? "unknown"

        // v1 had no explicit window; it always wrote the same one, measured from
        // the start of the day it was written.
        let cal = Calendar(identifier: .gregorian)
        let dayStart = cal.startOfDay(for: writtenAt)
        coverageStart = try c.decodeIfPresent(Date.self, forKey: .coverageStart)
            ?? cal.date(byAdding: .day, value: -SnapshotCoverage.daysBehind, to: dayStart) ?? dayStart
        coverageEnd = try c.decodeIfPresent(Date.self, forKey: .coverageEnd)
            ?? cal.date(byAdding: .day, value: SnapshotCoverage.daysAhead, to: dayStart) ?? dayStart
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, writtenAt, coverageStart, coverageEnd, isLoggedIn, writerVersion
        case events, language
        case todayColorHex, textColorHex, backgroundColorHex, lineColorHex
        case primaryColorHex, accentColorHex
    }
}

// MARK: - Read result

/// Why a read produced no usable snapshot. The distinction matters for the UI:
/// "never ran", "signed out" and "genuinely empty" call for different messages.
public enum SnapshotReadResult: Sendable {
    case ok(CalendarrSnapshot)
    /// The user signed out of Calendarr. Show a sign-in prompt, not stale events.
    case loggedOut(writtenAt: Date)
    /// Calendarr has never published on this machine. Ask the user to open it once.
    case neverWritten
    /// Written by a newer Calendarr than this reader understands. Refuse rather
    /// than guess; ask the user to update.
    case incompatible(foundSchema: Int, maxSupported: Int)
    /// Corrupt file, or — much more likely — a misconfigured App Group.
    case unreadable(String)

    public var snapshot: CalendarrSnapshot? {
        if case .ok(let s) = self { return s }
        return nil
    }
}
