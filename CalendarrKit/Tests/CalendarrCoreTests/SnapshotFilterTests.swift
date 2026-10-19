import Foundation
import Testing
@testable import CalendarrCore

struct SnapshotFilterTests {

    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    private static func event(_ id: String, key: String) -> SnapshotEvent {
        SnapshotEvent(id: id, title: id, start: now, end: now.addingTimeInterval(3600),
                      isAllDay: false, colorHex: "#4285f4", location: "", calendarKey: key)
    }

    private static func snapshot(_ events: [SnapshotEvent]) -> CalendarrSnapshot {
        CalendarrSnapshot(writtenAt: now,
                          coverageStart: now.addingTimeInterval(-86400),
                          coverageEnd: now.addingTimeInterval(86400),
                          isLoggedIn: true, writerVersion: "1.0", events: events,
                          theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                               line: "#4", primary: "#5", accent: "#6"),
                          language: "de")
    }

    @Test("An empty allow-list means every calendar, not no calendar")
    func emptyAllowListKeepsEverything() {
        let snap = Self.snapshot([Self.event("a", key: "local:1"), Self.event("b", key: "caldav:2")])
        #expect(snap.filtered(toCalendarKeys: []).events.count == 2)
    }

    @Test("An allow-list keeps only the listed calendars")
    func allowListNarrows() {
        let snap = Self.snapshot([Self.event("a", key: "local:1"), Self.event("b", key: "caldav:2")])
        #expect(snap.filtered(toCalendarKeys: ["local:1"]).events.map(\.id) == ["a"])
    }

    @Test("A deny-list removes only the listed calendars")
    func denyListNarrows() {
        let snap = Self.snapshot([Self.event("a", key: "local:1"), Self.event("b", key: "caldav:2")])
        #expect(snap.filtered(excludingCalendarKeys: ["local:1"]).events.map(\.id) == ["b"])
    }

    @Test("Filtering narrows the events but never the window")
    func windowIsUntouched() {
        let snap = Self.snapshot([Self.event("a", key: "local:1")])
        let filtered = snap.filtered(toCalendarKeys: ["nothing:0"])

        #expect(filtered.events.isEmpty)
        #expect(filtered.coverageStart == snap.coverageStart)
        #expect(filtered.coverageEnd == snap.coverageEnd)
    }
}
