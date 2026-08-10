import WidgetKit
import AppIntents

struct CalendarrEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct CalendarrTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = CalendarrEntry
    typealias Intent = CalendarSelectionIntent

    func placeholder(in context: Context) -> CalendarrEntry {
        CalendarrEntry(date: .now, snapshot: WidgetStore.read())
    }

    func snapshot(for configuration: CalendarSelectionIntent, in context: Context) async -> CalendarrEntry {
        let raw = WidgetStore.read()
        return CalendarrEntry(date: .now, snapshot: filtered(raw, by: configuration))
    }

    func timeline(for configuration: CalendarSelectionIntent, in context: Context) async -> Timeline<CalendarrEntry> {
        let raw = WidgetStore.read()
        let snap = filtered(raw, by: configuration)
        let now = Date()

        // One entry per hour for 24 h so the widget re-renders as time advances.
        var entries: [CalendarrEntry] = []
        for h in 0..<24 {
            let date = Calendar.current.date(byAdding: .hour, value: h, to: now) ?? now
            entries.append(CalendarrEntry(date: date, snapshot: snap))
        }
        let refreshAt = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now
        return Timeline(entries: entries, policy: .after(refreshAt))
    }

    // MARK: – Filtering

    private func filtered(_ snapshot: WidgetSnapshot?, by config: CalendarSelectionIntent) -> WidgetSnapshot? {
        guard let snapshot else { return nil }
        let ids = (config.selectedCalendars ?? []).map { $0.id }
        guard !ids.isEmpty else { return snapshot }   // nothing selected = show all
        let keep = Set(ids)
        return WidgetSnapshot(
            writtenAt:          snapshot.writtenAt,
            events:             snapshot.events.filter { keep.contains($0.calendarKey) },
            todayColorHex:      snapshot.todayColorHex,
            textColorHex:       snapshot.textColorHex,
            backgroundColorHex: snapshot.backgroundColorHex,
            lineColorHex:       snapshot.lineColorHex,
            primaryColorHex:    snapshot.primaryColorHex,
            accentColorHex:     snapshot.accentColorHex,
            language:           snapshot.language
        )
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
