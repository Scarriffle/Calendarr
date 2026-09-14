import Foundation
@_spi(Writer) import CalendarrCore
#if canImport(WidgetKit)
import WidgetKit
#endif

// The snapshot types and the App Group plumbing now live in CalendarrCore, so
// that a second app from this team reads the exact same format instead of
// reimplementing it and drifting.
//
// These aliases keep the ~70 existing call sites in the app and the widget
// compiling unchanged. They are a migration convenience, not a design: new code
// should use the CalendarrCore names directly.
typealias WidgetEvent = SnapshotEvent
typealias WidgetCalendar = SnapshotCalendar
typealias WidgetSnapshot = CalendarrSnapshot

/// The App Group identifier for this platform. See `CalendarrAppGroup`.
let widgetAppGroupID = CalendarrAppGroup.current

extension CalendarrSnapshot {
    // The six colours are stored flat on the wire for backwards compatibility
    // but exposed as `theme` in the package. These keep the widget views, which
    // read them individually, from having to change.
    var todayColorHex: String      { theme.today }
    var textColorHex: String       { theme.text }
    var backgroundColorHex: String { theme.background }
    var lineColorHex: String       { theme.line }
    var primaryColorHex: String    { theme.primary }
    var accentColorHex: String     { theme.accent }
}

/// Thin facade over `CalendarrCore.SnapshotStore`, preserving the static API the
/// app and widget already use. Errors are swallowed here exactly as before —
/// a failed widget cache write must never interrupt the user — but the store now
/// reports *why* a read failed, which is what `read()` discards and callers that
/// need the distinction should use `SnapshotStore` directly for.
enum WidgetStore {
    private static let store = SnapshotStore()
    private static let sessions = SharedSessionStore()

    /// Version of the app writing the cache, for diagnostics in the consumer.
    private static var writerVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static func write(_ snapshot: WidgetSnapshot) {
        try? store.write(snapshot)
    }

    static func read() -> WidgetSnapshot? {
        store.read().snapshot
    }

    static func writeCalendars(_ calendars: [WidgetCalendar]) {
        try? store.writeCalendars(calendars)
    }

    static func readCalendars() -> [WidgetCalendar] {
        store.readCalendars()
    }

    /// Record which server we are pointed at and whether anyone is signed in, so
    /// a reading app can tell "signed out" from "never ran" without reaching into
    /// this app's UserDefaults, which lives in another sandbox.
    static func writeSession(baseURL: String, username: String, isLoggedIn: Bool) {
        try? sessions.write(SharedSession(baseURL: baseURL,
                                          username: username,
                                          isLoggedIn: isLoggedIn,
                                          writtenAt: Date()))
    }

    /// Forget the session entirely. Used on server reset, where the app returns
    /// to unconfigured and there is no longer a server worth naming.
    static func clearSession() {
        sessions.clear()
    }

    /// Drop the cached calendar. Called on sign-out and server reset: the
    /// container outlives the session, so without this every reader keeps
    /// rendering the previous user's events.
    static func clear() {
        store.clear()
        WidgetTimelineNotifier.reload()
    }

    /// Rewrite the existing snapshot with the latest colour / language values so
    /// widgets pick up an appearance change immediately, without waiting for the
    /// next event sync. No-op when nothing is cached yet.
    static func republishAppearanceOnly() {
        guard let existing = read() else { return }
        let defaults = UserDefaults.standard
        let updated = WidgetSnapshot(
            writtenAt: Date(),
            coverageStart: existing.coverageStart,
            coverageEnd: existing.coverageEnd,
            isLoggedIn: existing.isLoggedIn,
            writerVersion: writerVersion,
            events: existing.events,
            theme: SnapshotTheme(
                today:      defaults.string(forKey: "todayColor")      ?? existing.theme.today,
                text:       defaults.string(forKey: "textColor")       ?? existing.theme.text,
                background: defaults.string(forKey: "backgroundColor") ?? existing.theme.background,
                line:       defaults.string(forKey: "lineColor")       ?? existing.theme.line,
                primary:    defaults.string(forKey: "primaryColor")    ?? existing.theme.primary,
                accent:     defaults.string(forKey: "accentColor")     ?? existing.theme.accent),
            language: defaults.string(forKey: "appLanguage") ?? existing.language)
        write(updated)
        WidgetTimelineNotifier.reload()
    }

    /// Build a snapshot from the app's current state. Kept here so the coverage
    /// window and the writer version are stamped in exactly one place.
    static func makeSnapshot(events: [WidgetEvent],
                             coverageStart: Date,
                             coverageEnd: Date) -> WidgetSnapshot {
        let defaults = UserDefaults.standard
        return WidgetSnapshot(
            writtenAt: Date(),
            coverageStart: coverageStart,
            coverageEnd: coverageEnd,
            isLoggedIn: true,          // only ever written while signed in
            writerVersion: writerVersion,
            events: events,
            theme: SnapshotTheme(
                today:      defaults.string(forKey: "todayColor")      ?? "#4285f4",
                text:       defaults.string(forKey: "textColor")       ?? "#FFFFFF",
                background: defaults.string(forKey: "backgroundColor") ?? "#000000",
                line:       defaults.string(forKey: "lineColor")       ?? "#3A3A52",
                primary:    defaults.string(forKey: "primaryColor")    ?? "#4285f4",
                accent:     defaults.string(forKey: "accentColor")     ?? "#ea4335"),
            language: defaults.string(forKey: "appLanguage") ?? "system")
    }
}

enum WidgetTimelineNotifier {
    static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
