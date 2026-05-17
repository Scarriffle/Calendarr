import SwiftUI

struct ProfileView: View {
    let api: CalendarrAPI
    @State private var profile: UserProfile?
    @State private var isLoading = true

    @State private var newEmail = ""
    @State private var currentPW = ""
    @State private var newPW = ""
    @State private var confirmPW = ""

    @State private var toast = ""
    @State private var showToast = false

    @State private var show2FASetup = false
    @State private var show2FADisable = false
    @State private var totpQR = ""
    @State private var totpSecret = ""
    @State private var totpCode = ""
    @State private var disablePW = ""
    @State private var isSaving2FA = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Lade Profil…")
                } else if let profile {
                    Form {
                        kontoSection(profile: profile)
                        passwordSection
                        twoFASection(profile: profile)
                    }
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.large)
            .overlay(alignment: .bottom) {
                if showToast {
                    Text(toast)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: showToast)
            .sheet(isPresented: $show2FASetup) {
                TwoFASetupSheet(
                    qrURL: totpQR,
                    secret: totpSecret,
                    code: $totpCode,
                    isSaving: isSaving2FA
                ) {
                    Task { await enable2FA() }
                }
            }
            .sheet(isPresented: $show2FADisable) {
                TwoFADisableSheet(password: $disablePW) {
                    Task { await disable2FA() }
                }
            }
        }
        .task { await load() }
    }

    func kontoSection(profile: UserProfile) -> some View {
        Section("Konto") {
            HStack {
                Text("Benutzername")
                Spacer()
                Text(profile.username)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Rolle")
                Spacer()
                Text(profile.isAdmin ? "Administrator" : "Benutzer")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("E-Mail")
                Spacer()
                TextField("Keine E-Mail", text: $newEmail)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
            Button("E-Mail speichern") {
                Task { await saveEmail() }
            }
            .foregroundStyle(Color.accentColor)
        }
    }

    var passwordSection: some View {
        Section("Passwort ändern") {
            SecureField("Aktuelles Passwort", text: $currentPW)
            SecureField("Neues Passwort", text: $newPW)
            SecureField("Neues Passwort wiederholen", text: $confirmPW)
            Button("Passwort ändern") {
                Task { await changePassword() }
            }
            .foregroundStyle(Color.accentColor)
            .disabled(currentPW.isEmpty || newPW.isEmpty || confirmPW.isEmpty)
        }
    }

    func twoFASection(profile: UserProfile) -> some View {
        Section("Zwei-Faktor-Authentifizierung") {
            if profile.totpEnabled {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("2FA ist aktiviert")
                }
                Button("2FA deaktivieren") {
                    show2FADisable = true
                }
                .foregroundStyle(.red)
            } else {
                HStack {
                    Image(systemName: "shield")
                        .foregroundStyle(.secondary)
                    Text("2FA ist deaktiviert")
                        .foregroundStyle(.secondary)
                }
                Button("2FA einrichten") {
                    Task { await setup2FA() }
                }
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let p = try? await api.getProfile() {
            profile = p
            newEmail = p.email ?? ""
        }
    }

    private func saveEmail() async {
        do {
            try await api.updateEmail(newEmail)
            showNotice("E-Mail gespeichert")
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    private func changePassword() async {
        guard newPW == confirmPW else {
            showNotice("Passwörter stimmen nicht überein")
            return
        }
        do {
            try await api.changePassword(current: currentPW, new: newPW)
            currentPW = ""; newPW = ""; confirmPW = ""
            showNotice("Passwort geändert")
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    private func setup2FA() async {
        do {
            let result = try await api.setup2FA()
            totpSecret = result.secret
            totpQR = result.qrUrl
            totpCode = ""
            show2FASetup = true
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    private func enable2FA() async {
        isSaving2FA = true
        do {
            try await api.enable2FA(code: totpCode)
            show2FASetup = false
            showNotice("2FA aktiviert")
            await load()
        } catch {
            showNotice(error.localizedDescription)
        }
        isSaving2FA = false
    }

    private func disable2FA() async {
        do {
            try await api.disable2FA(password: disablePW)
            show2FADisable = false
            showNotice("2FA deaktiviert")
            await load()
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    private func showNotice(_ msg: String) {
        toast = msg
        withAnimation { showToast = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showToast = false }
        }
    }
}

struct TwoFASetupSheet: View {
    let qrURL: String
    let secret: String
    @Binding var code: String
    let isSaving: Bool
    let onEnable: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Scanne den QR-Code mit deiner Authenticator-App (z.B. Bitwarden, Google Authenticator).")
                        .font(.body)
                }
                Section("QR-Code / Manueller Schlüssel") {
                    if let url = URL(string: qrURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 200)
                                    .frame(maxWidth: .infinity)
                            default:
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    HStack {
                        Text(secret)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = secret
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
                Section("Bestätigung") {
                    TextField("6-stelliger Code", text: $code)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("2FA einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Aktivieren") { onEnable() }
                        .bold()
                        .disabled(code.count < 6 || isSaving)
                }
            }
        }
    }
}

struct TwoFADisableSheet: View {
    @Binding var password: String
    let onDisable: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Passwort zum Deaktivieren") {
                    SecureField("Passwort", text: $password)
                }
            }
            .navigationTitle("2FA deaktivieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Deaktivieren") { onDisable() }
                        .bold()
                        .foregroundStyle(.red)
                        .disabled(password.isEmpty)
                }
            }
        }
    }
}
