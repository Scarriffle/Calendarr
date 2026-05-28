import SwiftUI
import WidgetKit

struct LockScreenWidgetView: View {
    let entry: CalendarrEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = WidgetL10n.locale(lang)
        return c
    }

    private var nextEvent: WidgetEvent? {
        guard let s = snapshot else { return nil }
        return WidgetHelpers.upcoming(from: entry.date, daysAhead: 1, in: s).first
    }

    private var timeFmt: DateFormatter {
        let f = DateFormatter(); f.locale = WidgetL10n.locale(lang); f.dateFormat = "HH:mm"; return f
    }

    private var monthAbbrev: String {
        let f = DateFormatter(); f.locale = WidgetL10n.locale(lang); f.dateFormat = "LLL"
        return f.string(from: entry.date).uppercased()
    }

    @ViewBuilder
    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            inlineView
        }
    }

    // MARK: – Circular: today's date

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("\(cal.component(.day, from: entry.date))")
                    .font(.system(size: 22, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                Text(monthAbbrev)
                    .font(.system(size: 8, weight: .semibold))
            }
        }
    }

    // MARK: – Rectangular: next event

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let ev = nextEvent {
                Text(ev.isAllDay
                     ? WidgetL10n.t("widget.allday", lang)
                     : timeFmt.string(from: ev.start))
                    .font(.system(size: 11, weight: .semibold))
                    .widgetAccentable()
                Text(ev.title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                if !ev.location.isEmpty {
                    Text(ev.location)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .widgetAccentable()
                Text(WidgetL10n.t("widget.no_events", lang))
                    .font(.system(size: 13))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: – Inline: brief next event

    private var inlineView: some View {
        let text: String = {
            guard let ev = nextEvent else {
                return WidgetL10n.t("widget.no_events", lang)
            }
            return ev.isAllDay ? ev.title : "\(timeFmt.string(from: ev.start)) \(ev.title)"
        }()
        return Label(text, systemImage: "calendar")
    }
}
