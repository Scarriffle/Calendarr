import Foundation
import Security

/// Keychain access for secrets (currently just the auth bearer token).
///
/// This replaces the earlier `enum Keychain`, which discarded every `OSStatus`.
/// That mattered more than it looks: on Mac Catalyst a missing
/// `keychain-access-groups` entitlement makes `SecItemAdd`/`SecItemCopyMatching`
/// fail with `errSecMissingEntitlement`, and because nothing checked the status
/// the result was indistinguishable from "no token stored" — the user was
/// silently signed out on every launch.
///
/// Items live in a shared access group so the Mac build and other apps from the
/// same team can read the token. Reading requires `keychain-access-groups` in
/// the entitlements listing `sharedAccessGroup`.
enum KeychainStore {
    /// Access group shared across our apps. Must match an entry in the
    /// `keychain-access-groups` entitlement of every app that uses it.
    /// The `PP34X97WS3.` prefix is this account's Team ID — the same value
    /// `$(AppIdentifierPrefix)` expands to at build time.
    static let sharedAccessGroup = "PP34X97WS3.com.scarriffleservices.calendarr.shared"

    private static let service = "Calendarr"

    /// Set when a keychain call failed because the entitlement was missing and
    /// we fell back to the app's own default access group. Signing is a build
    /// configuration concern, so in DEBUG we make it loud; in release we keep
    /// working rather than locking the user out of their own account.
    private(set) nonisolated(unsafe) static var didFallBackToDefaultGroup = false

    // MARK: - Public API

    /// Store or delete a value. Passing `nil` deletes it.
    static func set(_ value: String?, for key: String,
                    accessGroup: String? = sharedAccessGroup) throws {
        do {
            try write(value, key: key, accessGroup: accessGroup)
        } catch KeychainError.status(errSecMissingEntitlement, _) where accessGroup != nil {
            noteEntitlementFallback()
            try write(value, key: key, accessGroup: nil)
        }
    }

    /// Read a value. Returns `nil` when the item simply is not there;
    /// throws when the keychain itself refused the request.
    static func get(_ key: String, accessGroup: String? = sharedAccessGroup) throws -> String? {
        do {
            return try read(key: key, accessGroup: accessGroup)
        } catch KeychainError.status(errSecMissingEntitlement, _) where accessGroup != nil {
            noteEntitlementFallback()
            return try read(key: key, accessGroup: nil)
        }
    }

    // MARK: - Implementation

    private static func baseQuery(key: String, accessGroup: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            // Selects the modern, entitlement-gated keychain on macOS/Catalyst
            // instead of the legacy file-based login keychain. Documented no-op
            // on iOS 13+, so it is safe to set unconditionally.
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    private static func write(_ value: String?, key: String, accessGroup: String?) throws {
        let base = baseQuery(key: key, accessGroup: accessGroup)

        let deleteStatus = SecItemDelete(base as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.status(deleteStatus, operation: "delete \(key)")
        }

        guard let value, let data = value.data(using: .utf8) else { return }

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.status(addStatus, operation: "add \(key)")
        }
    }

    private static func read(key: String, accessGroup: String?) throws -> String? {
        var query = baseQuery(key: key, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            guard let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status, operation: "read \(key)")
        }
    }

    private static func noteEntitlementFallback() {
        guard !didFallBackToDefaultGroup else { return }
        didFallBackToDefaultGroup = true
        assertionFailure("""
            Keychain access group \(sharedAccessGroup) was refused \
            (errSecMissingEntitlement). Add it to keychain-access-groups and \
            enable Keychain Sharing on the App ID. Falling back to the app's \
            own default group — the Mac app will not see this token.
            """)
    }
}

enum KeychainError: Error, LocalizedError {
    case status(OSStatus, operation: String)

    var errorDescription: String? {
        switch self {
        case let .status(status, operation):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain \(operation) failed: \(detail)"
        }
    }
}
