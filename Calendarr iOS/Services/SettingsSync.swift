import Foundation

extension Notification.Name {
    /// Posted after a successful pull applied new settings to UserDefaults, so
    /// views holding live state (CalendarHostView → store, widgets) can react.
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

/// Per-setting cross-device synchronisation. The server is the sole authority for
/// WHICH settings sync (its `sync_flags` map); this client keeps a cached copy of
/// that map and only sends/applies the keys whose flag is on. See
/// backend/SETTINGS_SYNC.md for the shared contract.
///
/// - Pull: for every syncable key whose flag is on, the server value wins.
/// - Push (debounced, read-modify-write): start from the server snapshot,
///   overwrite only the on-flagged keys with the local value, PUT.
enum SettingsSync {

    /// Server keys this iOS client can sync, mapped to their UserDefaults key.
    /// Intentionally excluded: `language` (iOS "system" has no server value),
    /// `share_calendar_icon` (no iOS UI), text/line contrast (iOS-only opacity
    /// controls kept device-local), `liquid_glass` (iOS-only).
    static let keyToDefaults: [String: String] = [
        "default_view": "defaultView",
        "week_start_day": "weekStartDay",
        "dim_past_events": "dimPastEvents",
        "hour_height": "hourHeight",
        "default_event_duration_minutes": "defaultEventDurationMinutes",
        "default_reminder_minutes": "defaultReminderMinutes",
        "primary_color": "primaryColor",
        "accent_color": "accentColor",
        "today_color": "todayColor",
        "text_color": "textColor",
        "bg_color": "backgroundColor",
        "line_color": "lineColor",
        "month_divider_color": "monthDividerColor",
        "month_label_color": "monthLabelColor",
        "cache_months": "cacheMonths",
        "month_view_paged": "monthViewPaged",
    ]

    static let syncableKeys: [String] = Array(keyToDefaults.keys)

    /// Fallback flags used only until the first server pull populates the real map
    /// (mirrors the server's DEFAULT_SYNC for the iOS-managed keys).
    static let defaultSync: [String: Bool] = [
        "default_view": true, "week_start_day": true, "dim_past_events": true,
        "hour_height": true, "default_event_duration_minutes": true,
        "default_reminder_minutes": true, "primary_color": true, "accent_color": true,
        "today_color": true, "text_color": true, "bg_color": true, "line_color": true,
        "month_divider_color": true, "month_label_color": true,
        "cache_months": false, "month_view_paged": false,
    ]

    // MARK: – Flag storage (UserDefaults JSON, mirrors the server's resolved map)

    private static let flagsKey = "settingsSyncFlags"

    /// Effective flags: stored overrides on top of the fallback defaults.
    static func flags() -> [String: Bool] {
        var result = defaultSync
        if let data = UserDefaults.standard.data(forKey: flagsKey),
           let stored = try? JSONDecoder().decode([String: Bool].self, from: data) {
            for (k, v) in stored { result[k] = v }
        }
        return result
    }

    static func isSynced(_ key: String) -> Bool { flags()[key] ?? false }

    private static func writeFlags(_ f: [String: Bool]) {
        if let data = try? JSONEncoder().encode(f) {
            UserDefaults.standard.set(data, forKey: flagsKey)
        }
    }

    /// Replace the cached flags with the server's resolved map (known keys only).
    static func storeServerFlags(_ server: [String: Bool]?) {
        guard let server else { return }
        var f = flags()
        for key in syncableKeys { if let v = server[key] { f[key] = v } }
        writeFlags(f)
    }

    /// Toggle one setting's sync flag. Turning it on pushes this device's current
    /// value up (it becomes the shared value); turning off keeps the value local.
    static func setSynced(_ key: String, _ on: Bool, api: CalendarrAPI) {
        var f = flags(); f[key] = on; writeFlags(f)
        push(api: api)
    }

    /// The global "sync everything" switch.
    static func setAllSynced(_ on: Bool, api: CalendarrAPI) {
        var f = flags(); for key in syncableKeys { f[key] = on }; writeFlags(f)
        push(api: api)
    }

    // MARK: – Local ⇄ AppSettings field mapping

    private static func str(_ key: String, _ fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }
    private static func int(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }

