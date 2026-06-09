import SwiftUI
import WidgetKit

struct TwoMonthWidgetView: View {
    let entry: CalendarrEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = WidgetL10n.locale(lang)
        c.firstWeekday = 2
        return c
    }

    private var thisMonth: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: entry.date)) ?? entry.date
    }

    private var nextMonth: Date {
        cal.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
    }

    // Weekday header labels (M T W T F S S)
    private var weekdayHeaders: [String] {
        let f = DateFormatter(); f.locale = WidgetL10n.locale(lang)
        let symbols = f.veryShortWeekdaySymbols ?? cal.veryShortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return (0..<7).map { String(symbols[(start + $0) % 7]).uppercased() }
    }

    // Number of date rows to show (5 for medium, 6 for large)
    private var rowCount: Int { family == .systemLarge ? 6 : 5 }

    var body: some View {
        if let s = snapshot {
            let primary = Color(widgetHex: s.primaryColorHex)
            let accent  = Color(widgetHex: s.accentColorHex)
            let line    = Color(widgetHex: s.lineColorHex)
            HStack(alignment: .top, spacing: 0) {
                monthColumn(monthDate: thisMonth, snapshot: s,
                            primary: primary, accent: accent, line: line)
                    .frame(maxWidth: .infinity)
                line.opacity(0.35).frame(width: 0.5)
                    .padding(.horizontal, 3)
                monthColumn(monthDate: nextMonth, snapshot: s,
                            primary: primary, accent: accent, line: line)
                    .frame(maxWidth: .infinity)
            }
        } else {
            Text(WidgetL10n.t("widget.no_data", lang))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: – One month column

    private func monthColumn(monthDate: Date,
                             snapshot: WidgetSnapshot,
                             primary: Color,
                             accent: Color,
                             line: Color) -> some View {
        let monthFmt = DateFormatter()
        monthFmt.locale = WidgetL10n.locale(lang)
        monthFmt.dateFormat = "LLLL"
        let name = monthFmt.string(from: monthDate).uppercased()
        let start = gridStart(for: monthDate)
        let wn = WidgetL10n.t("widget.cw", lang)

        return VStack(alignment: .leading, spacing: 1) {
            // Month name
            Text(name)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(primary)

            // Column headers: KW + 7 weekdays
            HStack(spacing: 0) {
                Text(wn)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .center)
                ForEach(weekdayHeaders, id: \.self) { h in
                    Text(h)
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Date rows
            ForEach(0..<rowCount, id: \.self) { row in
                let rowStart = cal.date(byAdding: .day, value: row * 7, to: start)!
                let weekNum  = cal.component(.weekOfYear, from: rowStart)
                let inMonth  = cal.isDate(rowStart, equalTo: monthDate, toGranularity: .month)
                            || cal.isDate(cal.date(byAdding: .day, value: 6, to: rowStart)!,
                                          equalTo: monthDate, toGranularity: .month)
                if inMonth {
                    HStack(spacing: 0) {
                        Text("\(weekNum)")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .frame(width: 14, alignment: .center)
                        ForEach(0..<7, id: \.self) { col in
                            let day = cal.date(byAdding: .day, value: col, to: rowStart)!
                            dayCell(day, monthDate: monthDate, snapshot: snapshot,
                                    primary: primary, accent: accent)
                        }
                    }
                    // Distribute weeks across the full column height instead of
                    // top-packing them (which left the lower portion empty).
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: – Day cell

    private func dayCell(_ day: Date,
                         monthDate: Date,
                         snapshot: WidgetSnapshot,
                         primary: Color,
                         accent: Color) -> some View {
        let isToday   = cal.isDateInToday(day)
        let inMonth   = cal.isDate(day, equalTo: monthDate, toGranularity: .month)
        let evs       = inMonth ? WidgetHelpers.events(for: day, in: snapshot) : []
        let isWeekend = { () -> Bool in
            let wd = cal.component(.weekday, from: day)
            return wd == 1 || wd == 7
        }()

        return VStack(spacing: 1) {
            ZStack {
                if isToday { Circle().fill(primary) }
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 7.5, weight: isToday ? .bold : .medium))
                    .foregroundStyle(
                        isToday ? .white :
                        !inMonth ? Color.secondary.opacity(0.3) :
                        isWeekend ? Color.primary.opacity(0.5) :
                        Color.primary
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 11)

            // Event dots
            HStack(spacing: 1) {
                ForEach(evs.prefix(3).indices, id: \.self) { i in
                    Circle()
                        .fill(Color(widgetHex: evs[i].colorHex))
                        .frame(width: 2.5, height: 2.5)
                }
            }
            .frame(height: 3)
        }
        .padding(.bottom, 1)
    }

    // MARK: – Grid helpers

    private func gridStart(for monthDate: Date) -> Date {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)) ?? monthDate
        let weekday = cal.component(.weekday, from: first)
        let offset = ((weekday - cal.firstWeekday) + 7) % 7
        return cal.date(byAdding: .day, value: -offset, to: first) ?? first
    }
}
