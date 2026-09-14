import SwiftUI
import WidgetKit

struct TodayWidgetView: View {
    let entry: CalendarrEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }

    private var todayEvents: [WidgetEvent] {
        guard let s = snapshot else { return [] }
        return WidgetHelpers.events(for: entry.date, in: s)
    }

    private var lang: String { snapshot?.language ?? "system" }

    private var timeFmt: DateFormatter {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "HH:mm"
        return f
    }

    var body: some View {
        let primary = Color(widgetHex: snapshot?.primaryColorHex ?? "#4285f4")
        let accent  = Color(widgetHex: snapshot?.accentColorHex ?? "#ea4335")
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(WidgetL10n.t("widget.today", lang))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(primary)
                Spacer()
                Text(headerDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if snapshot == nil {
                Text(WidgetL10n.t("widget.no_data", lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if todayEvents.isEmpty {
                Spacer()
                Text(WidgetL10n.t("widget.no_events", lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(todayEvents.prefix(3)) { ev in
                    eventRow(ev)
                }
                if todayEvents.count > 3 {
                    Text(String(format: WidgetL10n.t("widget.more", lang), todayEvents.count - 3))
                        .font(.caption2)
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var headerDate: String {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "d. MMM"
        return f.string(from: entry.date)
    }

    private func eventRow(_ ev: WidgetEvent) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(widgetHex: ev.colorHex))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(ev.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(WidgetTime.range(ev, lang: lang))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
