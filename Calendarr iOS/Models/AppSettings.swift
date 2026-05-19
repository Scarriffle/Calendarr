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
    var lineColor: String = "#3A3A3C"

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
        case backgroundColor = "background_color"
        case lineColor = "line_color"
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

    enum CodingKeys: String, CodingKey {
        case id, name, color, enabled
        case sidebarHidden = "sidebar_hidden"
    }
}

struct LocalCalendar: Codable, Identifiable {
    let id: Int
    var name: String
    var color: String
    var enabled: Bool
}

struct ICalSubscription: Codable, Identifiable {
    let id: Int
    var name: String
    var url: String
    var color: String
    var enabled: Bool
    var refreshMinutes: Int
    var lastFetched: String?

    enum CodingKeys: String, CodingKey {
        case id, name, url, color, enabled
        case refreshMinutes = "refresh_minutes"
        case lastFetched = "last_fetched"
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

    enum CodingKeys: String, CodingKey {
        case id, name, color, enabled
        case sidebarHidden = "sidebar_hidden"
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

    enum CodingKeys: String, CodingKey {
        case id, name, color, enabled
        case entityId = "entity_id"
    }
}

struct UserProfile: Codable {
    let id: Int
    let username: String
    var email: String?
    let isAdmin: Bool
    let hasAvatar: Bool
    let totpEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, email
        case isAdmin = "is_admin"
        case hasAvatar = "has_avatar"
        case totpEnabled = "totp_enabled"
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
