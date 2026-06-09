import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) var appState
    @AppStorage("appLanguage") private var appLang = "system"
    @State private var username = ""
    @State private var password = ""
    @State private var totpCode = ""
    @State private var rememberMe = true
    @State private var needsTOTP = false
    @State private var error = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    VStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(Color.accentColor)
                        Text("Calendarr")
                            .font(.largeTitle.bold())
                        Text(appState.serverURL
                            .replacingOccurrences(of: "https://", with: "")
                            .replacingOccurrences(of: "http://", with: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 40)

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("login.username", appLang))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField(L10n.t("login.username", appLang), text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("login.password", appLang))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                            SecureField(L10n.t("login.password", appLang), text: $password)
                                .padding(12)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        if needsTOTP {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.t("login.totp", appLang))
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.secondary)
                                TextField(L10n.t("login.totp_placeholder", appLang), text: $totpCode)
                                    .keyboardType(.numberPad)
                                    .padding(12)
                                    .background(.quaternary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        Toggle(L10n.t("login.remember", appLang), isOn: $rememberMe)
                            .tint(Color.accentColor)

                        if !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await login() }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(L10n.t("login.signin", appLang)).fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(username.isEmpty || password.isEmpty || isLoading)
                    }
                    .padding(.horizontal, 32)
                    .animation(.easeInOut, value: needsTOTP)

                    Spacer().frame(height: 40)

                    Button(L10n.t("login.choose_server", appLang)) {
                        appState.resetServer()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func login() async {
        isLoading = true
        error = ""
        defer { isLoading = false }

        do {
            let code = needsTOTP ? (totpCode.isEmpty ? nil : totpCode) : nil
            let result = try await CalendarrAPI.login(
                baseURL: appState.serverURL,
                username: username,
                password: password,
                totpCode: code,
                rememberMe: rememberMe
            )
            appState.saveLogin(token: result.token, user: result.username, admin: result.isAdmin)
        } catch APIError.twoFactorRequired {
            withAnimation { needsTOTP = true }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
