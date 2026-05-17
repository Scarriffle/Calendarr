import SwiftUI

struct MenuSheet: View {
    let api: CalendarrAPI
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

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
                            Text("Admin")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Navigation links – direct destination syntax (no value-based nav)
                Section("Einstellungen") {
                    NavigationLink {
                        ProfileView(api: api)
                    } label: {
                        Label("Profil", systemImage: "person.circle")
                    }

                    NavigationLink {
                        SettingsView(api: api)
                    } label: {
                        Label("Darstellung", systemImage: "paintpalette")
                    }

                    NavigationLink {
                        AccountsView(api: api)
                    } label: {
                        Label("Konten & Kalender", systemImage: "tray.2")
                    }

                    NavigationLink {
                        ServerView()
                    } label: {
                        Label("Server", systemImage: "server.rack")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appState.logout()
                        }
                    } label: {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Menü")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
