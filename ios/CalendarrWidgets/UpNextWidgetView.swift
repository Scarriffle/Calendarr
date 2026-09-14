import SwiftUI
import WidgetKit

struct UpNextWidgetView: View {
    let entry: CalendarrEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = WidgetL10n.locale(lang)
        c.firstWeekday = 2
        return c
    }

    private var todayEvents: [WidgetEvent] {
        guard let s = snapshot else { return [] }
        return WidgetHelpers.events(for: entry.date, in: s)
    }

    /// Mini-month grid: 6 rows × 7 cols starting from the first weekday of the
    /// month, padded with neighbouring days where necessary.
    private var monthGrid: [Date] {
        let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: entry.date)) ?? entry.date
        let weekday = cal.component(.weekday, from: firstOfMonth)
        let offset = ((weekday - cal.firstWeekday) + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -offset, to: firstOfMonth) ?? firstOfMonth
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var weekdayHeaders: [String] {
        let f = DateFormatter(); f.locale = WidgetL10n.locale(lang)
        let symbols = f.veryShortWeekdaySymbols ?? cal.veryShortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    private var weekdayFmt: DateFormatter {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "EEE"
        return f
    }

    private var monthNameFmt: DateFormatter {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "LLL"
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
            HStack(spacing: 8) {
                leftPanel(snapshot: s, primary: primary, accent: accent)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                miniMonth(snapshot: s, primary: primary, accent: accent)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            Text(WidgetL10n.t("widget.no_data", lang))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func leftPanel(snapshot: WidgetSnapshot, primary: Color, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(cal.component(.day, from: entry.date))")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(primary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 0) {
                    Text(weekdayFmt.string(from: entry.date).uppercased() + ".")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                    Text(monthNameFmt.string(from: entry.date))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            if todayEvents.isEmpty {
                Text(WidgetL10n.t("widget.no_events", lang))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todayEvents.prefix(3)) { ev in
                    HStack(alignment: .top, spacing: 4) {
                        Circle()
                            .fill(Color(widgetHex: ev.colorHex))
                            .frame(width: 5, height: 5)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(ev.title)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                            Text(WidgetTime.range(ev, lang: lang))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func miniMonth(snapshot: WidgetSnapshot, primary: Color, accent: Color) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                ForEach(weekdayHeaders, id: \.self) { h in
                    Text(h)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            GeometryReader { geo in
                let cellW = geo.size.width / 7
                let cellH = geo.size.height / 6
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                miniDay(monthGrid[row * 7 + col],
                                        snapshot: snapshot,
                                        primary: primary,
                                        accent: accent)
                                    .frame(width: cellW, height: cellH)
                            }
                        }
                    }
                }
            }
        }
    }

    private func miniDay(_ day: Date, snapshot: WidgetSnapshot, primary: Color, accent: Color) -> some View {
        let isToday = cal.isDateInToday(day)
        let inMonth = cal.isDate(day, equalTo: entry.date, toGranularity: .month)
        let hasEvents = !WidgetHelpers.events(for: day, in: snapshot).isEmpty
        return ZStack {
            if isToday {
                RoundedRectangle(cornerRadius: 3)
                    .fill(primary)
            } else if hasEvents && inMonth {
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent.opacity(0.20))
            }
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 9, weight: isToday ? .bold : .medium))
                .foregroundStyle(
                    isToday ? Color.white :
                    inMonth ? Color.primary : Color.secondary.opacity(0.4)
                )
        }
        .padding(0.5)
    }
}
