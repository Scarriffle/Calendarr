import SwiftUI
import WidgetKit
import CalendarrCore

/// Time, title, location. The variant that answers the actual question.
struct NextEventComplicationView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        switch family {
        case .accessoryInline:
            inline(next)
        default:
            rectangular(next)
        }
    }

    @ViewBuilder
    private func rectangular(_ next: SnapshotEvent?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let next {
                Text(next.isAllDay
                     ? WatchL10n.t("watch.allday", entry.language)
                     : WatchComplicationSupport.time(next.start, language: entry.language))
                    .font(.system(size: 12, weight: .semibold))
                    .widgetAccentable()
                Text(next.title)
                    .font(.system(size: 15))
                    .lineLimit(1)
                if !next.location.isEmpty {
                    Text(next.location)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "calendar").font(.system(size: 13)).widgetAccentable()
                Text(WatchL10n.t("watch.no_events", entry.language)).font(.system(size: 13))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func inline(_ next: SnapshotEvent?) -> some View {
        let text: String = {
            guard let next else { return WatchL10n.t("watch.no_events", entry.language) }
            if next.isAllDay { return next.title }
            return "\(WatchComplicationSupport.time(next.start, language: entry.language)) \(next.title)"
        }()
        return Label(text, systemImage: "calendar")
    }
}

/// The next two, so back-to-back appointments are visible at once.
struct NextTwoComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        let events = WatchComplicationSupport.upcoming(in: entry.snapshot, at: entry.date, limit: 2)
        VStack(alignment: .leading, spacing: 3) {
            if events.isEmpty {
                Image(systemName: "calendar").font(.system(size: 13)).widgetAccentable()
                Text(WatchL10n.t("watch.no_events", entry.language)).font(.system(size: 13))
            } else {
                ForEach(events) { event in
                    HStack(spacing: 5) {
                        Text(event.isAllDay
                             ? WatchL10n.t("watch.allday", entry.language)
                             : WatchComplicationSupport.time(event.start, language: entry.language))
                            .font(.system(size: 12, weight: .semibold))
                            .widgetAccentable()
                        Text(event.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Weekday and date plus the next appointment, so one slot does both jobs.
struct DatePlusEventComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        VStack(alignment: .leading, spacing: 2) {
            Text(dateLine)
                .font(.system(size: 11, weight: .semibold))
                .widgetAccentable()
            if let next {
                Text(next.isAllDay
                     ? next.title
                     : "\(WatchComplicationSupport.time(next.start, language: entry.language)) \(next.title)")
                    .font(.system(size: 14))
                    .lineLimit(1)
            } else {
                Text(WatchL10n.t("watch.no_events", entry.language)).font(.system(size: 14))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(entry.language)
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMMM")
        return formatter.string(from: entry.date).uppercased()
    }
}
