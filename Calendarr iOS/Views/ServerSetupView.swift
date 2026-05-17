import SwiftUI

struct ServerSetupView: View {
    @Environment(AppState.self) var appState
    @State private var urlInput = ""
    @State private var error = ""
    @State private var isChecking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(Color.accentColor)
                        Text("Calendarr")
                            .font(.largeTitle.bold())
                        Text("Server verbinden")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server-URL")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("https://calendarr.example.com", text: $urlInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(12)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        if !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            if isChecking {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Verbinden")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(urlInput.isEmpty || isChecking)
                }
                .padding(.horizontal, 32)

                Spacer()

                Text("© 2026 Scarriffleservices")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
            .navigationBarHidden(true)
        }
    }

    private func connect() async {
        isChecking = true
        error = ""
        defer { isChecking = false }

        var url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http") { url = "https://" + url }
        if url.hasSuffix("/") { url = String(url.dropLast()) }

        do {
            _ = try await CalendarrAPI.checkSetupRequired(baseURL: url)
            appState.saveServer(url: url)
        } catch {
            self.error = "Server nicht erreichbar. URL prüfen."
        }
    }
}
