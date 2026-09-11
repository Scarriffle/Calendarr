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
            Text(WatchComplicationSupport.cornerLabel(next, at: entry.date, language: entry.language))
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
