import Foundation
import Testing
@testable import CalendarrCore

struct ComplicationTimelineTests {

    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    private static func event(_ id: String, startOffset: TimeInterval,
                              duration: TimeInterval) -> SnapshotEvent {
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

    @Test("The first entry is always now, so the complication renders immediately")
    func startsAtNow() {
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: Self.snapshot([]))
        #expect(dates.first == Self.now)
    }

    @Test("Entries are sorted and free of duplicates")
    func sortedAndDeduplicated() {
        let snap = Self.snapshot([Self.event("a", startOffset: 3600, duration: 1800),
                                  Self.event("b", startOffset: 5400, duration: 1800)])
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: snap)

        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
    }

    @Test("Event starts and ends inside the horizon become entries")
    func includesEventBoundaries() {
        let snap = Self.snapshot([Self.event("a", startOffset: 3600, duration: 1800)])
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: snap)

        #expect(dates.contains(Self.now.addingTimeInterval(3600)))
        #expect(dates.contains(Self.now.addingTimeInterval(5400)))
    }

    @Test("Boundaries outside the horizon are ignored")
    func ignoresBoundariesBeyondHorizon() {
        let snap = Self.snapshot([Self.event("far", startOffset: 40 * 3600, duration: 1800)])
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: snap, horizon: 24 * 3600)

        #expect(dates.contains(Self.now.addingTimeInterval(40 * 3600)) == false)
        #expect(dates.allSatisfy { $0 <= Self.now.addingTimeInterval(24 * 3600) })
    }

    @Test("Boundaries already in the past are ignored")
    func ignoresPastBoundaries() {
        let snap = Self.snapshot([Self.event("past", startOffset: -7200, duration: 1800)])
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: snap)

        #expect(dates.allSatisfy { $0 >= Self.now })
    }

    @Test("An empty calendar still gets hourly entries across the horizon")
    func fillsHourlyWhenEmpty() {
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: Self.snapshot([]),
                                                    horizon: 24 * 3600)
        #expect(dates.count >= 24)
    }

    @Test("The first hour gets minute-granular entries, so a compact countdown stays honest")
    func minuteGranularFirstHour() {
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: Self.snapshot([]))
        let firstHour = dates.filter { $0 <= Self.now.addingTimeInterval(3600) }

        // 60 minute marks plus `now` itself.
        #expect(firstHour.count >= 60)
        #expect(firstHour.contains(Self.now.addingTimeInterval(60)))
        #expect(firstHour.contains(Self.now.addingTimeInterval(1800)))
    }

    @Test("Past the first hour the entries thin out to hourly")
    func hourlyAfterFirstHour() {
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: Self.snapshot([]))
        let later = dates.filter { $0 > Self.now.addingTimeInterval(3600) }

        // 23 further hours, not 23 * 60 minutes.
        #expect(later.count < 40)
        #expect(later.contains(Self.now.addingTimeInterval(2 * 3600)))
    }

    @Test("The entry count is capped, keeping the earliest entries")
    func capsEntries() {
        var events: [SnapshotEvent] = []
        for i in 0..<300 {
            events.append(Self.event("e\(i)", startOffset: Double(i) * 60, duration: 30))
        }
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: Self.snapshot(events),
                                                    maxEntries: 50)

        #expect(dates.count == 50)
        #expect(dates.first == Self.now)
        #expect(dates == dates.sorted())
    }
}
