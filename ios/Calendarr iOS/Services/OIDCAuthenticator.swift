import AppAuth
import Foundation
import UIKit

/// Redirect target for the SSO round-trip. Reverse-DNS on the bundle id, per
/// RFC 8252; the same value has to be registered in the identity provider.
///
/// It is deliberately not server-configurable: the app can only ever receive a
/// scheme it owns, so the provider has to be registered with this exact value.
///
/// No `CFBundleURLTypes` entry is needed on the normal path — AppAuth's iOS
/// user agent uses `ASWebAuthenticationSession`, which intercepts the callback
/// itself. See `guidedAccessBlocksLogin` for the one exception.
private let redirectURI = "com.scarriffleservices.calendarr.ios:/oauth2redirect"

/// Keychain key for the serialised `OIDAuthState` (contains the refresh token).
private let authStateKey = "oidcAuthState"
/// UserDefaults key for the provider that SSO session belongs to.
let oidcProviderDefaultsKey = "oidcProvider"

/// A provider offered by the Calendarr server (`GET /api/auth/oidc/providers`).
struct OIDCProvider: Identifiable, Equatable {
    let key: String
    let name: String
    let issuer: String
    /// Exactly what the server told us to request. The app must not add scopes
    /// of its own — one the provider does not know makes it reject the whole
    /// authorization request.
    let scopes: String
    let mobileClientID: String

    var id: String { key }
}

/// An SSO failure carrying the server's stable slug, which `LoginView` maps to
/// a translated message. `underlying` is for the log, never for the user.
struct OIDCError: LocalizedError {
    let slug: String
    var underlying: String?
    var errorDescription: String? { slug }
}

/// Result of a completed provider flow, ready to be exchanged with Calendarr.
struct OIDCTokens {
    let idToken: String
    let accessToken: String?
    let nonce: String?
    /// Serialised `OIDAuthState`, including the refresh token.
    let serialisedState: String?
}

/// Drives the OpenID Connect Authorization Code Flow with PKCE.
///
/// The login page always opens in `ASWebAuthenticationSession` (AppAuth's
/// default external user agent on iOS) — never in an embedded web view, so the
/// credentials stay in the browser's security context and the provider's own
/// session cookies keep working.
@MainActor
final class OIDCAuthenticator {

    /// AppAuth requires the in-flight session to stay alive for the round-trip.
    private var session: OIDExternalUserAgentSession?

    /// Under Guided Access, AppAuth falls back to `SFSafariViewController`,
    /// whose redirect can only come back through a registered URL scheme — and
    /// the app target generates its Info.plist, which has no way to declare
    /// `CFBundleURLTypes`. Rather than hang forever waiting for a callback that
    /// cannot arrive, refuse up front.
    var guidedAccessBlocksLogin: Bool { UIAccessibility.isGuidedAccessEnabled }

    func discover(issuer: String) async throws -> OIDServiceConfiguration {
        guard let url = URL(string: issuer) else { throw OIDCError(slug: "oidc_bad_issuer") }
        return try await withCheckedThrowingContinuation { cont in
            OIDAuthorizationService.discoverConfiguration(forIssuer: url) { config, error in
                if let config {
                    cont.resume(returning: config)
                } else {
                    cont.resume(throwing: OIDCError(slug: "oidc_provider_unreachable",
                                                    underlying: Self.describe(error)))
                }
            }
        }
    }

    /// Run the full flow and return the provider's tokens.
    ///
    /// `OIDAuthorizationRequest` generates state, nonce and the PKCE verifier
    /// itself. The nonce has to travel to our server with the ID token so it
    /// can verify the binding — this is the app's replay protection.
    func authorize(provider: OIDCProvider) async throws -> OIDCTokens {
        if guidedAccessBlocksLogin { throw OIDCError(slug: "oidc_guided_access") }

        let config = try await discover(issuer: provider.issuer)

        var scopes = provider.scopes
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        if !scopes.contains(OIDScopeOpenID) { scopes.append(OIDScopeOpenID) }

        guard let redirectURL = URL(string: redirectURI) else {
            throw OIDCError(slug: "oidc_bad_redirect")
        }

        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: provider.mobileClientID,
            clientSecret: nil,          // public client — never send a secret
            scopes: scopes,
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        guard let presenter = Self.topViewController() else {
            throw OIDCError(slug: "oidc_no_presenter")
        }

        // Clear the retained session on every exit, not just the happy one.
        defer { session = nil }

        let authState: OIDAuthState = try await withCheckedThrowingContinuation { cont in
            session = OIDAuthState.authState(byPresenting: request,
                                             presenting: presenter) { state, error in
                if let state {
                    cont.resume(returning: state)
                } else if Self.isCancellation(error) {
                    cont.resume(throwing: OIDCError(slug: "oidc_cancelled"))
                } else {
                    cont.resume(throwing: OIDCError(slug: "oidc_failed",
                                                    underlying: Self.describe(error)))
                }
            }
        }

        guard let idToken = authState.lastTokenResponse?.idToken else {
            throw OIDCError(slug: "oidc_no_id_token")
        }

        return OIDCTokens(
            idToken: idToken,
            accessToken: authState.lastTokenResponse?.accessToken,
            nonce: request.nonce,
            serialisedState: Self.serialise(authState)
        )
    }

