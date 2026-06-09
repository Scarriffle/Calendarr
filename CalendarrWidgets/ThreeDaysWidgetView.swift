import SwiftUI
import WidgetKit

struct ThreeDaysWidgetView: View {
    let entry: CalendarrEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = WidgetL10n.locale(lang)
        return c
    }

    private var days: [Date] {
        let today = cal.startOfDay(for: entry.date)
        return (0..<3).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    private var monthHeader: String {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "LLLL yyyy"
        return f.string(from: entry.date).uppercased()
    }

    private var weekdayFmt: DateFormatter {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "EEE"
        return f
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(monthHeader.split(separator: " ").first.map(String.init) ?? "")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(primary)
                    Text(monthHeader.split(separator: " ").dropFirst().joined(separator: " "))
                        .font(.system(size: 11, weight: .semibold))
                }
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
                        column(for: day, snapshot: s, primary: primary, accent: accent)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .overlay(alignment: .trailing) {
                                if idx < 2 {
                                    Rectangle()
                                        .fill(Color(widgetHex: s.lineColorHex).opacity(0.4))
                                        .frame(width: 0.5)
                                }
                            }
                    }
                }
            }
        } else {
            Text(WidgetL10n.t("widget.no_data", lang))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func column(for day: Date, snapshot: WidgetSnapshot, primary: Color, accent: Color) -> some View {
        let isToday = cal.isDateInToday(day)
        let evs = WidgetHelpers.events(for: day, in: snapshot)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(weekdayFmt.string(from: day).uppercased() + ".")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isToday ? accent : .secondary)
                Spacer()
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 11, weight: isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? Color.white : Color.primary)
                    .frame(width: 17, height: 17)
                    .background(isToday ? primary : Color.clear)
                    .clipShape(Circle())
            }
            .padding(.horizontal, 3)
            if evs.isEmpty {
                Text(WidgetL10n.t("widget.no_events", lang))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 3)
            } else {
                ForEach(evs.prefix(4)) { ev in
                    eventRow(ev)
                }
                if evs.count > 4 {
                    Text("+\(evs.count - 4)")
                        .font(.system(size: 8))
                        .foregroundStyle(accent)
                        .padding(.leading, 3)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func eventRow(_ ev: WidgetEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(widgetHex: ev.colorHex))
                    .frame(width: 2)
                Text(ev.title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(WidgetTime.range(ev, lang: lang))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .padding(.leading, 5)
        }
        .padding(.horizontal, 3)
    }
}
