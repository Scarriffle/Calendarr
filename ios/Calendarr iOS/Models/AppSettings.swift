import SwiftUI

struct AppSettings: Codable {
    var defaultView: String = "month"
    var weekStartDay: String = "monday"
    var primaryColor: String = "#4285f4"
    var accentColor: String = "#ea4335"
    var todayColor: String = "#4285f4"
    var dimPastEvents: Bool = false
    var textContrast: Int = 3
    var lineContrast: Int = 3
    var hourHeight: Int = 60
    var language: String = "de"
    var monthDividerColor: String = "#7090c0"
    var monthLabelColor: String = "#7090c0"
    var textColor: String = "#FFFFFF"
    var backgroundColor: String = "#000000"
    var lineColor: String = "#3A3A52"
    var privateEventVisibility: String = "busy"   // 'hidden' | 'busy'
    var groupVisibleCalendarId: Int? = nil
    var defaultReminderMinutes: Int? = nil         // minutes before start; nil = off
    var defaultEventDurationMinutes: Int = 60      // applied to a new event's end time
    var cacheMonths: Int = 3                       // preloaded month range (device-local by default)
    var monthViewPaged: Bool = false               // month view swipe-paging (device-local by default)
    var syncFlags: [String: Bool]? = nil           // server-resolved per-setting sync flags

    enum CodingKeys: String, CodingKey {
        case defaultView = "default_view"
        case weekStartDay = "week_start_day"
        case primaryColor = "primary_color"
        case accentColor = "accent_color"
        case todayColor = "today_color"
        case dimPastEvents = "dim_past_events"
        case textContrast = "text_contrast"
        case lineContrast = "line_contrast"
        case hourHeight = "hour_height"
        case language
        case monthDividerColor = "month_divider_color"
        case monthLabelColor = "month_label_color"
        case textColor = "text_color"
        case backgroundColor = "bg_color"
        case lineColor = "line_color"
        case privateEventVisibility = "private_event_visibility"
        case groupVisibleCalendarId = "group_visible_calendar_id"
        case defaultReminderMinutes = "default_reminder_minutes"
        case defaultEventDurationMinutes = "default_event_duration_minutes"
        case cacheMonths = "cache_months"
        case monthViewPaged = "month_view_paged"
        case syncFlags = "sync_flags"
    }

    init() {}

    /// Resilient decoding: a server may omit some keys. Using `decodeIfPresent`
    /// with the property defaults means a missing key no longer aborts the whole
    /// decode — otherwise the entire settings sync silently breaks. (Note:
    /// `background_color` was previously mis-mapped; the server column is
    /// `bg_color`, now corrected above.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        defaultView       = try c.decodeIfPresent(String.self, forKey: .defaultView)       ?? d.defaultView
        weekStartDay      = try c.decodeIfPresent(String.self, forKey: .weekStartDay)      ?? d.weekStartDay
        primaryColor      = try c.decodeIfPresent(String.self, forKey: .primaryColor)      ?? d.primaryColor
        accentColor       = try c.decodeIfPresent(String.self, forKey: .accentColor)       ?? d.accentColor
        todayColor        = try c.decodeIfPresent(String.self, forKey: .todayColor)        ?? d.todayColor
        dimPastEvents     = try c.decodeIfPresent(Bool.self,   forKey: .dimPastEvents)     ?? d.dimPastEvents
        textContrast      = try c.decodeIfPresent(Int.self,    forKey: .textContrast)      ?? d.textContrast
        lineContrast      = try c.decodeIfPresent(Int.self,    forKey: .lineContrast)      ?? d.lineContrast
        hourHeight        = try c.decodeIfPresent(Int.self,    forKey: .hourHeight)        ?? d.hourHeight
        language          = try c.decodeIfPresent(String.self, forKey: .language)          ?? d.language
        monthDividerColor = try c.decodeIfPresent(String.self, forKey: .monthDividerColor) ?? d.monthDividerColor
        monthLabelColor   = try c.decodeIfPresent(String.self, forKey: .monthLabelColor)   ?? d.monthLabelColor
        textColor         = try c.decodeIfPresent(String.self, forKey: .textColor)         ?? d.textColor
        backgroundColor   = try c.decodeIfPresent(String.self, forKey: .backgroundColor)   ?? d.backgroundColor
        lineColor         = try c.decodeIfPresent(String.self, forKey: .lineColor)         ?? d.lineColor
        privateEventVisibility = try c.decodeIfPresent(String.self, forKey: .privateEventVisibility) ?? d.privateEventVisibility
        groupVisibleCalendarId = try c.decodeIfPresent(Int.self, forKey: .groupVisibleCalendarId)
        defaultReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultReminderMinutes)
        defaultEventDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultEventDurationMinutes) ?? d.defaultEventDurationMinutes
        cacheMonths = try c.decodeIfPresent(Int.self, forKey: .cacheMonths) ?? d.cacheMonths
        monthViewPaged = try c.decodeIfPresent(Bool.self, forKey: .monthViewPaged) ?? d.monthViewPaged
        syncFlags = try c.decodeIfPresent([String: Bool].self, forKey: .syncFlags)
    }
}

struct CalDAVAccount: Codable, Identifiable {
    let id: Int
    var name: String
    var url: String
    var username: String
    var color: String
    var enabled: Bool
    var calendars: [CalDAVCalendar]?

    enum CodingKeys: String, CodingKey {
        case id, name, url, username, color, enabled, calendars
    }
}

struct CalDAVCalendar: Codable, Identifiable {
    let id: Int
    var name: String
    var color: String?
    var enabled: Bool
    var sidebarHidden: Bool
    var remindersEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, color, enabled
        case sidebarHidden = "sidebar_hidden"
        case remindersEnabled = "reminders_enabled"
    }
}

