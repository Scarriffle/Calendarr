import SwiftUI
import CalendarrCore

/// The whole app: a scrolling agenda grouped by day, plus a way to reach the
/// calendar filter. Read-only by design — the snapshot carries neither
/// recurrence rules nor permissions, so it is deliberately not enough to edit.
///
/// Deliberately does **not** apply `snapshot.theme` to the background. The
/// always-on display and OLED make black the right choice here; the theme only
/// contributes the per-event accent colours.
struct WatchAgendaView: View {
    @Environment(WatchSnapshotModel.self) private var model
    @State private var showingFilter = false

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = WatchL10n.locale(model.language)
        return calendar
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(WatchL10n.t("watch.title", model.language))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingFilter = true } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel(WatchL10n.t("watch.calendars", model.language))
                    }
                }
                .sheet(isPresented: $showingFilter) { WatchCalendarFilterView() }
        }
        .onAppear { WatchSnapshotReceiver.shared.requestRefresh() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.visible, !groups(in: snapshot).isEmpty {
            List {
                ForEach(groups(in: snapshot), id: \.day) { group in
                    Section(WatchEventFormat.dayHeader(group.day, language: model.language,
                                                       calendar: calendar)) {
                        ForEach(group.events) { event in
                            NavigationLink {
                                WatchEventDetailView(event: event,
                                                     calendarName: model.calendarName(for: event.calendarKey),
                                                     language: model.language)
                            } label: {
                                WatchEventRow(event: event, language: model.language)
                            }
                        }
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(WatchL10n.t("watch.as_of", model.language)) \(WatchEventFormat.time(snapshot.writtenAt, language: model.language))")
                        // Beyond the coverage window the snapshot carries no
                        // information, which is not the same as "nothing
                        // scheduled". Saying so is what keeps the empty tail of
                        // the list from reading as a free afternoon.
                        Text("\(WatchL10n.t("watch.no_information", model.language)) \(coverageEndLine(snapshot))")
                        if let error = WatchSnapshotReceiver.shared.lastError {
                            Text(error).foregroundStyle(.orange)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }
            }
            .listStyle(.carousel)
        } else {
            WatchStatusView(result: model.result, language: model.language)
        }
    }

    private struct DayGroup {
        let day: Date
        let events: [SnapshotEvent]
    }

    /// The last day the snapshot can speak for, formatted for the footer.
    private func coverageEndLine(_ snapshot: CalendarrSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(model.language)
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        let lastCovered = calendar.date(byAdding: .day, value: -1, to: snapshot.coverageEnd)
        return formatter.string(from: lastCovered ?? snapshot.coverageEnd)
    }

    /// Group the covered window by day. Days the snapshot cannot speak for are
    /// simply absent — never rendered as "nothing scheduled", which would look
    /// correct and be false.
    private func groups(in snapshot: CalendarrSnapshot) -> [DayGroup] {
        let calendar = self.calendar
        let from = max(snapshot.coverageStart, calendar.startOfDay(for: Date()))
        var buckets: [Date: [SnapshotEvent]] = [:]

        for event in snapshot.events where event.end > from {
            var day = calendar.startOfDay(for: max(event.start, from))
            // A multi-day event appears on each day it covers.
            while day < event.end && day < snapshot.coverageEnd {
                buckets[day, default: []].append(event)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        return buckets
            .map { DayGroup(day: $0.key, events: $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.day < $1.day }
    }
}
