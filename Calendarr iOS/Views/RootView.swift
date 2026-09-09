import SwiftUI

struct RootView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        if !appState.isConfigured {
            ServerSetupView()
        } else if !appState.isLoggedIn {
            LoginView()
        } else {
            MainTabView()
                // Renew an SSO session before it lapses, so a user signed in
                // via a provider is not bounced back to the login screen.
                .task { await OIDCSessionRefresher.refreshIfNeeded(appState) }
        }
    }
}
