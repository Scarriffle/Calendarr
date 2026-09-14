import SwiftUI
import WidgetKit

struct TwoDaysWidgetView: View {
    let entry: CalendarrEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var today: Date { Calendar.current.startOfDay(for: entry.date) }
    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private var timeFmt: DateFormatter {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "HH:mm"
        return f
    }

    var body: some View {
        if let s = snapshot {
            let primary = Color(widgetHex: s.primaryColorHex)
            let accent  = Color(widgetHex: s.accentColorHex)
            HStack(spacing: 8) {
                column(for: today,
                       title: WidgetL10n.t("widget.today", lang),
                       isToday: true,
                       events: WidgetHelpers.events(for: today, in: s),
                       primary: primary, accent: accent,
                       lineColor: Color(widgetHex: s.lineColorHex))
                Rectangle()
                    .fill(Color(widgetHex: s.lineColorHex).opacity(0.4))
                    .frame(width: 0.5)
                column(for: tomorrow,
                       title: WidgetL10n.t("widget.tomorrow", lang),
                       isToday: false,
                       events: WidgetHelpers.events(for: tomorrow, in: s),
                       primary: primary, accent: accent,
                       lineColor: Color(widgetHex: s.lineColorHex))
            }
        } else {
            Text(WidgetL10n.t("widget.no_data", lang))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func column(for day: Date,
                        title: String,
                        isToday: Bool,
                        events: [WidgetEvent],
                        primary: Color,
                        accent: Color,
                        lineColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isToday ? primary : accent)
                Text(shortDate(day))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if events.isEmpty {
                Text(WidgetL10n.t("widget.no_events", lang))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(4)) { ev in
                    eventRow(ev)
                }
                if events.count > 4 {
                    Text(String(format: WidgetL10n.t("widget.more", lang), events.count - 4))
                        .font(.system(size: 9))
                        .foregroundStyle(accent)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func eventRow(_ ev: WidgetEvent) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(widgetHex: ev.colorHex))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(ev.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(WidgetTime.range(ev, lang: lang))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "d. MMM"
        return f.string(from: d)
    }
}
