import SwiftUI
import WidgetKit
import CalendarrCore

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
                Text(target, style: .timer)
                    .font(.system(size: 12))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
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
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(day)")
                        .font(.system(size: 22, weight: .bold))
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    Text(WatchComplicationSupport.monthAbbreviation(entry.date, language: entry.language))
                        .font(.system(size: 8, weight: .semibold))
                }
            }
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
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(count)")
                        .font(.system(size: 22, weight: .bold))
                        .widgetAccentable()
                    Text(WatchL10n.t("watch.events_today", entry.language).uppercased())
                        .font(.system(size: 7, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }
}
