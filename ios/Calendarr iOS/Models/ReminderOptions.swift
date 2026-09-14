import Foundation

/// Reminder offset options (minutes before an event's start; 0 = at start) and
/// their localized labels. Shared by the event editor, the settings default
/// picker, and the notification scheduler so the choices stay consistent.
enum ReminderOptions {
    /// Selectable offsets in minutes-before-start.
    static let all: [Int] = [0, 5, 15, 30, 60, 1440, 10080]

    /// Quick presets shown in the picker; everything else is entered as a
    /// custom number + unit. Default for a freshly-switched custom row.
    static let presets: [Int] = [0, 30, 1440]   // at start, 30 min, 1 day
    static let customDefault = 120              // 2 hours (deliberately not a preset)

    /// Time units for the custom picker (value × mult = minutes-before-start).
    enum Unit: Int, CaseIterable, Identifiable {
        case minutes, hours, days, weeks
        var id: Int { rawValue }
        var mult: Int {
            switch self {
            case .minutes: return 1
            case .hours:   return 60
            case .days:    return 1440
            case .weeks:   return 10080
            }
        }
    }

    /// Split a minutes value into the largest exact {value, unit} for the custom picker.
    static func split(_ minutes: Int) -> (value: Int, unit: Unit) {
        for u in Unit.allCases.reversed() where minutes > 0 && minutes % u.mult == 0 {
            return (minutes / u.mult, u)
        }
        return (max(1, minutes), .minutes)
    }

    static func unitLabel(_ u: Unit, _ l: String) -> String {
        let en = isEnglish(l)
        switch u {
        case .minutes: return en ? "minutes" : "Minuten"
        case .hours:   return en ? "hours"   : "Stunden"
        case .days:    return en ? "days"    : "Tage"
        case .weeks:   return en ? "weeks"   : "Wochen"
        }
    }
    /// Human label for a duration in minutes (no "before" suffix), e.g. "1 h", "30 min".
    static func durationLabel(_ minutes: Int, _ l: String) -> String {
        let en = isEnglish(l)
        if minutes % 60 == 0 {
            let h = minutes / 60
            return en ? "\(h) h" : "\(h) Std."
        }
        if minutes > 60 {
            let h = minutes / 60, m = minutes % 60
            return "\(h):\(String(format: "%02d", m)) h"
        }
        return en ? "\(minutes) min" : "\(minutes) Min."
    }
    static func customLabel(_ l: String) -> String { isEnglish(l) ? "Custom…" : "Benutzerdefiniert…" }
    static func beforeLabel(_ l: String) -> String { isEnglish(l) ? "before" : "vorher" }
    static func disabledNote(_ l: String) -> String {
        isEnglish(l)
            ? "Reminders are disabled for this calendar – they will not fire."
            : "Für diesen Kalender sind Benachrichtigungen deaktiviert – Erinnerungen werden nicht ausgeführt."
    }

    private static func isEnglish(_ appLang: String) -> Bool {
        if appLang == "en" { return true }
        if appLang == "de" { return false }
        return (Locale.current.language.languageCode?.identifier ?? "de").hasPrefix("en")
    }

    static func label(_ minutes: Int, _ appLang: String) -> String {
        let en = isEnglish(appLang)
        if minutes <= 0 { return en ? "At start time" : "Zur Startzeit" }
        if minutes < 60 {
            return en ? "\(minutes) minutes before" : "\(minutes) Minuten vorher"
        }
        if minutes < 1440 {
            let h = minutes / 60
            if en { return h == 1 ? "1 hour before" : "\(h) hours before" }
            return h == 1 ? "1 Stunde vorher" : "\(h) Stunden vorher"
        }
        if minutes < 10080 {
            let d = minutes / 1440
            if en { return d == 1 ? "1 day before" : "\(d) days before" }
            return d == 1 ? "1 Tag vorher" : "\(d) Tage vorher"
        }
        let w = minutes / 10080
        if en { return w == 1 ? "1 week before" : "\(w) weeks before" }
        return w == 1 ? "1 Woche vorher" : "\(w) Wochen vorher"
    }

    static func sectionTitle(_ l: String) -> String { isEnglish(l) ? "Reminders" : "Benachrichtigungen" }
    static func addLabel(_ l: String) -> String { isEnglish(l) ? "Add reminder" : "Benachrichtigung hinzufügen" }
    static func off(_ l: String) -> String { isEnglish(l) ? "Off" : "Aus" }
    static func defaultTitle(_ l: String) -> String { isEnglish(l) ? "Default reminder" : "Standardbenachrichtigung" }
    static func defaultFooter(_ l: String) -> String {
        isEnglish(l)
            ? "Applies to all events unless an event has its own reminders."
            : "Gilt für alle Termine, sofern ein Termin keine eigenen Benachrichtigungen hat."
    }
}
