import Foundation

extension Notification.Name {
    /// Posted after a successful pull applied new settings to UserDefaults, so
    /// views holding live state (CalendarHostView → store, widgets) can react.
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

/// Two-way synchronisation of appearance/behaviour settings between the app and
/// the Calendarr server. The server is treated as the source of truth on pull;
/// local edits are pushed immediately so the server then holds the newest value.
///
/// Two groups:
/// - **optional** (colors, contrasts, hour height) only sync when the user has
///   enabled the `settingsSync` toggle.
/// - **always** (default view, week start, dim past events) sync regardless of
///   the toggle, because they describe how the user expects the calendar to be
///   computed/presented everywhere.
enum SettingsSync {

    // MARK: – UserDefaults keys

    enum Key {
        // optional group
        static let primaryColor      = "primaryColor"
        static let accentColor       = "accentColor"
        static let todayColor        = "todayColor"
        static let textColor         = "textColor"
        static let backgroundColor   = "backgroundColor"
        static let lineColor         = "lineColor"
        static let monthDividerColor = "monthDividerColor"
        static let monthLabelColor   = "monthLabelColor"
        static let textContrast      = "textContrast"
        static let lineContrast      = "lineContrast"
        static let hourHeight        = "hourHeight"
        // always group
        static let defaultView       = "defaultView"
        static let weekStartDay      = "weekStartDay"
        static let dimPastEvents     = "dimPastEvents"
        // master switch
        static let enabled           = "settingsSync"
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: Key.enabled) }

    // MARK: – Defaults (mirror the historical hard-coded values)

    private static func int(_ key: String, _ fallback: Int) -> Int {
        let v = UserDefaults.standard.object(forKey: key) as? Int
        return v ?? fallback
    }
    private static func str(_ key: String, _ fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }

    // MARK: – Build AppSettings from local UserDefaults

    static func currentSettings() -> AppSettings {
        var s = AppSettings()
        s.primaryColor      = str(Key.primaryColor,      "#4285f4")
        s.accentColor       = str(Key.accentColor,       "#ea4335")
        s.todayColor        = str(Key.todayColor,        "#4285f4")
        s.textColor         = str(Key.textColor,         "#FFFFFF")
        s.backgroundColor   = str(Key.backgroundColor,   "#000000")
        s.lineColor         = str(Key.lineColor,         "#3A3A3C")
        s.monthDividerColor = str(Key.monthDividerColor, "#7090c0")
        s.monthLabelColor   = str(Key.monthLabelColor,   "#7090c0")
        s.textContrast      = int(Key.textContrast, 3)
        s.lineContrast      = int(Key.lineContrast, 3)
        s.hourHeight        = int(Key.hourHeight, 60)
        s.defaultView       = str(Key.defaultView,  "month")
        s.weekStartDay      = str(Key.weekStartDay, "monday")
        s.dimPastEvents     = UserDefaults.standard.bool(forKey: Key.dimPastEvents)
        return s
    }

    // MARK: – Apply a server snapshot to local UserDefaults

    /// Always writes the "always" trio. Writes the optional group only when
    /// `includeOptional` is true.
    static func apply(_ s: AppSettings, includeOptional: Bool) {
        let d = UserDefaults.standard
        // always group
        d.set(s.defaultView,   forKey: Key.defaultView)
        d.set(s.weekStartDay,  forKey: Key.weekStartDay)
        d.set(s.dimPastEvents, forKey: Key.dimPastEvents)
        guard includeOptional else { return }
        // NOTE: textColor / backgroundColor / lineColor are intentionally NOT
        // synced – the server has no columns for them (iOS-only). Writing the
        // resilient-decoded defaults here would wipe the user's local choices.
        d.set(s.primaryColor,      forKey: Key.primaryColor)
        d.set(s.accentColor,       forKey: Key.accentColor)
        d.set(s.todayColor,        forKey: Key.todayColor)
        d.set(s.monthDividerColor, forKey: Key.monthDividerColor)
        d.set(s.monthLabelColor,   forKey: Key.monthLabelColor)
        d.set(s.textContrast,      forKey: Key.textContrast)
        d.set(s.lineContrast,      forKey: Key.lineContrast)
        d.set(s.hourHeight,        forKey: Key.hourHeight)
    }

    // MARK: – Pull

    /// Fetch the server's settings and apply them locally (server wins).
    static func pull(api: CalendarrAPI) async {
        guard let server = try? await api.getSettings() else { return }
        apply(server, includeOptional: isEnabled)
        await MainActor.run {
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        }
    }

    // MARK: – Push (debounced)

    private static var pushTask: Task<Void, Never>?

    /// Schedule a debounced push. Repeated calls (e.g. while dragging a colour
    /// slider) collapse into a single network write ~1.2 s after the last edit.
    static func push(api: CalendarrAPI) {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .milliseconds(1200))
            if Task.isCancelled { return }
            await performPush(api: api)
        }
    }

    /// Read-modify-write: start from the server's current settings so that,
    /// when the optional group is NOT being synced, the server's colours stay
    /// intact. Overwrite the trio always, the optional group only if enabled.
    private static func performPush(api: CalendarrAPI) async {
        guard var merged = try? await api.getSettings() else { return }
        let local = currentSettings()
        // always group
        merged.defaultView   = local.defaultView
        merged.weekStartDay  = local.weekStartDay
        merged.dimPastEvents = local.dimPastEvents
        if isEnabled {
            merged.primaryColor      = local.primaryColor
            merged.accentColor       = local.accentColor
            merged.todayColor        = local.todayColor
            merged.textColor         = local.textColor
            merged.backgroundColor   = local.backgroundColor
            merged.lineColor         = local.lineColor
            merged.monthDividerColor = local.monthDividerColor
            merged.monthLabelColor   = local.monthLabelColor
            merged.textContrast      = local.textContrast
            merged.lineContrast      = local.lineContrast
            merged.hourHeight        = local.hourHeight
        }
        try? await api.updateSettings(merged)
    }
}