    /// Build an AppSettings snapshot from local UserDefaults.
    static func currentSettings() -> AppSettings {
        var s = AppSettings()
        s.primaryColor      = str("primaryColor",      "#4285f4")
        s.accentColor       = str("accentColor",       "#ea4335")
        s.todayColor        = str("todayColor",        "#4285f4")
        s.textColor         = str("textColor",         "#FFFFFF")
        s.backgroundColor   = str("backgroundColor",   "#000000")
        s.lineColor         = str("lineColor",         "#3A3A52")
        s.monthDividerColor = str("monthDividerColor", "#7090c0")
        s.monthLabelColor   = str("monthLabelColor",   "#7090c0")
        s.hourHeight        = int("hourHeight", 60)
        s.defaultView       = str("defaultView",  "month")
        s.weekStartDay      = str("weekStartDay", "monday")
        s.dimPastEvents     = UserDefaults.standard.bool(forKey: "dimPastEvents")
        s.cacheMonths       = int("cacheMonths", 3)
        s.monthViewPaged    = UserDefaults.standard.bool(forKey: "monthViewPaged")
        let rem = int("defaultReminderMinutes", -1)
        s.defaultReminderMinutes = rem < 0 ? nil : rem
        s.defaultEventDurationMinutes = int("defaultEventDurationMinutes", 60)
        return s
    }

    /// Copy one synced field from a source snapshot into a destination snapshot.
    private static func copyField(_ key: String, from src: AppSettings, into dst: inout AppSettings) {
        switch key {
        case "default_view":                    dst.defaultView = src.defaultView
        case "week_start_day":                  dst.weekStartDay = src.weekStartDay
        case "dim_past_events":                 dst.dimPastEvents = src.dimPastEvents
        case "hour_height":                     dst.hourHeight = src.hourHeight
        case "default_event_duration_minutes":  dst.defaultEventDurationMinutes = src.defaultEventDurationMinutes
        case "default_reminder_minutes":        dst.defaultReminderMinutes = src.defaultReminderMinutes
        case "primary_color":                   dst.primaryColor = src.primaryColor
        case "accent_color":                    dst.accentColor = src.accentColor
        case "today_color":                     dst.todayColor = src.todayColor
        case "text_color":                      dst.textColor = src.textColor
        case "bg_color":                        dst.backgroundColor = src.backgroundColor
        case "line_color":                      dst.lineColor = src.lineColor
        case "month_divider_color":             dst.monthDividerColor = src.monthDividerColor
        case "month_label_color":               dst.monthLabelColor = src.monthLabelColor
        case "cache_months":                    dst.cacheMonths = src.cacheMonths
        case "month_view_paged":                dst.monthViewPaged = src.monthViewPaged
        default: break
        }
    }

    /// Write one synced field from a server snapshot into local UserDefaults.
    private static func applyField(_ key: String, from s: AppSettings) {
        let d = UserDefaults.standard
        switch key {
        case "default_view":                    d.set(s.defaultView, forKey: "defaultView")
        case "week_start_day":                  d.set(s.weekStartDay, forKey: "weekStartDay")
        case "dim_past_events":                 d.set(s.dimPastEvents, forKey: "dimPastEvents")
        case "hour_height":                     d.set(s.hourHeight, forKey: "hourHeight")
        case "default_event_duration_minutes":  d.set(s.defaultEventDurationMinutes, forKey: "defaultEventDurationMinutes")
        case "default_reminder_minutes":        d.set(s.defaultReminderMinutes ?? -1, forKey: "defaultReminderMinutes")
        case "primary_color":                   d.set(s.primaryColor, forKey: "primaryColor")
        case "accent_color":                    d.set(s.accentColor, forKey: "accentColor")
        case "today_color":                     d.set(s.todayColor, forKey: "todayColor")
        case "text_color":                      d.set(s.textColor, forKey: "textColor")
        case "bg_color":                        d.set(s.backgroundColor, forKey: "backgroundColor")
        case "line_color":                      d.set(s.lineColor, forKey: "lineColor")
        case "month_divider_color":             d.set(s.monthDividerColor, forKey: "monthDividerColor")
        case "month_label_color":               d.set(s.monthLabelColor, forKey: "monthLabelColor")
        case "cache_months":                    d.set(s.cacheMonths, forKey: "cacheMonths")
        case "month_view_paged":                d.set(s.monthViewPaged, forKey: "monthViewPaged")
        default: break
        }
    }

    // MARK: – Pull

    /// Fetch the server's settings, refresh the flag cache, and apply the value of
    /// every on-flagged key locally (server wins).
    static func pull(api: CalendarrAPI) async {
        guard let server = try? await api.getSettings() else { return }
        storeServerFlags(server.syncFlags)
        let f = flags()
        for key in syncableKeys where f[key] == true {
            applyField(key, from: server)
        }
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

    /// Read-modify-write: start from the server's current settings so unsynced
    /// fields stay intact, overwrite only the on-flagged keys with local values,
    /// and send the current flag map so the account-wide config stays in sync.
    private static func performPush(api: CalendarrAPI) async {
        guard var merged = try? await api.getSettings() else { return }
        let local = currentSettings()
        let f = flags()
        for key in syncableKeys where f[key] == true {
            copyField(key, from: local, into: &merged)
        }
        merged.syncFlags = f
        try? await api.updateSettings(merged)
    }
}
