import Foundation

public enum SnapshotStoreError: Error, LocalizedError {
    case containerUnavailable(appGroupID: String)

    public var errorDescription: String? {
        switch self {
        case .containerUnavailable(let id):
            return "App Group container unavailable for \(id). Check that "
                 + "com.apple.security.application-groups in this target's "
                 + "entitlements matches exactly, and that macOS builds use the "
                 + "Team ID prefix."
        }
    }
}

/// Reads — and, for Calendarr itself, writes — the shared calendar snapshot.
///
/// Writing is gated behind `@_spi(Writer)` so a read-only consumer cannot
/// corrupt the shared cache even by accident. Calendarr imports the package as
/// `@_spi(Writer) import CalendarrCore`; everyone else gets read access only.
public struct SnapshotStore: Sendable {
    private static let cacheFilename     = "widget-cache.json"
    private static let calendarsFilename = "widget-calendars.json"

    public let appGroupID: String

    public init(appGroupID: String = CalendarrAppGroup.current) {
        self.appGroupID = appGroupID
    }

    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Reading

    /// Load the published snapshot.
    ///
    /// Never returns a bare nil: every failure mode is named, because they call
    /// for different things in the UI and because a silent nil is precisely how
    /// a misconfigured App Group used to hide itself.
    public func read() -> SnapshotReadResult {
        guard let container = containerURL else {
            return .unreadable(SnapshotStoreError
                .containerUnavailable(appGroupID: appGroupID).localizedDescription)
        }
        let url = container.appendingPathComponent(Self.cacheFilename)

        guard FileManager.default.fileExists(atPath: url.path) else { return .neverWritten }

        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { return .unreadable("Could not read \(Self.cacheFilename): \(error.localizedDescription)") }

        // Check the version before decoding: a newer writer may have changed the
        // meaning of a field we think we understand, so refusing beats guessing.
        if let probe = try? Self.decoder().decode(SchemaProbe.self, from: data) {
            let found = probe.schemaVersion ?? 1
            if found > CalendarrSnapshot.maxSupportedSchema {
                return .incompatible(foundSchema: found,
                                     maxSupported: CalendarrSnapshot.maxSupportedSchema)
            }
        }

        do {
            let snapshot = try Self.decoder().decode(CalendarrSnapshot.self, from: data)
            guard snapshot.isLoggedIn else { return .loggedOut(writtenAt: snapshot.writtenAt) }
            return .ok(snapshot)
        } catch {
            return .unreadable("Could not decode \(Self.cacheFilename): \(error)")
        }
    }

    /// The calendars available for filtering. Empty when nothing is published.
    public func readCalendars() -> [SnapshotCalendar] {
        guard let url = containerURL?.appendingPathComponent(Self.calendarsFilename),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? Self.decoder().decode([SnapshotCalendar].self, from: data)) ?? []
    }

    /// Reads only the version field, so an unsupported file is never fully decoded.
    private struct SchemaProbe: Decodable { let schemaVersion: Int? }

    // MARK: - Writing (Calendarr only)

    @_spi(Writer)
    public func write(_ snapshot: CalendarrSnapshot) throws {
        guard let container = containerURL else {
            throw SnapshotStoreError.containerUnavailable(appGroupID: appGroupID)
        }
        let data = try Self.encoder().encode(snapshot)
        try data.write(to: container.appendingPathComponent(Self.cacheFilename), options: .atomic)
        SnapshotChangeNotifier.post()
    }

    @_spi(Writer)
    public func writeCalendars(_ calendars: [SnapshotCalendar]) throws {
        guard let container = containerURL else {
            throw SnapshotStoreError.containerUnavailable(appGroupID: appGroupID)
        }
        let data = try Self.encoder().encode(calendars)
        try data.write(to: container.appendingPathComponent(Self.calendarsFilename), options: .atomic)
    }

    /// Remove everything published. Call this on sign-out and on server reset —
    /// the container outlives the session, so without it the next reader keeps
    /// rendering the previous user's calendar.
    @_spi(Writer)
    public func clear() {
        guard let container = containerURL else { return }
        for name in [Self.cacheFilename, Self.calendarsFilename] {
            try? FileManager.default.removeItem(at: container.appendingPathComponent(name))
        }
        SnapshotChangeNotifier.post()
    }
}
