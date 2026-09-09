import Foundation

/// Keeps an SSO session alive without sending the user back through the browser.
///
/// Calendarr's own token has no refresh mechanism — it simply expires. What the
/// `offline_access` scope buys is a refresh token at the *identity provider*, so
/// renewal means: get a fresh ID token from the provider, then trade it for a
/// fresh Calendarr token at `/api/auth/oidc/exchange`.
@MainActor
enum OIDCSessionRefresher {

    /// Renew when less than this much of the Calendarr token's life is left.
    private static let renewWithin: TimeInterval = 24 * 60 * 60

    /// Best-effort renewal at launch. Any failure is swallowed: the existing
    /// token is still valid, and a hard failure would only surface later as a
    /// normal 401.
    static func refreshIfNeeded(_ appState: AppState) async {
        guard !appState.authToken.isEmpty,
              let providerKey = OIDCAuthenticator.storedProviderKey,
              expiresSoon(appState.authToken) else { return }

        do {
            let authenticator = OIDCAuthenticator()
            guard let renewed = try await authenticator.renewIDToken() else { return }

            let providers = try await CalendarrAPI.oidcProviders(baseURL: appState.serverURL)
            guard let provider = providers.first(where: { $0.key == providerKey }) else { return }

            let result = try await CalendarrAPI.exchangeOIDC(
                baseURL: appState.serverURL,
                provider: provider.key,
                clientID: provider.mobileClientID,
                idToken: renewed.idToken,
                accessToken: renewed.accessToken,
                nonce: renewed.nonce
            )
            appState.saveLogin(token: result.token, user: result.username, admin: result.isAdmin)
        } catch {
            // Nothing to do — keep using the token we have.
        }
    }

    /// True when the Calendarr JWT expires within [renewWithin].
    ///
    /// The payload is read without verifying the signature: this only decides
    /// *whether* to renew, and the server validates the token on every request
    /// regardless. A token we cannot parse is left alone.
    private static func expiresSoon(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return false }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Base64url drops the padding that Data(base64Encoded:) insists on.
        while payload.count % 4 != 0 { payload += "=" }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return false }

        return Date(timeIntervalSince1970: exp).timeIntervalSinceNow < renewWithin
    }
}
