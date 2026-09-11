import Foundation

/// Dictionary keys used on the WatchConnectivity wire. Stable within a major
/// version, like the snapshot filenames.
public enum WatchTransportKey {
    public static let schema    = "schema"
    public static let snapshot  = "snapshot"
    public static let calendars = "calendars"
    public static let session   = "session"
}

public enum WatchTransportError: Error, Equatable, LocalizedError {
    case missingSnapshot
    case unsupportedSchema(found: Int, maxSupported: Int)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .missingSnapshot:
            return "Watch payload carried no snapshot."
        case .unsupportedSchema(let found, let max):
            return "Watch payload schema \(found) is newer than this build understands (\(max))."
        case .malformed(let why):
            return "Watch payload could not be decoded: \(why)"
        }
    }
}

/// What the phone sends to the watch: a trimmed snapshot, the calendar list for
/// a filter UI, and the non-secret session facts so the watch can tell "signed
/// out" from "never received anything".
///
/// The auth token is deliberately absent. The watch never talks to the server,
/// so there is nothing for it to authenticate with and nothing to leak.
public struct WatchTransportPayload: Sendable {
    /// Bump only for a breaking change to the dictionary shape.
    public static let currentSchema = 1
    /// Payloads claiming a higher schema are refused rather than mis-decoded.
    public static let maxSupportedSchema = 1

    public let snapshot: CalendarrSnapshot
    public let calendars: [SnapshotCalendar]
    public let session: SharedSession?

    public init(snapshot: CalendarrSnapshot,
                calendars: [SnapshotCalendar],
                session: SharedSession?) {
        self.snapshot = snapshot
        self.calendars = calendars
        self.session = session
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    /// Encode for `WCSession`. Values are `Data` and `Int` only, because
    /// WatchConnectivity accepts property-list types and rejects everything
    /// else at runtime rather than at compile time.
    public func encoded() throws -> [String: Any] {
        let e = Self.encoder()
        var dict: [String: Any] = [
            WatchTransportKey.schema: Self.currentSchema,
            WatchTransportKey.snapshot: try e.encode(snapshot),
            WatchTransportKey.calendars: try e.encode(calendars),
        ]
        if let session { dict[WatchTransportKey.session] = try e.encode(session) }
        return dict
    }

    public static func decode(_ dict: [String: Any]) throws -> WatchTransportPayload {
        let found = dict[WatchTransportKey.schema] as? Int ?? 1
        guard found <= maxSupportedSchema else {
            throw WatchTransportError.unsupportedSchema(found: found, maxSupported: maxSupportedSchema)
        }
        guard let snapshotData = dict[WatchTransportKey.snapshot] as? Data else {
            throw WatchTransportError.missingSnapshot
        }

        let d = decoder()
        let snapshot: CalendarrSnapshot
        do { snapshot = try d.decode(CalendarrSnapshot.self, from: snapshotData) }
        catch { throw WatchTransportError.malformed("snapshot: \(error)") }

        var calendars: [SnapshotCalendar] = []
        if let data = dict[WatchTransportKey.calendars] as? Data {
            calendars = (try? d.decode([SnapshotCalendar].self, from: data)) ?? []
        }

        var session: SharedSession?
        if let data = dict[WatchTransportKey.session] as? Data {
            session = try? d.decode(SharedSession.self, from: data)
        }

        return WatchTransportPayload(snapshot: snapshot, calendars: calendars, session: session)
    }
}