struct LocalCalendar: Codable, Identifiable {
    let id: Int
    var name: String
    var color: String
    var enabled: Bool
    var owned: Bool = true
    var sharedBy: String? = nil
    var permission: String? = nil
    var group: Bool = false
    var remindersEnabled: Bool = true
    // Birthday calendar: events are all-day yearly; server renders age + cake icon.
    var isBirthday: Bool = false
    // Days before a birthday to remind (0 = on the day). nil = no reminder.
    var birthdayNotifyDaysBefore: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, color, enabled, owned, permission, group
        case sharedBy = "shared_by"
        case remindersEnabled = "reminders_enabled"
        case isBirthday = "is_birthday"
        case birthdayNotifyDaysBefore = "birthday_notify_days_before"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(Int.self, forKey: .id)
        name      = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        color     = try c.decodeIfPresent(String.self, forKey: .color) ?? "#34a853"
        enabled   = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        owned     = try c.decodeIfPresent(Bool.self, forKey: .owned) ?? true
        sharedBy  = try c.decodeIfPresent(String.self, forKey: .sharedBy)
        permission = try c.decodeIfPresent(String.self, forKey: .permission)
        group     = try c.decodeIfPresent(Bool.self, forKey: .group) ?? false
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
        isBirthday = try c.decodeIfPresent(Bool.self, forKey: .isBirthday) ?? false
        birthdayNotifyDaysBefore = try c.decodeIfPresent(Int.self, forKey: .birthdayNotifyDaysBefore)
    }
}

struct ICalSubscription: Codable, Identifiable {
    let id: Int
    var name: String
    var url: String
    var color: String
    var enabled: Bool
    var refreshMinutes: Int
    var lastFetched: String?
    var remindersEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, url, color, enabled
        case refreshMinutes = "refresh_minutes"
        case lastFetched = "last_fetched"
        case remindersEnabled = "reminders_enabled"
    }
}

struct GoogleAccount: Codable, Identifiable {
    let id: Int
    var email: String
    var calendars: [GoogleCalendar]?
}

struct GoogleCalendar: Codable, Identifiable {
    let id: Int
    var name: String
    var color: String?
    var enabled: Bool
    var sidebarHidden: Bool
    var remindersEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, color, enabled
        case sidebarHidden = "sidebar_hidden"
        case remindersEnabled = "reminders_enabled"
    }
}

struct HomeAssistantAccount: Codable, Identifiable {
    let id: Int
    var name: String
    var url: String
    var authMethod: String
    var calendars: [HACalendar]?

    enum CodingKeys: String, CodingKey {
        case id, name, url, calendars
        case authMethod = "auth_method"
    }
}

struct HACalendar: Codable, Identifiable {
    let id: Int
    var name: String
    var entityId: String
    var color: String?
    var enabled: Bool
    var sidebarHidden: Bool
    var remindersEnabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, name, color, enabled
        case entityId = "entity_id"
        case sidebarHidden = "sidebar_hidden"
        case remindersEnabled = "reminders_enabled"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(Int.self, forKey: .id)
        name          = try c.decode(String.self, forKey: .name)
        entityId      = try c.decodeIfPresent(String.self, forKey: .entityId) ?? ""
        color         = try c.decodeIfPresent(String.self, forKey: .color)
        enabled       = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        sidebarHidden = try c.decodeIfPresent(Bool.self, forKey: .sidebarHidden) ?? false
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
    }
}

struct UserProfile: Codable {
    let id: Int
    let username: String
    var displayName: String?
    var email: String?
    let isAdmin: Bool
    let hasAvatar: Bool
    let totpEnabled: Bool
    var directoryHidden: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, username, email
        case displayName = "display_name"
        case isAdmin = "is_admin"
        case hasAvatar = "has_avatar"
        case totpEnabled = "totp_enabled"
        case directoryHidden = "directory_hidden"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        isAdmin = try c.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        hasAvatar = try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        totpEnabled = try c.decodeIfPresent(Bool.self, forKey: .totpEnabled) ?? false
        directoryHidden = try c.decodeIfPresent(Bool.self, forKey: .directoryHidden) ?? false
    }
}

// MARK: - Sharing & groups

struct DirectoryUser: Codable, Identifiable {
    let id: Int
    let displayName: String
    enum CodingKeys: String, CodingKey { case id; case displayName = "display_name" }
}

struct CalendarShare: Codable, Identifiable {
    let userId: Int
    let displayName: String?
    var permission: String
    var id: Int { userId }
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case permission
    }
}

struct GroupMember: Codable, Identifiable {
    let id: Int
    let displayName: String?
    var role: String
    var color: String?
    var sharesCalendar: Bool = true
    enum CodingKeys: String, CodingKey {
        case id, role, color
        case displayName = "display_name"
        case sharesCalendar = "shares_calendar"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "member"
        color = try c.decodeIfPresent(String.self, forKey: .color)
        sharesCalendar = try c.decodeIfPresent(Bool.self, forKey: .sharesCalendar) ?? true
    }
}

struct CalGroup: Codable, Identifiable {
    let id: Int
    var name: String
    var icon: String?
    var role: String?
    var memberCount: Int?
    var groupCalendarId: Int?
    var groupCalendarColor: String?
    var members: [GroupMember]?
    enum CodingKeys: String, CodingKey {
        case id, name, icon, role, members
        case memberCount = "member_count"
        case groupCalendarId = "group_calendar_id"
        case groupCalendarColor = "group_calendar_color"
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
