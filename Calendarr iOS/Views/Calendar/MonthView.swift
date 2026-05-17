import SwiftUI

struct MonthView: View {
    let store: CalendarStore
    let onDayTap: (Date) -> Void
    let onEventTap: (CalEvent) -> Void

    private var cal: Calendar { store.userCalendar }

    private var monthStart: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: store.currentDate))!
    }

    private var gridDays: [Date] {
        let firstWeekday = cal.firstWeekday
        let weekday = cal.component(.weekday, from: monthStart)
        let offset = ((weekday - firstWeekday) + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -offset, to: monthStart)!
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var rowCount: Int { gridDays.count / 7 }  // always 6

    private var weekdayHeaders: [String] {
        let symbols = cal.shortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return (0..<7).map { String(symbols[(start + $0) % 7].prefix(2)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Day-of-week header row (fixed height)
            HStack(spacing: 0) {
                ForEach(weekdayHeaders, id: \.self) { d in
                    Text(d)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
            }
            Divider()

            // Grid fills all remaining space using GeometryReader
            GeometryReader { geo in
                let rowH = geo.size.height / CGFloat(rowCount)
                VStack(spacing: 0) {
                    ForEach(0..<rowCount, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let day = gridDays[row * 7 + col]
                                DayCell(
                                    date: day,
                                    isCurrentMonth: cal.isDate(day, equalTo: monthStart, toGranularity: .month),
                                    isToday: cal.isDateInToday(day),
                                    events: store.events(on: day),
                                    rowHeight: rowH,
                                    onTap: { onDayTap(day) },
                                    onEventTap: onEventTap
                                )
                            }
                        }
                        .frame(height: rowH)
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let events: [CalEvent]
    let rowHeight: CGFloat
    let onTap: () -> Void
    let onEventTap: (CalEvent) -> Void

    private var maxVisible: Int {
        max(1, Int((rowHeight - 32) / 16))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Day number
            Button(action: onTap) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundStyle(
                        isToday ? Color.white :
                        isCurrentMonth ? Color.primary : Color.secondary.opacity(0.4)
                    )
                    .frame(width: 26, height: 26)
                    .background(isToday ? Color.accentColor : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .padding(.top, 2)

            // Events
            ForEach(events.prefix(maxVisible)) { ev in
                Button { onEventTap(ev) } label: {
                    EventChip(event: ev)
                }
                .buttonStyle(.plain)
            }

            if events.count > maxVisible {
                Text("+\(events.count - maxVisible)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(.separator)).frame(width: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
        }
    }
}

private struct EventChip: View {
    let event: CalEvent

    var body: some View {
        HStack(spacing: 3) {
            if !event.isAllDay {
                Circle()
                    .fill(Color(hex: event.effectiveColor))
                    .frame(width: 6, height: 6)
            }
            Text(event.title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(event.isAllDay ? .white : .primary)
        }
        .padding(.horizontal, event.isAllDay ? 4 : 2)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(event.isAllDay ? Color(hex: event.effectiveColor) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .padding(.horizontal, 2)
    }
}
