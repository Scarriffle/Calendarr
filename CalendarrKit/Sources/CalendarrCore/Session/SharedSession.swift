import Foundation

/// Non-secret session facts published alongside the snapshot.
///
/// This exists so a consumer can answer "which server, and is anyone signed in?"
/// without reading Calendarr's own `UserDefaults`, which lives in a different
/// sandbox. The auth token is deliberately *not* here — it belongs in the shared
/// keychain group, not in a plain file in the container.
public struct SharedSession: Codable, Sendable {
    public static let currentSchema = 1
    public static let maxSupportedSchema = 1

    public let schemaVersion: Int
    public let baseURL: String
    public let username: String
    public let isLoggedIn: Bool
    public let writtenAt: Date

    public init(baseURL: String, username: String, isLoggedIn: Bool, writtenAt: Date) {
        self.schemaVersion = Self.currentSchema
        self.baseURL = baseURL
        self.username = username
        self.isLoggedIn = isLoggedIn
        self.writtenAt = writtenAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        baseURL       = try c.decode(String.self, forKey: .baseURL)
        username      = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        isLoggedIn    = try c.decodeIfPresent(Bool.self, forKey: .isLoggedIn) ?? true
        writtenAt     = try c.decodeIfPresent(Date.self, forKey: .writtenAt) ?? Date(timeIntervalSince1970: 0)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, baseURL, username, isLoggedIn, writtenAt
    }

    /// The server URL as a `URL`, or nil when unset or malformed.
    public var url: URL? { baseURL.isEmpty ? nil : URL(string: baseURL) }
}

public struct SharedSessionStore: Sendable {
    private static let filename = "session.json"

    public let appGroupID: String

    public init(appGroupID: String = CalendarrAppGroup.current) {
        self.appGroupID = appGroupID
    }

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(Self.filename)
    }

    /// Nil when Calendarr has never published, or the file is unreadable or newer
    /// than this reader understands.
    public func read() -> SharedSession? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let session = try? decoder.decode(SharedSession.self, from: data),
              session.schemaVersion <= SharedSession.maxSupportedSchema else { return nil }
        return session
    }

    @_spi(Writer)
    public func write(_ session: SharedSession) throws {
        guard let url = fileURL else {
            throw SnapshotStoreError.containerUnavailable(appGroupID: appGroupID)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(session).write(to: url, options: .atomic)
    }

    @_spi(Writer)
    public func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
