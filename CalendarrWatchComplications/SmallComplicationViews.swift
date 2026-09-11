import SwiftUI
import WidgetKit
import CalendarrCore

/// Attaches the curved bezel label that a face with a bezel slot — Infograph —
/// renders across the top, where the tick marks otherwise are. Faces without
/// that slot ignore it, so it costs nothing to always provide.
private extension View {
    func eventBezelLabel(_ entry: WatchComplicationEntry) -> some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        return widgetLabel {
            Text(WatchComplicationSupport.eventLabel(next, at: entry.date, language: entry.language))
        }
    }
}

/// A draining ring plus the remaining time.
struct CountdownComplicationView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        switch family {
        case .accessoryInline:
            inline(next)
        default:
            circular(next)
        }
    }

    @ViewBuilder
    private func circular(_ next: SnapshotEvent?) -> some View {
        if let next {
            let target = WatchComplicationSupport.countdownTarget(next, at: entry.date)
            Gauge(value: WatchComplicationSupport.gaugeFraction(to: target, at: entry.date)) {
                Image(systemName: "calendar")
            } currentValueLabel: {
                Text(WatchComplicationSupport.compactCountdown(to: target, at: entry.date,
                                                               language: entry.language))
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .eventBezelLabel(entry)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "calendar").font(.system(size: 18))
            }
        }
    }

    @ViewBuilder
    private func inline(_ next: SnapshotEvent?) -> some View {
        if let next {
            Label {
                Text(WatchComplicationSupport.countdownTarget(next, at: entry.date), style: .timer)
            } icon: {
                Image(systemName: "timer")
            }
        } else {
            Label(WatchL10n.t("watch.no_events", entry.language), systemImage: "calendar")
        }
    }
}

/// Day number and month. No appointment information — a date replacement.
struct DateComplicationView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var day: Int {
        Calendar(identifier: .gregorian).component(.day, from: entry.date)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(WatchComplicationSupport.monthAbbreviation(entry.date, language: entry.language)) \(day)",
                  systemImage: "calendar")
        default:
            // A closed gauge, filling the slot edge to edge — the WidgetKit
            // equivalent of ClockKit's ClosedGaugeText, which no longer exists.
            // The ring is not decoration: it drains as the day does.
            Gauge(value: WatchComplicationSupport.dayRemainingFraction(at: entry.date)) {
                Text(WatchComplicationSupport.monthAbbreviation(entry.date, language: entry.language))
            } currentValueLabel: {
                Text("\(day)")
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .eventBezelLabel(entry)
        }
    }
}

/// How many appointments today. Says "busy", not "what".
struct TodayCountComplicationView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var count: Int {
        WatchComplicationSupport.todayCount(in: entry.snapshot, at: entry.date)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(count) \(WatchL10n.t("watch.events_today", entry.language))",
                  systemImage: "calendar")
        default:
            Gauge(value: WatchComplicationSupport.todayRemainingFraction(in: entry.snapshot,
                                                                         at: entry.date)) {
                Image(systemName: "calendar")
            } currentValueLabel: {
                Text("\(count)")
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .eventBezelLabel(entry)
        }
    }
}
