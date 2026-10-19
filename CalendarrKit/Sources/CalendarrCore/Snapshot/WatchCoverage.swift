import Foundation

/// How much of the calendar travels to the watch.
///
/// Deliberately narrower than `SnapshotCoverage`: the payload crosses
/// WatchConnectivity on every publish, and a watch complication never needs six
/// weeks of history to answer "what is next".
public enum WatchCoverage {
    /// Days before today. One is enough for "still running" all-day events.
    public static let daysBehind = 1
    /// Days after today.
    public static let daysAhead = 14
    /// Hard cap on events sent, applied after sorting by start date.
    public static let maxEvents = 120
}

extension CalendarrSnapshot {
    /// A narrower copy of this snapshot, suitable for sending to the watch.
    ///
    /// The coverage window shrinks together with the events, and never widens
    /// past what the writer already claimed. If `WatchCoverage.maxEvents`
    /// truncates the list, `coverageEnd` is pulled back to the first event we
    /// had to drop: everything before that point is provably complete, and
    /// beyond it the watch must not pretend to know anything.
    public func trimmedForWatch(now: Date = Date(),
                                calendar: Calendar = Calendar(identifier: .gregorian)) -> CalendarrSnapshot {
        let dayStart = calendar.startOfDay(for: now)
        let windowStart = max(coverageStart,
                              calendar.date(byAdding: .day, value: -WatchCoverage.daysBehind, to: dayStart) ?? dayStart)
        let windowEnd = min(coverageEnd,
                            calendar.date(byAdding: .day, value: WatchCoverage.daysAhead, to: dayStart) ?? dayStart)

        guard windowEnd > windowStart else {
            return Self.rebuilt(from: self, start: windowStart, end: windowStart, events: [])
        }

        let inWindow = events
            .filter { $0.start < windowEnd && $0.end > windowStart }
            .sorted { $0.start < $1.start }

        guard inWindow.count > WatchCoverage.maxEvents else {
            return Self.rebuilt(from: self, start: windowStart, end: windowEnd, events: inWindow)
        }

        let kept = Array(inWindow.prefix(WatchCoverage.maxEvents))
        // The first dropped event marks the edge of what we can prove. Its start
        // becomes the new end of coverage; the last kept event is dropped too
        // when it starts at that same instant, which keeps the invariant
        // "every event we carry starts before coverageEnd" exactly true.
        let provenEnd = max(windowStart, min(windowEnd, inWindow[WatchCoverage.maxEvents].start))
        return Self.rebuilt(from: self, start: windowStart, end: provenEnd,
                            events: kept.filter { $0.start < provenEnd && $0.end > windowStart })
    }

    private static func rebuilt(from source: CalendarrSnapshot,
                                start: Date, end: Date,
                                events: [SnapshotEvent]) -> CalendarrSnapshot {
        CalendarrSnapshot(writtenAt: source.writtenAt,
                          coverageStart: start,
                          coverageEnd: end,
                          isLoggedIn: source.isLoggedIn,
                          writerVersion: source.writerVersion,
                          events: events,
                          theme: source.theme,
                          language: source.language)
    }
}
