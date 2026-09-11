import WidgetKit
import SwiftUI

@main
struct CalendarrWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        WatchNextEventWidget()
        WatchCornerCountdownWidget()
        WatchCornerTitleWidget()
        WatchCornerTimeWidget()
        WatchCountdownWidget()
        WatchDateWidget()
        WatchTodayCountWidget()
        WatchNextTwoWidget()
        WatchDatePlusEventWidget()
    }
}

private extension View {
    /// Accessory families paint their own background; ours must stay out of
    /// the way so the watch face's tint comes through.
    func complicationChrome(_ language: String) -> some View {
        containerBackground(for: .widget) { Color.clear }
            .environment(\.locale, WatchL10n.locale(language))
    }
}

struct WatchNextEventWidget: Widget {
    let kind = "WatchNextEvent"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            NextEventComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Nächster Termin")
        .description("Zeit, Titel und Ort des nächsten Termins.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct WatchCornerCountdownWidget: Widget {
    let kind = "WatchCornerCountdown"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            CornerCountdownComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Restzeit (Ecke)")
        .description("Restzeit bis zum nächsten Termin, Name am Rand.")
        .supportedFamilies([.accessoryCorner])
    }
}

struct WatchCornerTitleWidget: Widget {
    let kind = "WatchCornerTitle"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            CornerTitleComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Terminname (Ecke)")
        .description("Name des nächsten Termins, Uhrzeit klein am Rand.")
        .supportedFamilies([.accessoryCorner])
    }
}

struct WatchCornerTimeWidget: Widget {
    let kind = "WatchCornerTime"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            CornerTimeComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Uhrzeit (Ecke)")
        .description("Uhrzeit des nächsten Termins, Name am Rand.")
        .supportedFamilies([.accessoryCorner])
    }
}

struct WatchCountdownWidget: Widget {
    let kind = "WatchCountdown"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            CountdownComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Countdown")
        .description("Ring, der bis zum nächsten Termin leerläuft.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct WatchDateWidget: Widget {
    let kind = "WatchDate"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            DateComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Datum")
        .description("Tag und Monat.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct WatchTodayCountWidget: Widget {
    let kind = "WatchTodayCount"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            TodayCountComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Termine heute")
        .description("Anzahl der heutigen Termine.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct WatchNextTwoWidget: Widget {
    let kind = "WatchNextTwo"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            NextTwoComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Die nächsten zwei")
        .description("Die beiden nächsten Termine.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct WatchDatePlusEventWidget: Widget {
    let kind = "WatchDatePlusEvent"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            DatePlusEventComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Datum + Termin")
        .description("Datum und nächster Termin in einem Slot.")
        .supportedFamilies([.accessoryRectangular])
    }
}
