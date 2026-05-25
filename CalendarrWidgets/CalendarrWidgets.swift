import WidgetKit
import SwiftUI

@main
struct CalendarrWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        TwoDaysWidget()
        ThreeDaysWidget()
        ThisWeekWidget()
        TwoWeeksWidget()
        UpcomingWidget()
        UpNextWidget()
    }
}

// Shared chrome modifier — keeps every widget on the same theme.
private struct CalendarrWidgetChrome: ViewModifier {
    let snapshot: WidgetSnapshot?

    func body(content: Content) -> some View {
        let lang = snapshot?.language ?? "system"
        content
            .containerBackground(for: .widget) {
                Color(widgetHex: snapshot?.backgroundColorHex ?? "#000000")
            }
            .foregroundStyle(Color(widgetHex: snapshot?.textColorHex ?? "#FFFFFF"))
            .environment(\.locale, WidgetL10n.locale(lang))
    }
}

private extension View {
    func calendarrChrome(_ snapshot: WidgetSnapshot?) -> some View {
        modifier(CalendarrWidgetChrome(snapshot: snapshot))
    }
}

// MARK: – Today (small)

struct TodayWidget: Widget {
    let kind: String = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarrTimelineProvider()) { entry in
            TodayWidgetView(entry: entry).calendarrChrome(entry.snapshot)
        }
        .configurationDisplayName(WidgetL10n.t("widget.display.today_title", "system"))
        .description(WidgetL10n.t("widget.display.today_desc", "system"))
        .supportedFamilies([.systemSmall])
    }
}

// MARK: – Today & Tomorrow (medium)

struct TwoDaysWidget: Widget {
    let kind: String = "TwoDaysWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarrTimelineProvider()) { entry in
            TwoDaysWidgetView(entry: entry).calendarrChrome(entry.snapshot)
        }
        .configurationDisplayName(WidgetL10n.t("widget.display.days_title", "system"))
        .description(WidgetL10n.t("widget.display.days_desc", "system"))
        .supportedFamilies([.systemMedium])
    }
}

// MARK: – Three Days (medium)

struct ThreeDaysWidget: Widget {
    let kind: String = "ThreeDaysWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarrTimelineProvider()) { entry in
            ThreeDaysWidgetView(entry: entry).calendarrChrome(entry.snapshot)
        }
        .configurationDisplayName(WidgetL10n.t("widget.display.threedays_title", "system"))
        .description(WidgetL10n.t("widget.display.threedays_desc", "system"))
        .supportedFamilies([.systemMedium])
    }
}

// MARK: – This Week (medium)

struct ThisWeekWidget: Widget {
    let kind: String = "ThisWeekWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarrTimelineProvider()) { entry in
            ThisWeekWidgetView(entry: entry).calendarrChrome(entry.snapshot)
        }
        .configurationDisplayName(WidgetL10n.t("widget.display.thisweek_title", "system"))
        .description(WidgetL10n.t("widget.display.thisweek_desc", "system"))
        .supportedFamilies([.systemMedium])
    }
}

// MARK: – Two Weeks (medium)

struct TwoWeeksWidget: Widget {
    let kind: String = "TwoWeeksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarrTimelineProvider()) { entry in
            TwoWeeksWidgetView(entry: entry).calendarrChrome(entry.snapshot)
        }
        .configurationDisplayName(WidgetL10n.t("widget.display.twoweeks_title", "system"))
        .description(WidgetL10n.t("widget.display.twoweeks_desc", "system"))
        .supportedFamilies([.systemMedium])
    }
}

// MARK: – Upcoming (large + extra large on iPad)

struct UpcomingWidget: Widget {
    let kind: String = "UpcomingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarrTimelineProvider()) { entry in
            UpcomingWidgetView(entry: entry).calendarrChrome(entry.snapshot)
        }
        .configurationDisplayName(WidgetL10n.t("widget.display.upcoming_title", "system"))
        .description(WidgetL10n.t("widget.display.upcoming_desc", "system"))
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

// MARK: – Up Next + Calendar (medium)

struct UpNextWidget: Widget {
    let kind: String = "UpNextWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarrTimelineProvider()) { entry in
            UpNextWidgetView(entry: entry).calendarrChrome(entry.snapshot)
        }
        .configurationDisplayName(WidgetL10n.t("widget.display.upnext_title", "system"))
        .description(WidgetL10n.t("widget.display.upnext_desc", "system"))
        .supportedFamilies([.systemMedium])
    }
}
