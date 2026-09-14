import SwiftUI

struct QuarterView: View {
    let store: CalendarStore
    let onEventTap: (CalEvent) -> Void

    private var cal: Calendar { store.userCalendar }

    private var months: [Date] {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: store.currentDate))!
        return (0..<3).compactMap { cal.date(byAdding: .month, value: $0, to: start) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(months, id: \.self) { month in
                    MiniMonthBlock(month: month, store: store, onEventTap: onEventTap)
                    Divider()
                }
            }
        }
    }
}

private struct MiniMonthBlock: View {
    let month: Date
    let store: CalendarStore
    let onEventTap: (CalEvent) -> Void

    private var cal: Calendar { store.userCalendar }

    private let monthFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()

    private var gridDays: [Date] {
        let firstWeekday = cal.firstWeekday
        let weekday = cal.component(.weekday, from: month)
        let offset = ((weekday - firstWeekday) + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -offset, to: month)!
        let rows = 6
        return (0..<(rows * 7)).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var weekdayHeaders: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(monthFmt.string(from: month))
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.top, 12)

            HStack(spacing: 0) {
                ForEach(weekdayHeaders, id: \.self) { d in
                    Text(d)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(gridDays, id: \.self) { day in
                    MiniDayCell(
                        date: day,
                        isCurrentMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                        isToday: cal.isDateInToday(day),
                        events: store.events(on: day),
                        onEventTap: onEventTap
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
    }
}

private struct MiniDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let events: [CalEvent]
    let onEventTap: (CalEvent) -> Void

    var body: some View {
        VStack(spacing: 1) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundStyle(
                    isToday ? Color.white :
                    isCurrentMonth ? Color.primary : Color.secondary.opacity(0.3)
                )
                .frame(width: 22, height: 22)
                .background(isToday ? Color.accentColor : Color.clear)
                .clipShape(Circle())

            // Up to 3 event dots
            HStack(spacing: 2) {
                ForEach(events.prefix(3)) { ev in
                    Circle()
                        .fill(Color(hex: ev.effectiveColor))
                        .frame(width: 4, height: 4)
                        .onTapGesture { onEventTap(ev) }
                }
            }
            .frame(height: 6)
        }
        .frame(minHeight: 36)
    }
}
