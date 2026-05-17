import SwiftUI

struct ServerView: View {
    @Environment(AppState.self) var appState
    @State private var showLogoutConfirm = false
    @State private var showChangeServer = false
    @State private var showImpressum = false

    var serverHost: String {
        appState.serverURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Verbundener Server") {
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
                            Text("Admin")
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
                            Text("Server wechseln")
                        }
                    }
                    .foregroundStyle(.primary)

                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .frame(width: 28)
                            Text("Abmelden")
                        }
                    }
                }

                Section("Info") {
                    Button {
                        showImpressum = true
                    } label: {
                        HStack {
                            Image(systemName: "info.circle")
                                .frame(width: 28)
                            Text("Impressum")
                        }
                    }
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog("Abmelden", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) {
                    appState.logout()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Du wirst von \(serverHost) abgemeldet.")
            }
            .confirmationDialog("Server wechseln", isPresented: $showChangeServer, titleVisibility: .visible) {
                Button("Server wechseln", role: .destructive) {
                    appState.resetServer()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Verbindung zu \(serverHost) wird getrennt und alle lokalen Anmeldedaten werden gelöscht.")
            }
            .sheet(isPresented: $showImpressum) {
                ImpressumView()
            }
        }
    }
}

struct ImpressumView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("Scarriffleservices")
                            .font(.title2.bold())
                        Text("Software & Webentwicklung")
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Text("Diese Software wurde von Scarriffleservices mit grösster Sorgfalt entwickelt und bereitgestellt. Alle Rechte vorbehalten © 2026 Scarriffleservices.")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Datenspeicherung").font(.headline)
                        Text("Alle Anwendungsdaten werden auf dem Server gespeichert und verarbeitet, auf dem diese Calendarr-Instanz betrieben wird. Der Speicherort hängt damit vom Betreiber des jeweiligen Servers ab. Bei Nutzung der Google Kalender-Anbindung werden Daten über die Google API ausgetauscht; für diese Daten gelten die Datenschutzbestimmungen von Google. Bei Nutzung der Home Assistant-Anbindung werden Daten mit der jeweiligen Home Assistant-Instanz ausgetauscht. Home Assistant ist ein Projekt der Open Home Foundation.")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Haftungsausschluss").font(.headline)
                        Text("Trotz sorgfältiger Erstellung wird keine Haftung für die Richtigkeit, Vollständigkeit oder Aktualität der bereitgestellten Inhalte übernommen. Die Nutzung erfolgt auf eigene Verantwortung.")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Kontakt").font(.headline)
                        Link("scarriffleservices@gmail.com", destination: URL(string: "mailto:scarriffleservices@gmail.com")!)
                    }

                    Divider()

                    Text("Calendarr v11 · iOS App v1.0")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
            }
            .navigationTitle("Impressum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Schliessen") { dismiss() }
                }
            }
        }
    }
}