    // MARK: - Silent renewal

    /// Ask the provider for a fresh ID token using the stored refresh token.
    ///
    /// Returns nil when there is no SSO session to renew. The refreshed state
    /// is written back, because the provider may have rotated the refresh
    /// token.
    func renewIDToken() async throws -> (idToken: String, accessToken: String?, nonce: String?)? {
        guard let stored = try? KeychainStore.get(authStateKey),
              let state = Self.deserialise(stored) else { return nil }

        let tokens: (String?, String?) = try await withCheckedThrowingContinuation { cont in
            state.performAction { accessToken, idToken, error in
                if let error {
                    cont.resume(throwing: OIDCError(slug: "oidc_refresh_failed",
                                                    underlying: Self.describe(error)))
                } else {
                    cont.resume(returning: (idToken, accessToken))
                }
            }
        }

        guard let idToken = tokens.0 else { return nil }
        if let refreshed = Self.serialise(state) {
            try? KeychainStore.set(refreshed, for: authStateKey)
        }
        // The original request travels inside the stored state, so the nonce
        // is still available. A refreshed token often drops the claim, which
        // the server tolerates — but when it keeps it, it has to match.
        let nonce = state.lastAuthorizationResponse.request.nonce
        return (idToken, tokens.1, nonce)
    }

    /// Persist the SSO session so it can be renewed without another browser trip.
    static func store(state: String?, providerKey: String) {
        guard let state else { return }
        try? KeychainStore.set(state, for: authStateKey)
        UserDefaults.standard.set(providerKey, forKey: oidcProviderDefaultsKey)
    }

    /// The provider key of the active SSO session, if any.
    static var storedProviderKey: String? {
        UserDefaults.standard.string(forKey: oidcProviderDefaultsKey)
    }

    static func clearStoredSession() {
        try? KeychainStore.set(nil, for: authStateKey)
        // Mirror the authToken handling: a pre-entitlement copy may exist in
        // the app's own keychain group.
        try? KeychainStore.set(nil, for: authStateKey, accessGroup: nil)
        UserDefaults.standard.removeObject(forKey: oidcProviderDefaultsKey)
    }

    // MARK: - Helpers

    private static func serialise(_ state: OIDAuthState) -> String? {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: state,
                                                        requiringSecureCoding: true)
            return data.base64EncodedString()
        } catch {
            log("archiving OIDAuthState failed: \(error)")
            return nil
        }
    }

    private static func deserialise(_ raw: String) -> OIDAuthState? {
        guard let data = Data(base64Encoded: raw) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data)
    }

    /// AppAuth reports both a user-initiated and a programmatic cancel; neither
    /// is a failure worth showing. Checking the domain as well as the code
    /// avoids matching an unrelated error that happens to share the number.
    private static func isCancellation(_ error: Error?) -> Bool {
        guard let ns = error as NSError? else { return false }
        guard ns.domain == OIDGeneralErrorDomain else { return false }
        return ns.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue
            || ns.code == OIDErrorCode.programCanceledAuthorizationFlow.rawValue
    }

    /// Detail for the log only — never shown to the user.
    private static func describe(_ error: Error?) -> String? {
        guard let ns = error as NSError? else { return nil }
        let oauth = ns.userInfo[OIDOAuthErrorResponseErrorKey] as? [String: Any]
        let detail = (oauth?["error"] as? String).map { " oauth=\($0)" } ?? ""
        let text = "\(ns.domain)/\(ns.code): \(ns.localizedDescription)\(detail)"
        log(text)
        return text
    }

    private static func log(_ message: String) {
        #if DEBUG
        print("[OIDC] \(message)")
        #endif
    }

    /// Topmost view controller to present the browser sheet from. Works under
    /// Mac Catalyst too, where a presentation anchor is likewise required.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
