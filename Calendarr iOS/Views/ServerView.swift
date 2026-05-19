import SwiftUI

struct ServerView: View {
    @Environment(AppState.self) var appState
    @State private var showLogoutConfirm = false
    @State private var showChangeServer = false
    @State private var showImpressum = false
    @AppStorage("appLanguage") private var appLang = "system"

    var serverHost: String {
        appState.serverURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("server.connected", appLang)) {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(serverHost)
                                .font(.body)
                            Text(appState.serverURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        Text(appState.username)
                        if appState.isAdmin {
                            Spacer()
                            Text(L10n.t("menu.admin", appLang))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }

                Section {
                    Button {
                        showChangeServer = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.swap")
                                .frame(width: 28)
                            Text(L10n.t("server.switch", appLang))
                        }
                    }
                    .foregroundStyle(.primary)

                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .frame(width: 28)
                            Text(L10n.t("menu.logout", appLang))
                        }
                    }
                }

                Section(L10n.t("server.info", appLang)) {
                    Button {
                        showImpressum = true
                    } label: {
                        HStack {
                            Image(systemName: "info.circle")
                                .frame(width: 28)
                            Text(L10n.t("server.imprint", appLang))
                        }
                    }
                    .foregroundStyle(.secondary)

                    HStack {
                        Text(L10n.t("server.version", appLang))
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.t("server.title", appLang))
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog(L10n.t("server.logout_title", appLang), isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button(L10n.t("menu.logout", appLang), role: .destructive) {
                    appState.logout()
                }
                Button(L10n.t("common.cancel", appLang), role: .cancel) {}
            } message: {
                Text(String(format: L10n.t("server.logout_msg", appLang), serverHost))
            }
            .confirmationDialog(L10n.t("server.switch", appLang), isPresented: $showChangeServer, titleVisibility: .visible) {
                Button(L10n.t("server.switch", appLang), role: .destructive) {
                    appState.resetServer()
                }
                Button(L10n.t("common.cancel", appLang), role: .cancel) {}
            } message: {
                Text(String(format: L10n.t("server.switch_msg", appLang), serverHost))
            }
            .sheet(isPresented: $showImpressum) {
                ImpressumView()
            }
        }
    }
}

struct ImpressumView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var appLang = "system"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text(L10n.t("imprint.company", appLang))
                            .font(.title2.bold())
                        Text(L10n.t("imprint.role", appLang))
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Text(L10n.t("imprint.copyright", appLang))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("imprint.storage.title", appLang)).font(.headline)
                        Text(L10n.t("imprint.storage.body", appLang))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("imprint.disclaimer.title", appLang)).font(.headline)
                        Text(L10n.t("imprint.disclaimer.body", appLang))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("imprint.contact.title", appLang)).font(.headline)
                        Link("scarriffleservices@gmail.com", destination: URL(string: "mailto:scarriffleservices@gmail.com")!)
                    }

                    Divider()

                    Text("Calendarr v11 · iOS App v1.0")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
            }
            .navigationTitle(L10n.t("server.imprint", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.t("common.close", appLang)) { dismiss() }
                }
            }
        }
    }
}
