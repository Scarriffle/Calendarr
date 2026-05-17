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
        }
    }
}
