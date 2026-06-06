import Foundation

/// Reminder offset options (minutes before an event's start; 0 = at start) and
/// their localized labels. Shared by the event editor, the settings default
/// picker, and the notification scheduler so the choices stay consistent.
enum ReminderOptions {
    /// Selectable offsets in minutes-before-start.
    static let all: [Int] = [0, 5, 10, 15, 30, 60, 120, 1440, 2880]

    private static func isEnglish(_ appLang: String) -> Bool {
        if appLang == "en" { return true }
        if appLang == "de" { return false }
        return (Locale.current.language.languageCode?.identifier ?? "de").hasPrefix("en")
    }

    static func label(_ minutes: Int, _ appLang: String) -> String {
        let en = isEnglish(appLang)
        if minutes <= 0 { return en ? "At start time" : "Zur Startzeit" }
        if minutes < 60 { return en ? "\(minutes) min before" : "\(minutes) Min. vorher" }
        if minutes < 1440 {
            let h = minutes / 60
            return en ? "\(h) h before" : "\(h) Std. vorher"
        }
        let d = minutes / 1440
        return en ? "\(d) day\(d == 1 ? "" : "s") before" : "\(d) Tag\(d == 1 ? "" : "e") vorher"
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
