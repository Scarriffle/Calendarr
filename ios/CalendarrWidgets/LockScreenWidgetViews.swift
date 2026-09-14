import SwiftUI
import WidgetKit

// MARK: – Date widget (existing)

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

// MARK: – Today event count widget

struct LockScreenCountWidgetView: View {
    let entry: CalendarrEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var timeFmt: DateFormatter {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "HH:mm"
        return f
    }

    private var todayEvents: [WidgetEvent] {
        guard let s = snapshot else { return [] }
        return WidgetHelpers.upcoming(from: entry.date, daysAhead: 1, in: s)
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

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .widgetAccentable()
                Text("\(todayEvents.count)")
                    .font(.system(size: 22, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
            }
        }
    }

    private var rectangularView: some View {
        let countLabel = "\(todayEvents.count) \(WidgetL10n.t("widget.events_count", lang))"
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(WidgetL10n.t("widget.today", lang).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .widgetAccentable()
                Text("· \(countLabel)")
                    .font(.system(size: 9))
            }
            if todayEvents.isEmpty {
                Text(WidgetL10n.t("widget.no_events", lang))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todayEvents.prefix(2)) { ev in
                    HStack(spacing: 4) {
                        Text(ev.isAllDay ? "·" : timeFmt.string(from: ev.start))
                            .font(.system(size: 10, weight: .semibold))
                            .widgetAccentable()
                            .frame(width: 32, alignment: .leading)
                        Text(ev.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var inlineView: some View {
        let label = "\(todayEvents.count) \(WidgetL10n.t("widget.events_count", lang))"
        return Label(label, systemImage: "calendar.badge.clock")
    }
}

// MARK: – Countdown to next event widget

struct LockScreenCountdownWidgetView: View {
    let entry: CalendarrEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var timeFmt: DateFormatter {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "HH:mm"
        return f
    }

    private var nextEvent: WidgetEvent? {
        guard let s = snapshot else { return nil }
        return WidgetHelpers.upcoming(from: entry.date, daysAhead: 1, in: s).first
    }

    private var isRunning: Bool {
        guard let ev = nextEvent, !ev.isAllDay else { return false }
        return ev.start <= entry.date && ev.end > entry.date
    }

    private var countdownText: String {
        guard let ev = nextEvent else { return WidgetL10n.t("widget.no_events", lang) }
        if isRunning { return WidgetL10n.t("widget.running", lang) }
        if ev.isAllDay { return WidgetL10n.t("widget.allday", lang) }
        let total = Int(max(0, ev.start.timeIntervalSince(entry.date)) / 60)
        if total < 60 { return "in \(total)m" }
        let h = total / 60; let m = total % 60
        return m == 0 ? "in \(h)h" : "in \(h)h \(m)m"
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

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text(countdownText)
                    .font(.system(size: 13, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
                if let ev = nextEvent, !ev.isAllDay {
                    Text(timeFmt.string(from: ev.start))
                        .font(.system(size: 8))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let ev = nextEvent {
                Text(countdownText)
                    .font(.system(size: 11, weight: .semibold))
                    .widgetAccentable()
                Text(ev.title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                let timeStr = ev.isAllDay
                    ? WidgetL10n.t("widget.allday", lang)
                    : "\(timeFmt.string(from: ev.start)) – \(timeFmt.string(from: ev.end))"
                Text(timeStr)
                    .font(.system(size: 11))
                    .lineLimit(1)
            } else {
                Image(systemName: "timer")
                    .font(.system(size: 13))
                    .widgetAccentable()
                Text(WidgetL10n.t("widget.no_events", lang))
                    .font(.system(size: 13))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var inlineView: some View {
        let text: String = {
            guard let ev = nextEvent else { return WidgetL10n.t("widget.no_events", lang) }
            return "\(ev.title) \(countdownText)"
        }()
        return Label(text, systemImage: "timer")
    }
}
