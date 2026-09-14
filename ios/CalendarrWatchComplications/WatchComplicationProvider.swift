import WidgetKit
import AppIntents
import SwiftUI
import CalendarrCore

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarrSnapshot?

    var language: String { snapshot?.language ?? "system" }
}

/// Builds every Calendarr complication's timeline.
///
/// Entries land on event boundaries rather than on a fixed schedule, so the
/// complication flips in the exact minute the next appointment changes without
/// a network call and without spending refresh budget. New *data* arrives by
/// push from the phone, which is why the refresh policy is `.atEnd`: when the
/// timeline simply runs out, regenerating from the same snapshot is cheap and
/// correct.
struct WatchComplicationProvider: AppIntentTimelineProvider {
    typealias Entry = WatchComplicationEntry
    typealias Intent = WatchCalendarSelectionIntent

    func placeholder(in context: Context) -> WatchComplicationEntry {
        WatchComplicationEntry(date: .now, snapshot: nil)
    }

    func snapshot(for configuration: WatchCalendarSelectionIntent,
                  in context: Context) async -> WatchComplicationEntry {
        WatchComplicationEntry(date: .now, snapshot: resolved(configuration))
    }

    func timeline(for configuration: WatchCalendarSelectionIntent,
                  in context: Context) async -> Timeline<WatchComplicationEntry> {
        let snapshot = resolved(configuration)
        let now = Date()
        let dates = snapshot.map { ComplicationTimeline.entryDates(from: now, in: $0) } ?? [now]
        return Timeline(entries: dates.map { WatchComplicationEntry(date: $0, snapshot: snapshot) },
                        policy: .atEnd)
    }

    /// What the complication gallery offers before anyone configures anything.
    /// Required on watchOS — iOS has a default implementation, the watch does
    /// not, because the gallery has to be populated.
    ///
    /// One entry, with nothing selected: that means "whatever the app is set
    /// to", which is the filter the user already chose there.
    func recommendations() -> [AppIntentRecommendation<WatchCalendarSelectionIntent>] {
        [AppIntentRecommendation(intent: WatchCalendarSelectionIntent(),
                                 description: Text("Calendarr"))]
    }

    /// The app-level filter applies first; a per-complication selection narrows
    /// further. An empty selection means "whatever the app is set to".
    private func resolved(_ configuration: WatchCalendarSelectionIntent) -> CalendarrSnapshot? {
        guard case .ok(let snapshot) = SnapshotStore().read() else { return nil }
        return snapshot
            .filtered(excludingCalendarKeys: WatchFilterStore.load())
            .filtered(toCalendarKeys: Set((configuration.selectedCalendars ?? []).map(\.id)))
    }
}
