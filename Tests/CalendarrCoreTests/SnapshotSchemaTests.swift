import Foundation
import Testing
@testable import CalendarrCore

/// The wire format is a contract between apps that ship independently, so both
/// directions of compatibility need a test: a new reader must understand an old
/// file, and an old reader must survive a new one.
struct SnapshotSchemaTests {

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }

    /// A real v1 file: no schemaVersion, no coverage window, no isLoggedIn,
    /// colours flat at the top level.
    private static let v1Fixture = """
    {
      "writtenAt": "2026-08-10T12:00:00Z",
      "events": [
        {
          "id": "abc",
          "title": "Zahnarzt",
          "start": "2026-08-11T09:00:00Z",
          "end": "2026-08-11T10:00:00Z",
          "isAllDay": false,
          "colorHex": "#58B900",
          "location": "Bern",
          "calendarKey": "local:3"
        }
      ],
      "todayColorHex": "#6FB669",
      "textColorHex": "#FFFFFF",
      "backgroundColorHex": "#000000",
      "lineColorHex": "#3B3B3D",
      "primaryColorHex": "#58B900",
      "accentColorHex": "#45A148",
      "language": "de"
    }
    """

    @Test("A v1 file decodes, and its missing fields get sane defaults")
    func decodesV1() throws {
        let snap = try Self.decoder().decode(
            CalendarrSnapshot.self, from: Data(Self.v1Fixture.utf8))

        #expect(snap.schemaVersion == 1)
        #expect(snap.events.count == 1)
        #expect(snap.events[0].calendarKey == "local:3")
        #expect(snap.language == "de")
        #expect(snap.theme.today == "#6FB669")
        #expect(snap.theme.accent == "#45A148")

        // v1 never said whether anyone was signed in; assuming yes preserves the
        // old behaviour of simply rendering whatever was cached.
        #expect(snap.isLoggedIn)
        #expect(snap.writerVersion == "unknown")

        // The window is reconstructed from the policy v1 always used.
        let cal = Calendar(identifier: .gregorian)
        let dayStart = cal.startOfDay(for: snap.writtenAt)
        #expect(snap.coverageStart == cal.date(byAdding: .day, value: -7, to: dayStart))
        #expect(snap.coverageEnd == cal.date(byAdding: .day, value: 42, to: dayStart))
    }

    /// Older still: written before per-calendar filtering existed, so the events
    /// carry no calendarKey at all.
    private static let v1FixtureNoCalendarKey = """
    {
      "writtenAt": "2026-08-10T12:00:00Z",
      "events": [
        {
          "id": "abc",
          "title": "Zahnarzt",
          "start": "2026-08-11T09:00:00Z",
          "end": "2026-08-11T10:00:00Z",
          "isAllDay": false,
          "colorHex": "#58B900",
          "location": "Bern"
        }
      ],
      "todayColorHex": "#6FB669",
      "textColorHex": "#FFFFFF",
      "backgroundColorHex": "#000000",
      "lineColorHex": "#3B3B3D",
      "language": "de"
    }
    """

    @Test("A v1 file that predates calendarKey and the newer colours still decodes")
    func decodesV1WithoutCalendarKey() throws {
        let snap = try Self.decoder().decode(
            CalendarrSnapshot.self, from: Data(Self.v1FixtureNoCalendarKey.utf8))
        #expect(snap.events[0].calendarKey == "")
        // primary/accent were added later too, so they fall back to defaults.
        #expect(snap.theme.primary == "#4285f4")
        #expect(snap.theme.accent == "#ea4335")
    }

    @Test("v2 round-trips without losing anything")
    func roundTripsV2() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let original = CalendarrSnapshot(
            writtenAt: start,
            coverageStart: start.addingTimeInterval(-7 * 86_400),
            coverageEnd: start.addingTimeInterval(42 * 86_400),
            isLoggedIn: true,
            writerVersion: "3.5",
            events: [SnapshotEvent(id: "x", title: "Termin", start: start,
                                   end: start.addingTimeInterval(3600),
                                   isAllDay: false, colorHex: "#58B900",
                                   location: "", calendarKey: "local:1")],
            theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                 line: "#4", primary: "#5", accent: "#6"),
            language: "ch")

        let decoded = try Self.decoder().decode(
            CalendarrSnapshot.self, from: Self.encoder().encode(original))

        #expect(decoded.schemaVersion == CalendarrSnapshot.currentSchema)
        #expect(decoded.writerVersion == "3.5")
        #expect(decoded.language == "ch")
        #expect(decoded.coverageStart == original.coverageStart)
        #expect(decoded.coverageEnd == original.coverageEnd)
        #expect(decoded.theme == original.theme)
        #expect(decoded.events == original.events)
    }

    /// The reason the colours are stored flat rather than nested under `theme`:
    /// a v1 reader requires them at the top level, so nesting them would have
    /// broken every older build on the first v2 write.
    @Test("v2 keeps the colour keys where a v1 reader expects them")
    func v2StaysReadableByV1() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let snap = CalendarrSnapshot(
            writtenAt: start, coverageStart: start, coverageEnd: start,
            isLoggedIn: true, writerVersion: "3.5", events: [],
            theme: SnapshotTheme(today: "#a", text: "#b", background: "#c",
                                 line: "#d", primary: "#e", accent: "#f"),
            language: "de")

        let object = try JSONSerialization.jsonObject(
            with: Self.encoder().encode(snap)) as? [String: Any]

        for key in ["todayColorHex", "textColorHex", "backgroundColorHex",
                    "lineColorHex", "primaryColorHex", "accentColorHex",
                    "writtenAt", "events", "language"] {
            #expect(object?[key] != nil, "v1 readers require \(key) at the top level")
        }
        #expect(object?["theme"] == nil, "theme must stay a computed view, not a stored key")
    }

    @Test("covers() separates 'no events' from 'no information'")
    func coverageWindow() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let snap = CalendarrSnapshot(
            writtenAt: now,
            coverageStart: now.addingTimeInterval(-86_400),
            coverageEnd: now.addingTimeInterval(86_400),
            isLoggedIn: true, writerVersion: "3.5", events: [],
            theme: SnapshotTheme(today: "", text: "", background: "",
                                 line: "", primary: "", accent: ""),
            language: "de")

        #expect(snap.covers(now))
        #expect(snap.covers(now.addingTimeInterval(-86_399)))
        #expect(!snap.covers(now.addingTimeInterval(-90_000)))
        #expect(!snap.covers(snap.coverageEnd))   // half-open: end is excluded
    }
}
