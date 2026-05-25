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

    @AppStorage("appLanguage") private var appLang = "system"

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(L10n.t("profile.loading", appLang))
                } else if let profile {
                    Form {
                        kontoSection(profile: profile)
                        passwordSection
                        twoFASection(profile: profile)
                        adminNoteSection
                    }
                }
            }
            .navigationTitle(L10n.t("profile.title", appLang))
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
        Section(L10n.t("profile.account", appLang)) {
            HStack {
                Text(L10n.t("profile.username", appLang))
                Spacer()
                Text(profile.username)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(L10n.t("profile.role", appLang))
                Spacer()
                Text(profile.isAdmin
                     ? L10n.t("profile.role.admin", appLang)
                     : L10n.t("profile.role.user", appLang))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(L10n.t("profile.email", appLang))
                Spacer()
                TextField(L10n.t("profile.no_email", appLang), text: $newEmail)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
            Button(L10n.t("profile.save_email", appLang)) {
                Task { await saveEmail() }
            }
            .foregroundStyle(Color.accentColor)
        }
    }

    var passwordSection: some View {
        Section(L10n.t("profile.change_password", appLang)) {
            SecureField(L10n.t("profile.current_password", appLang), text: $currentPW)
            SecureField(L10n.t("profile.new_password", appLang), text: $newPW)
            SecureField(L10n.t("profile.new_password_repeat", appLang), text: $confirmPW)
            Button(L10n.t("profile.change_password", appLang)) {
                Task { await changePassword() }
            }
            .foregroundStyle(Color.accentColor)
            .disabled(currentPW.isEmpty || newPW.isEmpty || confirmPW.isEmpty)
        }
    }

    func twoFASection(profile: UserProfile) -> some View {
        Section(L10n.t("profile.twofa", appLang)) {
            if profile.totpEnabled {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text(L10n.t("profile.twofa.active", appLang))
                }
                Button(L10n.t("profile.twofa.disable", appLang)) {
                    show2FADisable = true
                }
                .foregroundStyle(.red)
            } else {
                HStack {
                    Image(systemName: "shield")
                        .foregroundStyle(.secondary)
                    Text(L10n.t("profile.twofa.inactive", appLang))
                        .foregroundStyle(.secondary)
                }
                Button(L10n.t("profile.twofa.enable", appLang)) {
                    Task { await setup2FA() }
                }
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    var adminNoteSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Text(L10n.t("profile.admin_note", appLang))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
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
            showNotice(L10n.t("profile.email_saved", appLang))
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    private func changePassword() async {
        guard newPW == confirmPW else {
            showNotice(L10n.t("profile.password_mismatch", appLang))
            return
        }
        do {
            try await api.changePassword(current: currentPW, new: newPW)
            currentPW = ""; newPW = ""; confirmPW = ""
            showNotice(L10n.t("profile.password_changed", appLang))
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
            showNotice(L10n.t("profile.twofa.enabled_toast", appLang))
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
            showNotice(L10n.t("profile.twofa.disabled_toast", appLang))
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
    @AppStorage("appLanguage") private var appLang = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.t("twofa.scan_hint", appLang))
                        .font(.body)
                }
                Section(L10n.t("twofa.qr_section", appLang)) {
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
                Section(L10n.t("twofa.confirmation", appLang)) {
                    TextField(L10n.t("twofa.code_placeholder", appLang), text: $code)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle(L10n.t("twofa.setup_title", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("common.cancel", appLang)) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.t("twofa.activate", appLang)) { onEnable() }
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
    @AppStorage("appLanguage") private var appLang = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("twofa.password_section", appLang)) {
                    SecureField(L10n.t("twofa.password_placeholder", appLang), text: $password)
                }
            }
            .navigationTitle(L10n.t("twofa.disable_title", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("common.cancel", appLang)) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.t("twofa.disable", appLang)) { onDisable() }
                        .bold()
                        .foregroundStyle(.red)
                        .disabled(password.isEmpty)
                }
            }
        }
    }
}
