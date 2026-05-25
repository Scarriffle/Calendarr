import SwiftUI
import WidgetKit

struct ThisWeekWidgetView: View {
    let entry: CalendarrEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = WidgetL10n.locale(lang)
        c.firstWeekday = 2  // Monday
        return c
    }

    private var weekStart: Date {
        cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date)) ?? entry.date
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var monthHeader: String {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "LLLL yyyy"
        return f.string(from: weekStart).uppercased()
    }

    private var weekdayHeaders: [String] {
        let f = DateFormatter(); f.locale = WidgetL10n.locale(lang)
        let symbols = f.shortWeekdaySymbols ?? cal.shortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return (0..<7).map { String(symbols[(start + $0) % 7].prefix(2)).uppercased() }
    }

    var body: some View {
        if let s = snapshot {
            let primary = Color(widgetHex: s.primaryColorHex)
            let accent  = Color(widgetHex: s.accentColorHex)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(monthHeader.split(separator: " ").first.map(String.init) ?? "")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(primary)
                    Text(monthHeader.split(separator: " ").dropFirst().joined(separator: " "))
                        .font(.system(size: 10, weight: .semibold))
                }
                GeometryReader { geo in
                    let colW = geo.size.width / 7
                    HStack(spacing: 0) {
                        ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                            dayColumn(day, snapshot: s, primary: primary, accent: accent)
                                .frame(width: colW)
                                .overlay(alignment: .trailing) {
                                    if idx < 6 {
                                        Rectangle()
                                            .fill(Color(widgetHex: s.lineColorHex).opacity(0.35))
                                            .frame(width: 0.5)
                                    }
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

    private func dayColumn(_ day: Date,
                           snapshot: WidgetSnapshot,
                           primary: Color,
                           accent: Color) -> some View {
        let isToday = cal.isDateInToday(day)
        let evs = WidgetHelpers.events(for: day, in: snapshot)
        let dayIdx = (0..<7).firstIndex { i in cal.isDate(weekDays[i], inSameDayAs: day) } ?? 0
        return VStack(spacing: 1) {
            Text(weekdayHeaders[dayIdx])
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(isToday ? accent : .secondary)
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 10, weight: isToday ? .bold : .semibold))
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: 15, height: 15)
                .background(isToday ? primary : Color.clear)
                .clipShape(Circle())
            ForEach(evs.prefix(2)) { ev in
                eventPill(ev)
            }
            if evs.count > 2 {
                Text("+\(evs.count - 2)")
                    .font(.system(size: 7))
                    .foregroundStyle(accent)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 1)
    }

    private func eventPill(_ ev: WidgetEvent) -> some View {
        Text(ev.title)
            .font(.system(size: 7, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 2)
            .padding(.vertical, 0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(widgetHex: ev.colorHex))
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }
}
