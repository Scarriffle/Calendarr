import SwiftUI

struct MenuSheet: View {
    let api: CalendarrAPI
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var appLang = "system"
    @State private var isSyncing = false

    var body: some View {
        NavigationStack {
            List {
                // User info header
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Text(appState.username.prefix(1).uppercased())
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.username).font(.headline)
                            Text(appState.serverURL
                                .replacingOccurrences(of: "https://", with: "")
                                .replacingOccurrences(of: "http://", with: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if appState.isAdmin {
                            Spacer()
                            Text(L10n.t("menu.admin", appLang))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(L10n.t("menu.section.settings", appLang)) {
                    NavigationLink {
                        ProfileView(api: api)
                    } label: {
                        Label(L10n.t("menu.profile", appLang), systemImage: "person.circle")
                    }

                    NavigationLink {
                        SettingsView(api: api)
                    } label: {
                        Label(L10n.t("menu.appearance", appLang), systemImage: "paintpalette")
                    }

                    NavigationLink {
                        AccountsView(api: api)
                    } label: {
                        Label(L10n.t("menu.accounts", appLang), systemImage: "tray.2")
                    }

                    NavigationLink {
                        ServerView()
                    } label: {
                        Label(L10n.t("menu.server", appLang), systemImage: "server.rack")
                    }
                }

                Section(L10n.t("menu.sync.section", appLang)) {
                    Button {
                        Task { await syncNow() }
                    } label: {
                        HStack {
                            Label(L10n.t("menu.sync", appLang), systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isSyncing { ProgressView() }
                        }
                    }
                    .disabled(isSyncing)
                }

                Section {
                    Button(role: .destructive) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appState.logout()
                        }
                    } label: {
                        Label(L10n.t("menu.logout", appLang), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle(L10n.t("nav.menu", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.t("nav.done", appLang)) { dismiss() }
                }
            }
        }
    }

    /// Manual sync: pull appearance/behaviour settings from the server, then
    /// ask the calendar host to re-fetch events (cache-busting).
    private func syncNow() async {
        isSyncing = true
        await SettingsSync.pull(api: api)
        NotificationCenter.default.post(name: .manualSyncRequested, object: nil)
        isSyncing = false
        dismiss()
    }
}
