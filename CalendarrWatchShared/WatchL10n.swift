import Foundation

/// German and English strings for the watch app and its complications.
///
/// A local copy rather than a shared one: `CalendarrCore` is deliberately
/// Foundation-only and holds no presentation concerns, and the iOS `WidgetL10n`
/// belongs to a target the watch cannot link against.
enum WatchL10n {
    static func t(_ key: String, _ stored: String) -> String {
        strings[resolve(stored)]?[key] ?? strings["en"]?[key] ?? key
    }

    static func locale(_ stored: String) -> Locale {
        Locale(identifier: resolve(stored) == "de" ? "de_DE" : "en_US")
    }

    private static func resolve(_ stored: String) -> String {
        if stored == "de" || stored == "en" { return stored }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.lowercased().hasPrefix("de") ? "de" : "en"
    }

    private static let strings: [String: [String: String]] = [
        "de": [
            "watch.title":          "Calendarr",
            "watch.calendars":      "Kalender",
            "watch.allday":         "Ganztägig",
            "watch.no_events":      "Keine Termine",
            "watch.today":          "Heute",
            "watch.tomorrow":       "Morgen",
            "watch.events_today":   "Termine",
            "watch.sign_in":        "Auf dem iPhone anmelden",
            "watch.update":         "Watch-App aktualisieren",
            "watch.waiting":        "Warte auf Daten vom iPhone",
            "watch.unreadable":     "Daten nicht lesbar",
            "watch.as_of":          "Stand",
            "watch.no_information": "Keine Daten nach",
        ],
        "en": [
            "watch.title":          "Calendarr",
            "watch.calendars":      "Calendars",
            "watch.allday":         "All-day",
            "watch.no_events":      "No events",
            "watch.today":          "Today",
            "watch.tomorrow":       "Tomorrow",
            "watch.events_today":   "events",
            "watch.sign_in":        "Sign in on your iPhone",
            "watch.update":         "Update the watch app",
            "watch.waiting":        "Waiting for data from your iPhone",
            "watch.unreadable":     "Data unreadable",
            "watch.as_of":          "As of",
            "watch.no_information": "No data after",
        ],
    ]
}
