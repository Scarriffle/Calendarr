import Foundation
import CalendarrCore

/// Which calendars this watch hides, on top of what the phone already filtered.
///
/// The snapshot arrives with hidden and banished calendars already removed, so
/// this narrows further and can never contradict the phone. It lives in the App
/// Group so one toggle in the app affects every complication at once.
enum WatchFilterStore {
    private static let key = "watchHiddenCalendarKeys"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: CalendarrAppGroup.current)
    }

    static func load() -> Set<String> {
        Set(defaults?.stringArray(forKey: key) ?? [])
    }

    static func save(_ keys: Set<String>) {
        defaults?.set(keys.sorted(), forKey: key)
    }
}
