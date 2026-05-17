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
        authToken = UserDefaults.standard.string(forKey: "authToken") ?? ""
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
        UserDefaults.standard.set(token, forKey: "authToken")
        UserDefaults.standard.set(user, forKey: "username")
        UserDefaults.standard.set(admin, forKey: "isAdmin")
    }

    func logout() {
        authToken = ""
        username = ""
        isAdmin = false
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults.standard.removeObject(forKey: "username")
        UserDefaults.standard.removeObject(forKey: "isAdmin")
    }

    func resetServer() {
        logout()
        serverURL = ""
        UserDefaults.standard.removeObject(forKey: "serverURL")
    }
}
