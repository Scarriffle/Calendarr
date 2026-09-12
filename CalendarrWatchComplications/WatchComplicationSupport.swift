import Foundation
import CalendarrCore

enum WatchComplicationSupport {
    /// The first event that has not ended yet — including one running now,
    /// which is what "what is next" means when you are already in a meeting.
    /// Matches `WatchPushPolicy.nextEventIdentity`, deliberately.
    static func nextEvent(in snapshot: CalendarrSnapshot?, at now: Date) -> SnapshotEvent? {
        snapshot?.events.filter { $0.end > now }.min { $0.start < $1.start }
    }

    static func upcoming(in snapshot: CalendarrSnapshot?, at now: Date, limit: Int) -> [SnapshotEvent] {
        guard let snapshot else { return [] }
        return Array(snapshot.events.filter { $0.end > now }.sorted { $0.start < $1.start }.prefix(limit))
    }

    static func todayCount(in snapshot: CalendarrSnapshot?, at now: Date,
                           calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        guard let snapshot else { return 0 }
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        return snapshot.events.filter { $0.start < dayEnd && $0.end > dayStart }.count
    }

    /// The appointment happening right now, if there is one. All-day events are
    /// excluded on purpose: one of those is "running" for twenty-four hours and
    /// would hold the ring at some arbitrary fraction all day, which says
    /// nothing.
    static func runningEvent(in snapshot: CalendarrSnapshot?, at now: Date) -> SnapshotEvent? {
        snapshot?.events
            .filter { !$0.isAllDay && $0.start <= now && $0.end > now }
            .min { $0.end < $1.end }
    }

    /// How far through an appointment we are, 0 at its start and 1 at its end.
    static func progress(of event: SnapshotEvent, at now: Date) -> Double {
        let total = event.end.timeIntervalSince(event.start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(event.start) / total))
    }

    static func weekdayAbbreviation(_ date: Date, language: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
    }

    /// What a countdown counts to: the start if it has not begun, otherwise the
    /// end. Counting up from a start time that has passed reads as broken.
    static func countdownTarget(_ event: SnapshotEvent, at now: Date) -> Date {
        event.start > now ? event.start : event.end
    }

    /// A countdown narrow enough for a corner or a circular gauge: at most
    /// three characters. `Text(style: .timer)` would be live and free of
    /// timeline entries, but renders `1:23:45` and overlaps whatever sits
    /// beside it — so the timeline carries minute-granular entries instead and
    /// this is recomputed per entry.
    static func compactCountdown(to target: Date, at now: Date, language: String) -> String {
        let seconds = target.timeIntervalSince(now)
        guard seconds > 0 else { return WatchL10n.t("watch.now", language) }
        let minutes = Int(seconds / 60)
        if minutes < 1  { return WatchL10n.t("watch.now", language) }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24   { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    /// How full a draining ring should be, over a two-hour lead window.
    static func gaugeFraction(to target: Date, at now: Date) -> Double {
        let window: TimeInterval = 2 * 3600
        return min(1, max(0, target.timeIntervalSince(now) / window))
    }

    /// How much of today is still ahead. Drains through the day, matching the
    /// countdown ring rather than inventing a second direction.
    static func dayRemainingFraction(at now: Date,
                                     calendar: Calendar = Calendar(identifier: .gregorian)) -> Double {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        let total = dayEnd.timeIntervalSince(dayStart)
        guard total > 0 else { return 0 }
        return min(1, max(0, dayEnd.timeIntervalSince(now) / total))
    }

    /// The share of today's appointments still ahead. Zero when there are none,
    /// which leaves the ring empty rather than full — an empty day should not
    /// look like an untouched one.
    static func todayRemainingFraction(in snapshot: CalendarrSnapshot?, at now: Date,
                                       calendar: Calendar = Calendar(identifier: .gregorian)) -> Double {
        guard let snapshot else { return 0 }
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        let today = snapshot.events.filter { $0.start < dayEnd && $0.end > dayStart }
        guard !today.isEmpty else { return 0 }
        let ahead = today.filter { $0.end > now }.count
        return min(1, max(0, Double(ahead) / Double(today.count)))
    }

    static func time(_ date: Date, language: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func monthAbbreviation(_ date: Date, language: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.dateFormat = "LLL"
        return formatter.string(from: date).uppercased()
    }

    /// The curved label that accompanies a circular or corner complication:
    /// time plus title, or a plain "no events".
    ///
    /// On a corner this follows the screen edge. On a face with a bezel slot —
    /// Infograph — the same label arcs across the top, where the tick marks
    /// otherwise are. That is the position ClockKit called `graphicBezel`, and
    /// in WidgetKit it is reached by attaching `.widgetLabel` to an
    /// `accessoryCircular` widget.
    static func eventLabel(_ event: SnapshotEvent?, at now: Date, language: String) -> String {
        guard let event else { return WatchL10n.t("watch.no_events", language) }
        if event.isAllDay { return event.title }
        return "\(time(event.start, language: language)) \(event.title)"
    }
}
