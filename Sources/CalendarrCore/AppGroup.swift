import Foundation

/// The App Group the Calendarr apps share.
///
/// The identifier registered in the Apple Developer portal never changes. What
/// changes is the string the *runtime* expects: macOS — including Mac Catalyst —
/// requires the Team ID prefix, and iOS forbids it.
///
/// Getting this wrong fails silently. `containerURL(forSecurityApplication‑
/// GroupIdentifier:)` returns nil, every read and write no-ops, and widgets show
/// placeholder content forever with no error raised anywhere. `current` must
/// therefore stay byte-identical to `com.apple.security.application-groups` in
/// the entitlements file used for the platform being built.
public enum CalendarrAppGroup {
    /// As registered in the Apple Developer portal.
    public static let unprefixed = "group.com.scarriffleservices.calendarr"

    /// Team ID — the value `$(AppIdentifierPrefix)` expands to at build time.
    public static let teamID = "PP34X97WS3"

    /// The value to hand to `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`.
    #if os(macOS) || targetEnvironment(macCatalyst)
    public static let current = "\(teamID).\(unprefixed)"
    #else
    public static let current = unprefixed
    #endif

    /// Keychain access group shared across apps from this team. Requires
    /// `keychain-access-groups` in the entitlements of every app that uses it.
    public static let sharedKeychainGroup = "\(teamID).com.scarriffleservices.calendarr.shared"
}
