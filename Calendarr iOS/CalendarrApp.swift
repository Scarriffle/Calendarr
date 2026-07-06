import SwiftUI
import Security

@main
struct CalendarrApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}

@Observable
class AppState {
    var serverURL: String = ""
    var authToken: String = ""
    var username: String = ""
    var isAdmin: Bool = false

    var isConfigured: Bool { !serverURL.isEmpty }
    var isLoggedIn: Bool { !authToken.isEmpty }

    init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        // Migrate a token previously kept in UserDefaults into the Keychain once,
        // so existing logins survive the change without re-authenticating.
        if let legacy = UserDefaults.standard.string(forKey: "authToken"), !legacy.isEmpty {
            Keychain.set(legacy, for: "authToken")
            UserDefaults.standard.removeObject(forKey: "authToken")
        }
        authToken = Keychain.get("authToken") ?? ""
        username = UserDefaults.standard.string(forKey: "username") ?? ""
        isAdmin = UserDefaults.standard.bool(forKey: "isAdmin")
    }

    func saveServer(url: String) {
        serverURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if serverURL.hasSuffix("/") { serverURL = String(serverURL.dropLast()) }
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
    }

    func saveLogin(token: String, user: String, admin: Bool) {
        authToken = token
        username = user
        isAdmin = admin
        Keychain.set(token, for: "authToken")   // secret → Keychain, not UserDefaults
        UserDefaults.standard.set(user, forKey: "username")
        UserDefaults.standard.set(admin, forKey: "isAdmin")
    }

    func logout() {
        authToken = ""
        username = ""
        isAdmin = false
        Keychain.set(nil, for: "authToken")
        UserDefaults.standard.removeObject(forKey: "authToken")  // clear any legacy copy
        UserDefaults.standard.removeObject(forKey: "username")
        UserDefaults.standard.removeObject(forKey: "isAdmin")
    }

    func resetServer() {
        logout()
        serverURL = ""
        UserDefaults.standard.removeObject(forKey: "serverURL")
    }
}

/// Minimal Keychain wrapper for secrets (the auth bearer token). Values are
/// stored as generic passwords, accessible after first unlock.
enum Keychain {
    private static let service = "Calendarr"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
