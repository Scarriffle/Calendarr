import SwiftUI

// Local copy of the Color(hex:) initializer, since the widget extension
// is a separate target and cannot import the main app's Color extension.
extension Color {
    init(widgetHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

enum WidgetL10n {
    static func t(_ key: String, _ stored: String) -> String {
        let lang: String
        if stored == "de" || stored == "en" { lang = stored }
        else {
            let pref = Locale.preferredLanguages.first ?? "en"
            lang = pref.lowercased().hasPrefix("de") ? "de" : "en"
        }
        return strings[lang]?[key] ?? strings["en"]?[key] ?? key
    }

    static func locale(_ stored: String) -> Locale {
        let lang: String
        if stored == "de" || stored == "en" { lang = stored }
        else {
            let pref = Locale.preferredLanguages.first ?? "en"
            lang = pref.lowercased().hasPrefix("de") ? "de" : "en"
        }
        return Locale(identifier: lang)
    }

    private static let strings: [String: [String: String]] = [
        "de": [
            "widget.today":         "Heute",
            "widget.tomorrow":      "Morgen",
            "widget.no_events":     "Keine Termine",
            "widget.allday":        "Ganztägig",
            "widget.more":          "+%d weitere",
            "widget.upcoming":      "Nächste 5 Tage",
            "widget.no_data":       "Keine Daten – App einmal öffnen",
            "widget.display.today_title":       "Heute",
            "widget.display.today_desc":        "Heutige Termine auf einen Blick.",
            "widget.display.days_title":        "Heute & Morgen",
            "widget.display.days_desc":         "Termine der nächsten zwei Tage.",
            "widget.display.upcoming_title":    "Nächste 5 Tage",
            "widget.display.upcoming_desc":     "Termine der nächsten 5 Tage.",
            "widget.display.thisweek_title":    "Diese Woche",
            "widget.display.thisweek_desc":     "Wochenraster mit Terminen.",
            "widget.display.twoweeks_title":    "Zwei Wochen",
            "widget.display.twoweeks_desc":     "Zwei-Wochen-Raster mit Terminen.",
            "widget.display.threedays_title":   "Drei Tage",
            "widget.display.threedays_desc":    "Drei-Tages-Ansicht mit Terminen.",
            "widget.display.upnext_title":      "Up Next + Kalender",
            "widget.display.upnext_desc":       "Nächste Termine mit Monatsübersicht.",
            "widget.display.calday_title":      "Tag & Termine",
            "widget.display.calday_desc":       "Datum, Wochenübersicht und nächste Termine.",
            "widget.display.lockscreen_title":  "Datum",
            "widget.display.lockscreen_desc":   "Aktuelles Datum und nächster Termin.",
            "widget.display.twomonth_title":    "Zwei Monate",
            "widget.display.twomonth_desc":     "Aktueller und nächster Monat auf einen Blick.",
            "widget.display.nownext_title":     "Jetzt & Nächstes",
            "widget.display.nownext_desc":      "Aktueller Termin und nächste Ereignisse.",
            "widget.cw":                        "KW",
            "widget.running":                   "Läuft",
            "widget.events_count":              "Termine",
            "widget.display.lockscreen_count_title":    "Termine heute",
            "widget.display.lockscreen_count_desc":     "Anzahl und Liste heutiger Termine.",
            "widget.display.lockscreen_countdown_title": "Countdown",
            "widget.display.lockscreen_countdown_desc":  "Zeit bis zum nächsten Termin."
        ],
        "en": [
            "widget.today":         "Today",
            "widget.tomorrow":      "Tomorrow",
            "widget.no_events":     "No events",
            "widget.allday":        "All-day",
            "widget.more":          "+%d more",
            "widget.upcoming":      "Next 5 days",
            "widget.no_data":       "No data – open the app once",
            "widget.display.today_title":       "Today",
            "widget.display.today_desc":        "Today's events at a glance.",
            "widget.display.days_title":        "Today & tomorrow",
            "widget.display.days_desc":         "Events for the next two days.",
            "widget.display.upcoming_title":    "Next 5 days",
            "widget.display.upcoming_desc":     "Events for the next 5 days.",
            "widget.display.thisweek_title":    "This Week",
            "widget.display.thisweek_desc":     "Week grid with events.",
            "widget.display.twoweeks_title":    "Two Weeks",
            "widget.display.twoweeks_desc":     "Two-week grid with events.",
            "widget.display.threedays_title":   "Three Days",
            "widget.display.threedays_desc":    "Three-day view with events.",
            "widget.display.upnext_title":      "Up Next + Calendar",
            "widget.display.upnext_desc":       "Next events with month overview.",
            "widget.display.calday_title":      "Day & Events",
            "widget.display.calday_desc":       "Date, week overview and upcoming events.",
            "widget.display.lockscreen_title":  "Date",
            "widget.display.lockscreen_desc":   "Current date and next event.",
            "widget.display.twomonth_title":    "Two Months",
            "widget.display.twomonth_desc":     "Current and next month at a glance.",
            "widget.display.nownext_title":     "Now & Next",
            "widget.display.nownext_desc":      "Current event and upcoming events.",
            "widget.cw":                        "W",
            "widget.running":                   "Running",
            "widget.events_count":              "Events",
            "widget.display.lockscreen_count_title":    "Today's Events",
            "widget.display.lockscreen_count_desc":     "Count and list of today's events.",
            "widget.display.lockscreen_countdown_title": "Countdown",
            "widget.display.lockscreen_countdown_desc":  "Time until your next event."
        ]
    ]
}
