import Foundation
import Testing
@testable import CalendarrCore

/// The watch payload is a narrower snapshot, not a different one. These tests
/// pin down the part that is easy to get wrong: the coverage window has to
/// shrink with the events, or the watch renders an empty week it knows nothing
/// about.
struct WatchTrimmingTests {

    private static let cal = Calendar(identifier: .gregorian)
    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    private static func event(_ id: String, dayOffset: Int, hour: Int = 9) -> SnapshotEvent {
        let dayStart = cal.startOfDay(for: now)
        let day = cal.date(byAdding: .day, value: dayOffset, to: dayStart)!
        let start = cal.date(byAdding: .hour, value: hour, to: day)!
        return SnapshotEvent(id: id, title: "Event \(id)",
                             start: start, end: start.addingTimeInterval(3600),
                             isAllDay: false, colorHex: "#4285f4",
                             location: "", calendarKey: "local:1")
    }

    private static func snapshot(_ events: [SnapshotEvent]) -> CalendarrSnapshot {
        let dayStart = cal.startOfDay(for: now)
        return CalendarrSnapshot(
            writtenAt: now,
            coverageStart: cal.date(byAdding: .day, value: -SnapshotCoverage.daysBehind, to: dayStart)!,
            coverageEnd: cal.date(byAdding: .day, value: SnapshotCoverage.daysAhead, to: dayStart)!,
            isLoggedIn: true,
            writerVersion: "1.0",
            events: events,
            theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                 line: "#4", primary: "#5", accent: "#6"),
            language: "de")
    }

    @Test("The window narrows to the watch policy, not just the events")
    func narrowsWindow() {
        let trimmed = Self.snapshot([]).trimmedForWatch(now: Self.now, calendar: Self.cal)
        let dayStart = Self.cal.startOfDay(for: Self.now)

        #expect(trimmed.coverageStart == Self.cal.date(byAdding: .day, value: -WatchCoverage.daysBehind, to: dayStart))
        #expect(trimmed.coverageEnd == Self.cal.date(byAdding: .day, value: WatchCoverage.daysAhead, to: dayStart))
    }

    @Test("Events outside the watch window are dropped")
    func dropsEventsOutsideWindow() {
        let inside = Self.event("in", dayOffset: 3)
        let outside = Self.event("out", dayOffset: 30)
        let trimmed = Self.snapshot([inside, outside]).trimmedForWatch(now: Self.now, calendar: Self.cal)

        #expect(trimmed.events.map(\.id) == ["in"])
    }

    @Test("An event still running at the window start is kept")
    func keepsRunningEvent() {
        let dayStart = Self.cal.startOfDay(for: Self.now)
        let start = Self.cal.date(byAdding: .day, value: -5, to: dayStart)!
        let running = SnapshotEvent(id: "running", title: "Urlaub",
                                    start: start,
                                    end: Self.cal.date(byAdding: .day, value: 5, to: dayStart)!,
                                    isAllDay: true, colorHex: "#4285f4",
                                    location: "", calendarKey: "local:1")
        let trimmed = Self.snapshot([running]).trimmedForWatch(now: Self.now, calendar: Self.cal)

        #expect(trimmed.events.map(\.id) == ["running"])
    }

    @Test("Metadata survives trimming unchanged")
    func preservesMetadata() {
        let original = Self.snapshot([Self.event("a", dayOffset: 1)])
        let trimmed = original.trimmedForWatch(now: Self.now, calendar: Self.cal)

        #expect(trimmed.language == "de")
        #expect(trimmed.isLoggedIn == true)
        #expect(trimmed.writerVersion == "1.0")
        #expect(trimmed.theme.accent == "#6")
        #expect(trimmed.writtenAt == original.writtenAt)
        #expect(trimmed.schemaVersion == CalendarrSnapshot.currentSchema)
    }

    @Test("When the event cap truncates, coverageEnd pulls back to what we can prove")
    func capPullsBackCoverage() {
        var many: [SnapshotEvent] = []
        for day in 0..<14 {
            for hour in 8..<18 { many.append(Self.event("d\(day)h\(hour)", dayOffset: day, hour: hour)) }
        }
        #expect(many.count > WatchCoverage.maxEvents)

        let trimmed = Self.snapshot(many).trimmedForWatch(now: Self.now, calendar: Self.cal)

        #expect(trimmed.events.count <= WatchCoverage.maxEvents)
        #expect(trimmed.events.allSatisfy { $0.start < trimmed.coverageEnd })
        let dayStart = Self.cal.startOfDay(for: Self.now)
        let fullEnd = Self.cal.date(byAdding: .day, value: WatchCoverage.daysAhead, to: dayStart)!
        #expect(trimmed.coverageEnd < fullEnd)
        #expect(trimmed.coverageEnd > trimmed.coverageStart)
    }

    @Test("Trimming never widens a window the writer already narrowed")
    func neverWidens() {
        let dayStart = Self.cal.startOfDay(for: Self.now)
        let narrow = CalendarrSnapshot(
            writtenAt: Self.now,
            coverageStart: dayStart,
            coverageEnd: Self.cal.date(byAdding: .day, value: 2, to: dayStart)!,
            isLoggedIn: true, writerVersion: "1.0", events: [],
            theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                 line: "#4", primary: "#5", accent: "#6"),
            language: "de")

        let trimmed = narrow.trimmedForWatch(now: Self.now, calendar: Self.cal)

        #expect(trimmed.coverageStart == dayStart)
        #expect(trimmed.coverageEnd == Self.cal.date(byAdding: .day, value: 2, to: dayStart))
    }
}
