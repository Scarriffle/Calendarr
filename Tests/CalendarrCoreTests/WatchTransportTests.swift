import Foundation
import Testing
@testable import CalendarrCore

/// The phone and the watch ship on independent schedules, so the transport gets
/// the same treatment as the file format: refuse a newer schema rather than
/// mis-decode it.
struct WatchTransportTests {

    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    private static func snapshot() -> CalendarrSnapshot {
        CalendarrSnapshot(writtenAt: now,
                          coverageStart: now.addingTimeInterval(-86400),
                          coverageEnd: now.addingTimeInterval(14 * 86400),
                          isLoggedIn: true, writerVersion: "1.2",
                          events: [SnapshotEvent(id: "a", title: "Zahnarzt",
                                                 start: now.addingTimeInterval(3600),
                                                 end: now.addingTimeInterval(7200),
                                                 isAllDay: false, colorHex: "#4285f4",
                                                 location: "Bern", calendarKey: "local:3")],
                          theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                               line: "#4", primary: "#5", accent: "#6"),
                          language: "de")
    }

    @Test("A payload survives a round trip")
    func roundTrips() throws {
        let payload = WatchTransportPayload(
            snapshot: Self.snapshot(),
            calendars: [SnapshotCalendar(id: "local:3", name: "Privat", colorHex: "#4285f4")],
            session: SharedSession(baseURL: "https://cal.example.com", username: "guido",
                                   isLoggedIn: true, writtenAt: Self.now))

        let decoded = try WatchTransportPayload.decode(try payload.encoded())

        #expect(decoded.snapshot.events.map(\.id) == ["a"])
        #expect(decoded.snapshot.language == "de")
        #expect(decoded.calendars.map(\.name) == ["Privat"])
        #expect(decoded.session?.username == "guido")
    }

    @Test("A payload with no session record still decodes")
    func sessionIsOptional() throws {
        let payload = WatchTransportPayload(snapshot: Self.snapshot(), calendars: [], session: nil)
        let decoded = try WatchTransportPayload.decode(try payload.encoded())

        #expect(decoded.session == nil)
        #expect(decoded.calendars.isEmpty)
    }

    @Test("The encoded form only contains property-list types")
    func encodesToPlistTypes() throws {
        let dict = try WatchTransportPayload(snapshot: Self.snapshot(), calendars: [], session: nil).encoded()

        #expect(dict[WatchTransportKey.schema] is Int)
        #expect(dict[WatchTransportKey.snapshot] is Data)
        #expect(PropertyListSerialization.propertyList(dict, isValidFor: .binary))
    }

    @Test("A newer schema is refused rather than guessed at")
    func refusesNewerSchema() throws {
        var dict = try WatchTransportPayload(snapshot: Self.snapshot(), calendars: [], session: nil).encoded()
        dict[WatchTransportKey.schema] = WatchTransportPayload.maxSupportedSchema + 1

        #expect(throws: WatchTransportError.unsupportedSchema(
            found: WatchTransportPayload.maxSupportedSchema + 1,
            maxSupported: WatchTransportPayload.maxSupportedSchema)) {
            try WatchTransportPayload.decode(dict)
        }
    }

    @Test("A payload without a snapshot is rejected")
    func rejectsMissingSnapshot() {
        let dict: [String: Any] = [WatchTransportKey.schema: WatchTransportPayload.currentSchema]

        #expect(throws: WatchTransportError.missingSnapshot) {
            try WatchTransportPayload.decode(dict)
        }
    }
}
