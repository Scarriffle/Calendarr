import Foundation

/// Reminder offset options (minutes before an event's start; 0 = at start) and
/// their localized labels. Shared by the event editor, the settings default
/// picker, and the notification scheduler so the choices stay consistent.
enum ReminderOptions {
    /// Selectable offsets in minutes-before-start.
    static let all: [Int] = [0, 5, 15, 30, 60, 1440, 10080]

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
