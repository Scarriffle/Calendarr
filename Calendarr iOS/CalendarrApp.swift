import SwiftUI

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
        authToken = Self.loadToken()
        username = UserDefaults.standard.string(forKey: "username") ?? ""
        isAdmin = UserDefaults.standard.bool(forKey: "isAdmin")
    }

    /// Find the stored token, migrating it forward from wherever an older build
    /// left it. Runs on every launch but does real work only once.
    ///
    /// Step 2 is the one that keeps existing users signed in. Before the
    /// `keychain-access-groups` entitlement existed, items landed in the app's
    /// own default group. Adding the entitlement makes the *first* array entry
    /// the new default — and that entry is deliberately the app's own group, so
    /// an unqualified query still resolves those items and we can copy them
    /// across instead of stranding them.
    private static func loadToken() -> String {
        let key = "authToken"

        // 1. Already in the shared group — the steady state.
        if let token = try? KeychainStore.get(key), !token.isEmpty {
            return token
        }

        // 2. In the app's own default group, written before the entitlement.
        if let token = try? KeychainStore.get(key, accessGroup: nil), !token.isEmpty {
            try? KeychainStore.set(token, for: key)
            try? KeychainStore.set(nil, for: key, accessGroup: nil)
            return token
        }

        // 3. In UserDefaults, written before secrets moved to the Keychain.
        if let legacy = UserDefaults.standard.string(forKey: key), !legacy.isEmpty {
            try? KeychainStore.set(legacy, for: key)
            UserDefaults.standard.removeObject(forKey: key)
            return legacy
        }

        return ""
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
        try? KeychainStore.set(token, for: "authToken")   // secret → Keychain, not UserDefaults
        UserDefaults.standard.set(user, forKey: "username")
        UserDefaults.standard.set(admin, forKey: "isAdmin")
        publishSession()
    }

    /// Mirror the non-secret session facts into the shared container. Apps in
    /// another sandbox cannot read our UserDefaults, so this is how they learn
    /// which server we point at and whether anyone is signed in. The token
    /// itself stays in the shared keychain group, never in a plain file.
    private func publishSession() {
        WidgetStore.writeSession(baseURL: serverURL,
                                 username: username,
                                 isLoggedIn: isLoggedIn)
    }

    func logout() {
        authToken = ""
        username = ""
        isAdmin = false
        try? KeychainStore.set(nil, for: "authToken")
        try? KeychainStore.set(nil, for: "authToken", accessGroup: nil)  // pre-entitlement copy
        // Drop the SSO session too, otherwise a stale provider refresh token
        // outlives the account it belonged to.
        OIDCAuthenticator.clearStoredSession()
        UserDefaults.standard.removeObject(forKey: "authToken")          // pre-Keychain copy
        UserDefaults.standard.removeObject(forKey: "username")
        UserDefaults.standard.removeObject(forKey: "isAdmin")
        // The shared container outlives the session, so it has to be cleared
        // explicitly — otherwise widgets keep showing the signed-out user's data.
        // The session record stays behind, flagged signed-out, so a reader can
        // say "sign in to Calendarr" rather than "open Calendarr once".
        WidgetStore.clear()
        publishSession()
    }

    func resetServer() {
        logout()
        serverURL = ""
        UserDefaults.standard.removeObject(forKey: "serverURL")
        // Back to unconfigured: there is no server left to name, so drop the
        // session record rather than leaving a stale URL in the container.
        WidgetStore.clearSession()
    }
}
