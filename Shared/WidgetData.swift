import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App-Group identifier shared between the main app and the widget extension.
/// IMPORTANT: This must match the App Group capability in BOTH targets
/// and the App Group ID registered in the Apple Developer Portal.
let widgetAppGroupID = "group.com.scarriffleservices.calendarr"

/// Lightweight calendar descriptor stored alongside the event cache so the
/// widget configuration intent can offer calendar options without a network call.
struct WidgetCalendar: Codable, Identifiable, Hashable {
    let id: String       // calendarKey ("source-calendarId")
    let name: String
    let colorHex: String
}

/// Lightweight event representation that lives inside the widget cache.
/// We strip everything the widget doesn't need (notes, calendar IDs, URLs).
struct WidgetEvent: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let colorHex: String
    let location: String
    let calendarKey: String   // used for per-calendar filtering in widget config

    init(id: String, title: String, start: Date, end: Date,
         isAllDay: Bool, colorHex: String, location: String, calendarKey: String) {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.colorHex = colorHex
        self.location = location; self.calendarKey = calendarKey
    }

    // Backward-compatible decoder: old caches have no calendarKey field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(String.self, forKey: .id)
        title      = try c.decode(String.self, forKey: .title)
        start      = try c.decode(Date.self,   forKey: .start)
        end        = try c.decode(Date.self,   forKey: .end)
        isAllDay   = try c.decode(Bool.self,   forKey: .isAllDay)
        colorHex   = try c.decode(String.self, forKey: .colorHex)
        location   = try c.decode(String.self, forKey: .location)
        calendarKey = try c.decodeIfPresent(String.self, forKey: .calendarKey) ?? ""
    }
}

/// Snapshot blob the app writes to the App-Group container and the widget reads.
struct WidgetSnapshot: Codable {
    let writtenAt: Date
    let events: [WidgetEvent]
    /// Mirrors the user's chosen visual settings so the widget looks the same
    /// as the app even when its own AppStorage in the extension is empty.
    let todayColorHex: String
    let textColorHex: String
    let backgroundColorHex: String
    let lineColorHex: String
    let primaryColorHex: String
    let accentColorHex: String
    let language: String

    init(writtenAt: Date,
         events: [WidgetEvent],
         todayColorHex: String,
         textColorHex: String,
         backgroundColorHex: String,
         lineColorHex: String,
         primaryColorHex: String,
         accentColorHex: String,
         language: String) {
        self.writtenAt = writtenAt
        self.events = events
        self.todayColorHex = todayColorHex
        self.textColorHex = textColorHex
        self.backgroundColorHex = backgroundColorHex
        self.lineColorHex = lineColorHex
        self.primaryColorHex = primaryColorHex
        self.accentColorHex = accentColorHex
        self.language = language
    }

    /// Custom decoder so older caches without the new colour fields still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        writtenAt          = try c.decode(Date.self,           forKey: .writtenAt)
        events             = try c.decode([WidgetEvent].self,  forKey: .events)
        todayColorHex      = try c.decode(String.self,         forKey: .todayColorHex)
        textColorHex       = try c.decode(String.self,         forKey: .textColorHex)
        backgroundColorHex = try c.decode(String.self,         forKey: .backgroundColorHex)
        lineColorHex       = try c.decode(String.self,         forKey: .lineColorHex)
        language           = try c.decode(String.self,         forKey: .language)
        primaryColorHex    = try c.decodeIfPresent(String.self, forKey: .primaryColorHex) ?? "#4285f4"
        accentColorHex     = try c.decodeIfPresent(String.self, forKey: .accentColorHex)  ?? "#ea4335"
    }

    private enum CodingKeys: String, CodingKey {
        case writtenAt, events, todayColorHex, textColorHex, backgroundColorHex
        case lineColorHex, primaryColorHex, accentColorHex, language
    }
}

enum WidgetStore {
    private static let cacheFilename     = "widget-cache.json"
    private static let calendarsFilename = "widget-calendars.json"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: widgetAppGroupID)
    }

    private static var cacheURL: URL? {
        containerURL?.appendingPathComponent(cacheFilename)
    }

    private static var calendarsURL: URL? {
        containerURL?.appendingPathComponent(calendarsFilename)
    }

    /// Called by the app whenever the event cache changes.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = cacheURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Called by the widget timeline provider to load the latest snapshot.
    static func read() -> WidgetSnapshot? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Write the list of available calendars so the widget intent can offer
    /// calendar options for filtering without a network call.
    static func writeCalendars(_ calendars: [WidgetCalendar]) {
        guard let url = calendarsURL else { return }
        if let data = try? JSONEncoder().encode(calendars) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Read the calendar list written by the main app.
    static func readCalendars() -> [WidgetCalendar] {
        guard let url = calendarsURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WidgetCalendar].self, from: data)) ?? []
    }

    /// Rewrite the existing snapshot with the latest colour / language values
    /// from UserDefaults. Used when the user tweaks an appearance setting and
    /// we want the widgets to refresh immediately, without needing a new event
    /// sync. No-op if there's no cached snapshot yet.
    static func republishAppearanceOnly() {
        guard let existing = read() else { return }
        let defaults = UserDefaults.standard
        let updated = WidgetSnapshot(
            writtenAt: Date(),
            events: existing.events,
            todayColorHex:      defaults.string(forKey: "todayColor")       ?? existing.todayColorHex,
            textColorHex:       defaults.string(forKey: "textColor")        ?? existing.textColorHex,
            backgroundColorHex: defaults.string(forKey: "backgroundColor")  ?? existing.backgroundColorHex,
            lineColorHex:       defaults.string(forKey: "lineColor")        ?? existing.lineColorHex,
            primaryColorHex:    defaults.string(forKey: "primaryColor")     ?? existing.primaryColorHex,
            accentColorHex:     defaults.string(forKey: "accentColor")      ?? existing.accentColorHex,
            language:           defaults.string(forKey: "appLanguage")      ?? existing.language
        )
        write(updated)
        WidgetTimelineNotifier.reload()
    }
}

enum WidgetTimelineNotifier {
    static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
