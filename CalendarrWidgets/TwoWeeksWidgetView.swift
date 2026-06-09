import SwiftUI
import WidgetKit

struct TwoWeeksWidgetView: View {
    let entry: CalendarrEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = WidgetL10n.locale(lang)
        c.firstWeekday = 2
        return c
    }

    private var weekStart: Date {
        cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date)) ?? entry.date
    }

    private var fortnight: [Date] {
        (0..<14).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var monthHeader: String {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "LLLL yyyy"
        return f.string(from: weekStart).uppercased()
    }

    private var weekdayHeaders: [String] {
        let f = DateFormatter(); f.locale = WidgetL10n.locale(lang)
        let symbols = f.veryShortWeekdaySymbols ?? cal.veryShortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    var body: some View {
        if let s = snapshot {
            let primary = Color(widgetHex: s.primaryColorHex)
            let accent  = Color(widgetHex: s.accentColorHex)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(monthHeader.split(separator: " ").first.map(String.init) ?? "")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(primary)
                    Text(monthHeader.split(separator: " ").dropFirst().joined(separator: " "))
                        .font(.system(size: 9, weight: .semibold))
                }
                weekdayRow(accent: accent)
                GeometryReader { geo in
                    let colW = geo.size.width / 7
                    let rowH = geo.size.height / 2
                    VStack(spacing: 0) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { col in
                                    let day = fortnight[row * 7 + col]
                                    dayCell(day, snapshot: s, primary: primary, accent: accent)
                                        .frame(width: colW, height: rowH)
                                        .overlay(alignment: .trailing) {
                                            if col < 6 {
                                                Rectangle()
                                                    .fill(Color(widgetHex: s.lineColorHex).opacity(0.35))
                                                    .frame(width: 0.5)
                                            }
                                        }
                                        .overlay(alignment: .top) {
                                            if row == 1 {
                                                Rectangle()
                                                    .fill(Color(widgetHex: s.lineColorHex).opacity(0.35))
                                                    .frame(height: 0.5)
                                            }
                                        }
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

    private func weekdayRow(accent: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(weekdayHeaders, id: \.self) { h in
                Text(h)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: Date,
                         snapshot: WidgetSnapshot,
                         primary: Color,
                         accent: Color) -> some View {
        let isToday = cal.isDateInToday(day)
        let evs = WidgetHelpers.events(for: day, in: snapshot)
        return VStack(alignment: .center, spacing: 0.5) {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 8.5, weight: isToday ? .bold : .semibold))
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: 12, height: 12)
                .background(isToday ? primary : Color.clear)
                .clipShape(Circle())
            // Up to 2 mini event-title pills (the cell has room for titles).
            ForEach(evs.prefix(2)) { ev in
                Text(ev.title)
                    .font(.system(size: 6, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(widgetHex: ev.colorHex))
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
            }
            if evs.count > 2 {
                Text("+\(evs.count - 2)")
                    .font(.system(size: 6))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 1)
    }
}
