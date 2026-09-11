import Foundation

/// When a complication needs to be redrawn.
///
/// A watch-face complication has a small refresh budget, so the timeline is
/// pre-computed from data the watch already holds instead of being refreshed on
/// a schedule: an entry on every event boundary means the complication changes
/// in the exact minute the next appointment does, without a network call.
public enum ComplicationTimeline {
    /// Dates at which a complication should re-render.
    ///
    /// Always begins with `now` so the first entry renders immediately. Event
    /// starts and ends within `horizon` become entries.
    ///
    /// The first `fineGrainedWindow` then gets a mark every minute, and the rest
    /// of the horizon one every hour. The fine-grained part is what lets a
    /// complication show a *compact* countdown — "23m" rather than "1:23:45" —
    /// which is the only kind that fits an accessoryCorner or a circular gauge.
    /// A live `Text(style: .timer)` needs no entries at all but is eight
    /// characters wide, and overlaps the curved label it sits next to.
    ///
    /// The result is sorted, deduplicated to the second, and capped at
    /// `maxEntries`, keeping the earliest.
    public static func entryDates(from now: Date,
                                  in snapshot: CalendarrSnapshot,
                                  horizon: TimeInterval = 24 * 3600,
                                  fineGrainedWindow: TimeInterval = 3600,
                                  maxEntries: Int = 150) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var seen: Set<Int> = []
        var dates: [Date] = []

        func add(_ date: Date) {
            guard date >= now, date <= end else { return }
            // Deduplicate to whole seconds: two events that meet exactly would
            // otherwise produce two entries a float apart.
            let key = Int(date.timeIntervalSince1970.rounded())
            guard seen.insert(key).inserted else { return }
            dates.append(date)
        }

        add(now)
        for event in snapshot.events {
            add(event.start)
            add(event.end)
        }
        let fineEnd = min(end, now.addingTimeInterval(fineGrainedWindow))
        var minute = now.addingTimeInterval(60)
        while minute <= fineEnd {
            add(minute)
            minute = minute.addingTimeInterval(60)
        }
        var hourly = now.addingTimeInterval(3600)
        while hourly <= end {
            add(hourly)
            hourly = hourly.addingTimeInterval(3600)
        }

        return Array(dates.sorted().prefix(maxEntries))
    }
}
