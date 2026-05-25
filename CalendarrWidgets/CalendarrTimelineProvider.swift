import WidgetKit

struct CalendarrEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct CalendarrTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarrEntry {
        CalendarrEntry(date: .now, snapshot: WidgetStore.read())
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarrEntry) -> Void) {
        completion(CalendarrEntry(date: .now, snapshot: WidgetStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarrEntry>) -> Void) {
        let snapshot = WidgetStore.read()
        let now = Date()

        // Provide one entry per hour for the next 24h so the widget keeps
        // re-rendering as time progresses (past events drop off, "now" advances).
        var entries: [CalendarrEntry] = []
        for h in 0..<24 {
            let date = Calendar.current.date(byAdding: .hour, value: h, to: now) ?? now
            entries.append(CalendarrEntry(date: date, snapshot: snapshot))
        }
        // Ask iOS to refresh in 30 min to pick up any new data the app wrote.
        let refreshAt = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(refreshAt)))
    }
}

// MARK: – Shared helpers used by all widget views

enum WidgetHelpers {
    static func events(for day: Date, in snapshot: WidgetSnapshot) -> [WidgetEvent] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return snapshot.events
            .filter { $0.start < dayEnd && $0.end > dayStart }
            .sorted { $0.start < $1.start }
    }

    static func upcoming(from now: Date, daysAhead: Int, in snapshot: WidgetSnapshot) -> [WidgetEvent] {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: daysAhead, to: cal.startOfDay(for: now)) ?? now
        return snapshot.events
            .filter { $0.end > now && $0.start < end }
            .sorted { $0.start < $1.start }
    }
}
