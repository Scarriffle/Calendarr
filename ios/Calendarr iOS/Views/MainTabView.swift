import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) var appState
    @State private var showMenu = false

    var api: CalendarrAPI {
        CalendarrAPI(baseURL: appState.serverURL, token: appState.authToken)
    }

    var body: some View {
        CalendarHostView(api: api, showMenu: $showMenu)
            .ignoresSafeArea(edges: .bottom)
            .sheet(isPresented: $showMenu) {
                MenuSheet(api: api)
            }
    }
}
