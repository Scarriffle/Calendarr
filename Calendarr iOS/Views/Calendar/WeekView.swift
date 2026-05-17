import SwiftUI

struct WeekView: View {
    let store: CalendarStore
    let onEventTap: (CalEvent) -> Void
    let onTimeTap: (Date) -> Void

    private var cal: Calendar { store.userCalendar }

    private var weekDays: [Date] {
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: store.currentDate))!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var timedEvents: [(Int, CalEvent)] {
        weekDays.enumerated().flatMap { idx, day in
            store.events(on: day).filter { !$0.isAllDay }.map { (idx, $0) }
        }
    }

    private var allDayEvents: [CalEvent] {
        let s = weekDays.first ?? .now
        let e = cal.date(byAdding: .day, value: 1, to: weekDays.last ?? .now)!
        return store.events(in: s, end: e).filter(\.isAllDay)
    }

    private var todayIndex: Int? {
        weekDays.firstIndex(where: { cal.isDateInToday($0) })
    }

    private let headerFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d"; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            columnHeaders
            Divider()
            if !allDayEvents.isEmpty { allDayRow }
            timeGrid
        }
    }

    // MARK: – Column headers (fixed height — no Color.clear tricks)

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: timeColumnWidth, height: 36) // fixed height!
            ForEach(weekDays, id: \.self) { day in
                Text(headerFmt.string(from: day).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(cal.isDateInToday(day) ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color(.separator)).frame(width: 0.5)
                    }
            }
        }
    }

    // MARK: – All-day strip

    private var allDayRow: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: timeColumnWidth)
            ForEach(weekDays, id: \.self) { day in
                let dayEvs = allDayEvents.filter { ev in
                    let ds = cal.startOfDay(for: day)
                    let de = cal.date(byAdding: .day, value: 1, to: ds)!
                    return ev.startDate < de && ev.endDate > ds
                }
                VStack(spacing: 1) {
                    ForEach(dayEvs.prefix(2)) { ev in
                        Button { onEventTap(ev) } label: {
                            Text(ev.title)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                                .background(Color(hex: ev.effectiveColor))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color(.separator)).frame(width: 0.5)
                }
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: – Time grid  (GeometryReader OUTSIDE ScrollView → clean layout)

    private var timeGrid: some View {
        GeometryReader { geo in
            let colW = (geo.size.width - timeColumnWidth) / 7

            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        // Background: time labels + vertical grid lines
                        HStack(alignment: .top, spacing: 0) {
                            timeLabels
                            ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                                VStack(spacing: 0) {
                                    ForEach(hours, id: \.self) { _ in
                                        Rectangle()
                                            .fill(Color(.separator).opacity(0.4))
                                            .frame(height: 0.5)
                                        Color.clear.frame(height: hourHeight - 0.5)
                                    }
                                }
                                .frame(width: colW)
                                .contentShape(Rectangle())
                                .onTapGesture { loc in
                                    let h = Int(loc.y / hourHeight)
                                    let m = Int((loc.y.truncatingRemainder(dividingBy: hourHeight)) / hourHeight * 60)
                                    let date = cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
                                    onTimeTap(date)
                                }
                                .overlay(alignment: .trailing) {
                                    Rectangle().fill(Color(.separator)).frame(width: 0.5)
                                }
                            }
                        }

                        // Events – positioned using known column widths (no GeometryReader inside)
                        ForEach(timedEvents, id: \.1.id) { dayIdx, ev in
                            Button(action: { onEventTap(ev) }) {
                                EventBlock(event: ev)
                            }
                            .buttonStyle(.plain)
                            .frame(width: colW - 2, height: max(eventHeight(ev), 18))
                            .offset(x: timeColumnWidth + CGFloat(dayIdx) * colW + 1,
                                    y: eventTop(ev))
                        }

                        // Current time line
                        if let ti = todayIndex {
                            let lineY = eventTop(Date.now)
                            HStack(spacing: 0) {
                                Spacer().frame(width: timeColumnWidth + CGFloat(ti) * colW - 4)
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                Rectangle().fill(Color.red).frame(width: colW - 4, height: 1.5)
                            }
                            .offset(y: lineY - 0.75)
                        }
                    }
                    .frame(width: geo.size.width, height: hourHeight * 24 + 80)
                    .id("grid")
                }
                .onAppear { scrollToCurrentHour(proxy) }
                .onChange(of: store.currentDate) { _, _ in scrollToCurrentHour(proxy) }
            }
        }
    }

    private var timeLabels: some View {
        VStack(spacing: 0) {
            ForEach(hours, id: \.self) { h in
                ZStack(alignment: .topTrailing) {
                    Color.clear.frame(height: hourHeight)
                    Text(String(format: "%02d:00", h))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .offset(y: -6)
                }
            }
            Color.clear.frame(height: 80) // FAB space
        }
        .frame(width: timeColumnWidth)
    }

    private func scrollToCurrentHour(_ proxy: ScrollViewProxy) {
        let h = Calendar.current.component(.hour, from: .now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("grid", anchor: UnitPoint(x: 0, y: CGFloat(max(h - 1, 0)) / 24.0))
            }
        }
    }
}

// Trick to compute eventTop from a Date instead of CalEvent
private func eventTop(_ date: Date) -> CGFloat {
    let cal = Calendar.current
    let h = CGFloat(cal.component(.hour, from: date))
    let m = CGFloat(cal.component(.minute, from: date))
    return h * hourHeight + m * hourHeight / 60
}
