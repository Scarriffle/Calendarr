import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case twoFactorRequired
    case serverError(String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige Server-URL"
        case .unauthorized: return "Benutzername oder Passwort falsch"
        case .twoFactorRequired: return "2FA-Code erforderlich"
        case .serverError(let msg): return msg
        case .decodingError: return "Antwort konnte nicht verarbeitet werden"
        }
    }
}

class CalendarrAPI {
    let baseURL: String
    let token: String

    init(baseURL: String, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw APIError.unauthorized }
        if status >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Fehler \(status)"
            throw APIError.serverError(msg)
        }
        return data
    }

    static func login(baseURL: String, username: String, password: String, totpCode: String? = nil, rememberMe: Bool = false) async throws -> (token: String, username: String, isAdmin: Bool) {
        guard let url = URL(string: baseURL + "/api/auth/login") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["username": username, "password": password, "remember_me": rememberMe]
        if let code = totpCode { body["totp_code"] = code }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? ""
            if detail == "2fa_required" { throw APIError.twoFactorRequired }
            throw APIError.unauthorized
        }
        if status >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Fehler"
            throw APIError.serverError(msg)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String,
              let user = json["user"] as? [String: Any],
              let uname = user["username"] as? String else {
            throw APIError.decodingError
        }
        let admin = user["is_admin"] as? Bool ?? false
        // Persist id + display name for creator/owner comparisons and display.
        UserDefaults.standard.set(user["id"] as? Int ?? 0, forKey: "userId")
        UserDefaults.standard.set(user["display_name"] as? String ?? uname, forKey: "displayName")
        return (token, uname, admin)
    }

    static func checkSetupRequired(baseURL: String) async throws -> Bool {
        guard let url = URL(string: baseURL + "/api/auth/setup-required") else { throw APIError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["required"] as? Bool ?? false
    }

    func getSettings() async throws -> AppSettings {
        let data = try await request("/api/settings/")
        guard let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { throw APIError.decodingError }
        return settings
    }

    func updateSettings(_ settings: AppSettings) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let body = try? encoder.encode(settings),
              let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return }
        _ = try await request("/api/settings/", method: "PUT", body: dict)
    }

    func getProfile() async throws -> UserProfile {
        let data = try await request("/api/auth/me")
        guard let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { throw APIError.decodingError }
        return profile
    }

    func updateEmail(_ email: String) async throws {
        _ = try await request("/api/profile/", method: "PATCH", body: ["email": email])
    }

    func changePassword(current: String, new: String) async throws {
        _ = try await request("/api/profile/password", method: "POST", body: ["current_password": current, "new_password": new])
    }

    func getCalDAVAccounts() async throws -> [CalDAVAccount] {
        let data = try await request("/api/caldav/accounts")
        return (try? JSONDecoder().decode([CalDAVAccount].self, from: data)) ?? []
    }

    func addCalDAVAccount(name: String, url: String, username: String, password: String, color: String) async throws -> CalDAVAccount {
        let data = try await request("/api/caldav/accounts", method: "POST", body: [
            "name": name, "url": url, "username": username, "password": password, "color": color
        ])
        guard let acc = try? JSONDecoder().decode(CalDAVAccount.self, from: data) else { throw APIError.decodingError }
        return acc
    }

    func deleteCalDAVAccount(id: Int) async throws {
        _ = try await request("/api/caldav/accounts/\(id)", method: "DELETE")
    }

    func getLocalCalendars() async throws -> [LocalCalendar] {
        let data = try await request("/api/local/calendars")
        return (try? JSONDecoder().decode([LocalCalendar].self, from: data)) ?? []
    }

    func addLocalCalendar(name: String, color: String) async throws -> LocalCalendar {
        let data = try await request("/api/local/calendars", method: "POST", body: ["name": name, "color": color])
        guard let cal = try? JSONDecoder().decode(LocalCalendar.self, from: data) else { throw APIError.decodingError }
        return cal
    }

    func deleteLocalCalendar(id: Int) async throws {
        _ = try await request("/api/local/calendars/\(id)", method: "DELETE")
    }

    func getICalSubscriptions() async throws -> [ICalSubscription] {
        let data = try await request("/api/ical/subscriptions")
        return (try? JSONDecoder().decode([ICalSubscription].self, from: data)) ?? []
    }

    func addICalSubscription(name: String, url: String, color: String, refreshMinutes: Int) async throws -> ICalSubscription {
        let data = try await request("/api/ical/subscriptions", method: "POST", body: [
            "name": name, "url": url, "color": color, "refresh_minutes": refreshMinutes
        ])
        guard let sub = try? JSONDecoder().decode(ICalSubscription.self, from: data) else { throw APIError.decodingError }
        return sub
    }

    func deleteICalSubscription(id: Int) async throws {
        _ = try await request("/api/ical/subscriptions/\(id)", method: "DELETE")
    }

    func getGoogleAccounts() async throws -> [GoogleAccount] {
        let data = try await request("/api/google/accounts")
        return (try? JSONDecoder().decode([GoogleAccount].self, from: data)) ?? []
    }

    func deleteGoogleAccount(id: Int) async throws {
        _ = try await request("/api/google/accounts/\(id)", method: "DELETE")
    }

    func getHomeAssistantAccounts() async throws -> [HomeAssistantAccount] {
        let data = try await request("/api/homeassistant/accounts")
        return (try? JSONDecoder().decode([HomeAssistantAccount].self, from: data)) ?? []
    }

    func addHomeAssistantAccount(name: String, url: String, token: String) async throws -> HomeAssistantAccount {
        let data = try await request("/api/homeassistant/accounts", method: "POST", body: [
            "name": name, "url": url, "token": token, "auth_method": "token"
        ])
        guard let acc = try? JSONDecoder().decode(HomeAssistantAccount.self, from: data) else { throw APIError.decodingError }
        return acc
    }

    func deleteHomeAssistantAccount(id: Int) async throws {
        _ = try await request("/api/homeassistant/accounts/\(id)", method: "DELETE")
    }

    func setup2FA() async throws -> (secret: String, qrUrl: String) {
        let data = try await request("/api/profile/2fa/setup", method: "POST")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let secret = json["secret"] as? String,
              let qr = json["qr_url"] as? String else { throw APIError.decodingError }
        return (secret, qr)
    }

    func enable2FA(code: String) async throws {
        _ = try await request("/api/profile/2fa/enable", method: "POST", body: ["code": code])
    }

    func disable2FA(password: String) async throws {
        _ = try await request("/api/profile/2fa/disable", method: "POST", body: ["password": password])
    }

    // MARK: – Events

    func fetchEvents(start: Date, end: Date) async throws -> [CalEvent] {
        // Use UTC with Z suffix – avoids '+' character which breaks URL query params
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(abbreviation: "UTC")
        let s = iso.string(from: start)   // e.g. "2026-05-01T00:00:00Z"
        let e = iso.string(from: end)
        let sEnc = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        let eEnc = e.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? e
        let data = try await request("/api/caldav/events?start=\(sEnc)&end=\(eEnc)")
        // Server returns {"events": [...], "errors": [...]}
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let arr = root["events"] as? [[String: Any]]
        else {
            let preview = String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? "no data"
            throw APIError.serverError("Unerwartete Antwort: \(preview)")
        }
        return arr.compactMap { CalEvent.from(json: $0) }
    }

    func createLocalEvent(calendarId: Int, title: String, start: Date, end: Date,
                          isAllDay: Bool, location: String, description: String, color: String?,
                          isPrivate: Bool = false) async throws -> CalEvent {
        var body: [String: Any] = [
            "calendar_id": calendarId,
            "title": title,
            "start": formatISO(start, allDay: isAllDay),
            "end": formatISO(end, allDay: isAllDay),
            "allDay": isAllDay,
            "location": location,
            "description": description,
            "private": isPrivate
        ]
        if let c = color, !c.isEmpty { body["color"] = c }
        let data = try await request("/api/local/events", method: "POST", body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ev = CalEvent.from(json: json) else { throw APIError.decodingError }
        return ev
    }

    func updateLocalEvent(uid: String, title: String, start: Date, end: Date,
                          isAllDay: Bool, location: String, description: String, color: String?,
                          isPrivate: Bool = false) async throws {
        var body: [String: Any] = [
            "title": title,
            "start": formatISO(start, allDay: isAllDay),
            "end": formatISO(end, allDay: isAllDay),
            "allDay": isAllDay,
            "location": location,
            "description": description,
            "private": isPrivate
        ]
        if let c = color { body["color"] = c }
        _ = try await request("/api/local/events/\(uid)", method: "PUT", body: body)
    }

    func deleteLocalEvent(uid: String) async throws {
        _ = try await request("/api/local/events/\(uid)", method: "DELETE")
    }

    func createCalDAVEvent(calendarId: Int, title: String, start: Date, end: Date,
                           isAllDay: Bool, location: String, description: String, color: String?) async throws {
        var body: [String: Any] = [
            "calendar_id": calendarId,
            "title": title,
            "start": formatISO(start, allDay: isAllDay),
            "end": formatISO(end, allDay: isAllDay),
            "allDay": isAllDay,
            "location": location,
            "description": description
        ]
        if let c = color, !c.isEmpty { body["color"] = c }
        _ = try await request("/api/caldav/events", method: "POST", body: body)
    }

    func updateCalDAVEvent(uid: String, url: String, calendarId: Int?, title: String,
                           start: Date, end: Date, isAllDay: Bool,
                           location: String, description: String, color: String?) async throws {
        var body: [String: Any] = [
            "title": title,
            "start": formatISO(start, allDay: isAllDay),
            "end": formatISO(end, allDay: isAllDay),
            "allDay": isAllDay,
            "location": location,
            "description": description
        ]
        if let c = color { body["color"] = c }
        let encURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        var path = "/api/caldav/events/\(uid)?event_url=\(encURL)"
        if let cid = calendarId { path += "&calendar_id=\(cid)" }
        _ = try await request(path, method: "PUT", body: body)
    }

    func deleteCalDAVEvent(uid: String, url: String, calendarId: Int?) async throws {
        let encURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        var path = "/api/caldav/events/\(uid)?event_url=\(encURL)"
        if let cid = calendarId { path += "&calendar_id=\(cid)" }
        _ = try await request(path, method: "DELETE")
    }

    // MARK: – Google Calendar events

    func getGoogleCalendars() async throws -> [(accountEmail: String, calId: Int, name: String, color: String)] {
        let data = try await request("/api/google/accounts")
        guard let accounts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var result: [(String, Int, String, String)] = []
        for acc in accounts {
            let email = acc["email"] as? String ?? "Google"
            let cals = acc["calendars"] as? [[String: Any]] ?? []
            for cal in cals where (cal["enabled"] as? Bool ?? true) {
                if let id = cal["id"] as? Int, let name = cal["name"] as? String {
                    let color = cal["color"] as? String ?? "#4285f4"
                    result.append((email, id, name, color))
                }
            }
        }
        return result
    }

    func createGoogleEvent(calendarDbId: Int, title: String, start: Date, end: Date,
                           isAllDay: Bool, location: String, description: String) async throws {
        let body: [String: Any] = [
            "calendar_db_id": calendarDbId,
            "title": title,
            "start": formatISO(start, allDay: isAllDay),
            "end": formatISO(end, allDay: isAllDay),
            "allDay": isAllDay,
            "location": location,
            "description": description
        ]
        _ = try await request("/api/google/events", method: "POST", body: body)
    }

    // MARK: – Home Assistant events

    func getHACalendars() async throws -> [(accountName: String, calId: Int, name: String, color: String)] {
        let data = try await request("/api/homeassistant/accounts")
        guard let accounts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var result: [(String, Int, String, String)] = []
        for acc in accounts {
            let aName = acc["name"] as? String ?? "Home Assistant"
            let cals = acc["calendars"] as? [[String: Any]] ?? []
            for cal in cals where (cal["enabled"] as? Bool ?? true) {
                if let id = cal["id"] as? Int, let name = cal["name"] as? String {
                    let color = cal["color"] as? String ?? "#46bdc6"
                    result.append((aName, id, name, color))
                }
            }
        }
        return result
    }

    func createHAEvent(calendarId: Int, title: String, start: Date, end: Date,
                       isAllDay: Bool, location: String, description: String) async throws {
        let body: [String: Any] = [
            "calendar_id": calendarId,
            "title": title,
            "start": formatISO(start, allDay: isAllDay),
            "end": formatISO(end, allDay: isAllDay),
            "allDay": isAllDay,
            "location": location,
            "description": description
        ]
        _ = try await request("/api/homeassistant/events", method: "POST", body: body)
    }

    /// Delete a Home Assistant calendar event.
    /// `calendarId` is the numeric HA-calendar DB id; `uid` is the HA event uid.
    func deleteHAEvent(calendarId: Int, uid: String) async throws {
        // uid is a path segment and may contain "/" or other reserved chars.
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let encUid = uid.addingPercentEncoding(withAllowedCharacters: allowed) ?? uid
        _ = try await request("/api/homeassistant/events/\(calendarId)/\(encUid)", method: "DELETE")
    }

    // MARK: – Calendar visibility (sidebar_hidden)

    /// Toggle a calendar's server-side visibility. Mirrors the web: hiding sets
    /// `enabled=false, sidebar_hidden=true` (server then omits its events);
    /// showing sets `enabled=true, sidebar_hidden=false`. Only CalDAV / Google /
    /// Home Assistant have this flag; `local` / `ical` are a no-op.
    func setCalendarSidebarHidden(source: String, calendarId: Int, hidden: Bool) async throws {
        let path: String
        switch source {
        case "caldav":        path = "/api/caldav/calendars/\(calendarId)"
        case "google":        path = "/api/google/calendars/\(calendarId)"
        case "homeassistant": path = "/api/homeassistant/calendars/\(calendarId)"
        default:              return
        }
        _ = try await request(path, method: "PUT",
                              body: ["enabled": !hidden, "sidebar_hidden": hidden])
    }

    // MARK: – Profile (display name / login name / email)

    /// Update profile fields. A login-name change returns a fresh token (the old
    /// one becomes invalid) — the caller must store the returned token.
    func updateProfile(displayName: String?, username: String?, email: String?) async throws -> String? {
        var body: [String: Any] = [:]
        if let d = displayName { body["display_name"] = d }
        if let u = username { body["username"] = u }
        if let e = email { body["email"] = e } else { body["email"] = NSNull() }
        let data = try await request("/api/profile/", method: "PUT", body: body)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["access_token"] as? String
    }

    // MARK: – Sharing

    func getUserDirectory() async throws -> [DirectoryUser] {
        let data = try await request("/api/users/directory")
        return (try? JSONDecoder().decode([DirectoryUser].self, from: data)) ?? []
    }

    func getShares(calendarId: Int) async throws -> [CalendarShare] {
        let data = try await request("/api/local/calendars/\(calendarId)/shares")
        return (try? JSONDecoder().decode([CalendarShare].self, from: data)) ?? []
    }

    func addShare(calendarId: Int, userId: Int, permission: String) async throws {
        _ = try await request("/api/local/calendars/\(calendarId)/shares", method: "POST",
                              body: ["user_id": userId, "permission": permission])
    }

    func removeShare(calendarId: Int, userId: Int) async throws {
        _ = try await request("/api/local/calendars/\(calendarId)/shares/\(userId)", method: "DELETE")
    }

    // MARK: – Groups

    func getGroups() async throws -> [CalGroup] {
        let data = try await request("/api/groups/")
        return (try? JSONDecoder().decode([CalGroup].self, from: data)) ?? []
    }

    func getGroup(id: Int) async throws -> CalGroup {
        let data = try await request("/api/groups/\(id)")
        guard let g = try? JSONDecoder().decode(CalGroup.self, from: data) else { throw APIError.decodingError }
        return g
    }

    func createGroup(name: String, memberIds: [Int], icon: String?) async throws -> CalGroup {
        var body: [String: Any] = ["name": name, "member_ids": memberIds]
        if let icon { body["icon"] = icon }
        let data = try await request("/api/groups/", method: "POST", body: body)
        guard let g = try? JSONDecoder().decode(CalGroup.self, from: data) else { throw APIError.decodingError }
        return g
    }

    func updateGroup(id: Int, name: String?, icon: String?) async throws {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let icon { body["icon"] = icon }
        _ = try await request("/api/groups/\(id)", method: "PUT", body: body)
    }

    func deleteGroup(id: Int) async throws {
        _ = try await request("/api/groups/\(id)", method: "DELETE")
    }

    func addGroupMember(groupId: Int, userId: Int) async throws {
        _ = try await request("/api/groups/\(groupId)/members", method: "POST", body: ["user_id": userId])
    }

    func removeGroupMember(groupId: Int, userId: Int) async throws {
        _ = try await request("/api/groups/\(groupId)/members/\(userId)", method: "DELETE")
    }

    func setGroupMemberColor(groupId: Int, userId: Int, color: String) async throws {
        _ = try await request("/api/groups/\(groupId)/members/\(userId)/color", method: "PUT",
                              body: ["color": color])
    }

    func fetchGroupCombined(groupId: Int, start: Date, end: Date) async throws -> [CalEvent] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(abbreviation: "UTC")
        let s = iso.string(from: start)
        let e = iso.string(from: end)
        let sEnc = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        let eEnc = e.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? e
        let data = try await request("/api/groups/\(groupId)/combined?start=\(sEnc)&end=\(eEnc)")
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["events"] as? [[String: Any]] else { return [] }
        return arr.compactMap { CalEvent.from(json: $0) }
    }

    // MARK: – iCal import / export

    /// Import a .ics file into a local calendar. Returns (imported, skipped, errors).
    func importICS(calendarId: Int, fileURL: URL) async throws -> (imported: Int, skipped: Int, errors: [String]) {
        guard let url = URL(string: baseURL + "/api/local/calendars/\(calendarId)/import") else { throw APIError.invalidURL }
        let fileData = try Data(contentsOf: fileURL)
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var bodyData = Data()
        let filename = fileURL.lastPathComponent.isEmpty ? "import.ics" : fileURL.lastPathComponent
        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        bodyData.append("Content-Type: text/calendar\r\n\r\n".data(using: .utf8)!)
        bodyData.append(fileData)
        bodyData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = bodyData
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw APIError.unauthorized }
        if status >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Fehler \(status)"
            throw APIError.serverError(msg)
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errs = (json?["errors"] as? [String]) ?? []
        return (json?["imported"] as? Int ?? 0, json?["skipped"] as? Int ?? 0, errs)
    }

    /// Export a local calendar as raw .ics bytes.
    func exportICS(calendarId: Int) async throws -> Data {
        return try await request("/api/local/calendars/\(calendarId)/export")
    }
}
