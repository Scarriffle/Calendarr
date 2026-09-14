import SwiftUI
import WidgetKit
import CalendarrCore

// A corner holds **one** value plus the curved bezel label. A second inner line
// runs into the curved text — do not add one. `.widgetLabel` is what makes
// WidgetKit lay the text along the edge; there is no arc to draw by hand.

/// Value: live countdown. Label: time and title.
struct CornerCountdownComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        Group {
            if let next {
                Text(WatchComplicationSupport.compactCountdown(
                        to: WatchComplicationSupport.countdownTarget(next, at: entry.date),
                        at: entry.date,
                        language: entry.language))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            } else {
                Image(systemName: "calendar")
            }
        }
        .widgetLabel {
            Text(WatchComplicationSupport.eventLabel(next, at: entry.date, language: entry.language))
        }
    }
}

/// Value: the appointment's clock time. Label: the title.
struct CornerTimeComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        Group {
            if let next {
                Text(next.isAllDay
                     ? WatchL10n.t("watch.allday", entry.language)
                     : WatchComplicationSupport.time(next.start, language: entry.language))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            } else {
                Image(systemName: "calendar")
            }
        }
        .widgetLabel {
            Text(next?.title ?? WatchL10n.t("watch.no_events", entry.language))
        }
    }
}

/// Value: the appointment's name. Label: the time, small and curved.
///
/// This is the inverse of how the slot is shaped — the curved bezel is where a
/// corner has room for long text, and the inner area holds three or four
/// characters. The title therefore shrinks and truncates here. Built this way
/// on request; `CornerTimeComplicationView` is the same information with the
/// roles the other way round, so both can be compared on the face.
struct CornerTitleComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        Group {
            if let next {
                Text(next.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .widgetAccentable()
            } else {
                Image(systemName: "calendar")
            }
        }
        .widgetLabel {
            Text(next.map {
                $0.isAllDay
                    ? WatchL10n.t("watch.allday", entry.language)
                    : WatchComplicationSupport.time($0.start, language: entry.language)
            } ?? WatchL10n.t("watch.no_events", entry.language))
        }
    }
}
