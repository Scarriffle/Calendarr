import Foundation
import Testing
@testable import CalendarrCore

struct WatchPushPolicyTests {

    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    private static func event(_ id: String, startOffset: TimeInterval,
                              duration: TimeInterval = 3600) -> SnapshotEvent {
        SnapshotEvent(id: id, title: id,
                      start: now.addingTimeInterval(startOffset),
                      end: now.addingTimeInterval(startOffset + duration),
                      isAllDay: false, colorHex: "#4285f4", location: "", calendarKey: "local:1")
    }

    private static func snapshot(_ events: [SnapshotEvent]) -> CalendarrSnapshot {
        CalendarrSnapshot(writtenAt: now,
                          coverageStart: now.addingTimeInterval(-86400),
                          coverageEnd: now.addingTimeInterval(14 * 86400),
                          isLoggedIn: true, writerVersion: "1.0", events: events,
                          theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                               line: "#4", primary: "#5", accent: "#6"),
                          language: "de")
    }

    @Test("The next event is the first one that has not ended yet")
    func picksFirstUnfinished() {
        let snap = Self.snapshot([Self.event("past", startOffset: -7200),
                                  Self.event("running", startOffset: -600),
                                  Self.event("later", startOffset: 3600)])

        #expect(WatchPushPolicy.nextEventIdentity(in: snap, at: Self.now)?.id == "running")
    }

    @Test("An empty calendar has no next event")
    func emptyHasNoIdentity() {
        #expect(WatchPushPolicy.nextEventIdentity(in: Self.snapshot([]), at: Self.now) == nil)
    }

    @Test("Events are considered in start order regardless of input order")
    func sortsBeforePicking() {
        let snap = Self.snapshot([Self.event("late", startOffset: 7200),
                                  Self.event("soon", startOffset: 1800)])

        #expect(WatchPushPolicy.nextEventIdentity(in: snap, at: Self.now)?.id == "soon")
    }

    @Test("An unchanged next event does not spend a push")
    func unchangedDoesNotPush() {
        let identity = NextEventIdentity(id: "a", start: Self.now)
        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: identity, current: identity) == false)
    }

    @Test("A different event, a moved event, or a first event all spend a push")
    func changesPush() {
        let a = NextEventIdentity(id: "a", start: Self.now)
        let b = NextEventIdentity(id: "b", start: Self.now)
        let moved = NextEventIdentity(id: "a", start: Self.now.addingTimeInterval(600))

        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: a, current: b))
        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: a, current: moved))
        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: nil, current: a))
    }

    @Test("Losing the last event spends a push, so the watch stops showing it")
    func clearingPushes() {
        let a = NextEventIdentity(id: "a", start: Self.now)
        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: a, current: nil))
    }

    @Test("Two empty calendars in a row do not push")
    func stayingEmptyDoesNotPush() {
        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: nil, current: nil) == false)
    }
}
