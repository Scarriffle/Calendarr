import SwiftUI

// Cover ~10 years back and ~77 years ahead, so the scrollable range goes well
// past 2100 — enough room for any vacation that's actually getting planned.
private let weeksBack = 520
private let weeksAhead = 4000
private let weekdayHeaderHeight: CGFloat = 28
private let dayNumberRowHeight: CGFloat = 22
private let laneHeight: CGFloat = 16
private let laneSpacing: CGFloat = 2
private let maxLanesPerWeek = 5

private enum DividerEdge { case none, topHighlight, bottomHighlight }

struct MonthView: View {
    let store: CalendarStore
    let onDayTap: (Date) -> Void
    let onEventTap: (CalEvent) -> Void
    let onCreateEvent: (Date) -> Void
    let onShowWeek: (Date) -> Void
    let onShowDay: (Date) -> Void
    @Binding var visibleMonth: Date

    @AppStorage("appLanguage")       private var appLang = "system"
    @AppStorage("monthDividerColor") private var dividerHex = "#7090c0"
    @AppStorage("monthLabelColor")   private var labelHex = "#7090c0"
    @AppStorage("textColor")         private var textHex = "#FFFFFF"
    @AppStorage("lineColor")         private var lineHex = "#3A3A3C"
    @AppStorage("textContrast")      private var textContrast = 3

    @State private var scrolledWeek: Date? = nil
    @State private var didInitialScroll = false

    private var cal: Calendar { store.userCalendar }

    private var weekStarts: [Date] {
        let today = cal.startOfDay(for: .now)
        let thisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        return (-weeksBack...weeksAhead).compactMap {
            cal.date(byAdding: .weekOfYear, value: $0, to: thisWeek)
        }
    }

    private var weekdayHeaders: [String] {
        let fmt = DateFormatter(); fmt.locale = L10n.locale(appLang)
        let symbols = fmt.shortWeekdaySymbols ?? cal.shortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return (0..<7).map { i in String(symbols[(start + i) % 7].prefix(2)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {                    ForEach(weekStarts, id: \.self) { ws in
                        WeekRow(weekStart: ws,
                                store: store,
                                dividerColor: Color(hex: dividerHex),
                                labelColor: Color(hex: labelHex),
                                textColor: Color(hex: textHex),
                                lineColor: Color(hex: lineHex),
                                language: appLang,
                                onDayTap: onDayTap,
                                onEventTap: onEventTap,
                                onCreateEvent: onCreateEvent,
                                onShowWeek: onShowWeek,
                                onShowDay: onShowDay)
                            .id(ws)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrolledWeek, anchor: .top)
            .onAppear {
                if !didInitialScroll {
                    didInitialScroll = true
                    scrolledWeek = weekStart(for: store.currentDate)
                    publishVisibleMonth(from: scrolledWeek)
                }
            }
            .onChange(of: store.currentDate) { _, newDate in
                let target = weekStart(for: newDate)
                if scrolledWeek != target {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scrolledWeek = target
                    }
                }
            }
            .onChange(of: scrolledWeek) { _, newWeek in
                publishVisibleMonth(from: newWeek)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdayHeaders, id: \.self) { d in
                Text(d)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(hex: textHex).opacity(secondaryTextOpacity(textContrast)))
                    .frame(maxWidth: .infinity, minHeight: weekdayHeaderHeight)
            }
        }
    }

    private func weekStart(for date: Date) -> Date {
        cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
    }

    /// Determine the header month from the currently-scrolled week.
    /// Rule: take the month of the topmost visible week's start day. This
    /// means as long as the "1." of the next month is still visible in the
    /// top row, the header keeps showing the previous month – and only flips
    /// to the new month once its "1." has scrolled out of view above.
    private func publishVisibleMonth(from week: Date?) {
        guard let w = week else { return }
        let month = cal.date(from: cal.dateComponents([.year, .month], from: w)) ?? w
        if visibleMonth != month {
            visibleMonth = month
        }
    }
}

// MARK: – Week Row

private struct WeekRow: View {
    let weekStart: Date
    let store: CalendarStore
    let dividerColor: Color
    let labelColor: Color
    let textColor: Color
    let lineColor: Color
    let language: String
    let onDayTap: (Date) -> Void
    let onEventTap: (CalEvent) -> Void
    let onCreateEvent: (Date) -> Void
    let onShowWeek: (Date) -> Void
    let onShowDay: (Date) -> Void

    private var cal: Calendar { store.userCalendar }

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekNumber: Int { cal.component(.weekOfYear, from: weekStart) }

    private func columnRange(for ev: CalEvent) -> (startCol: Int, span: Int) {
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)!
        let evStart = max(cal.startOfDay(for: ev.startDate), weekStart)
        // All-day end is already exclusive; timed end-of-day-on-same-day shouldn't add a column.
        let rawEnd: Date
        if ev.isAllDay {
            rawEnd = ev.endDate
        } else {
            // Treat timed events as occupying days from start up to and including the day of end.
            rawEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: ev.endDate))!
        }
        let evEnd = min(rawEnd, weekEnd)
        let sc = max(0, cal.dateComponents([.day], from: weekStart, to: evStart).day ?? 0)
        let lastIncl = (cal.dateComponents([.day], from: weekStart, to: evEnd).day ?? 0) - 1
        let ec = min(6, lastIncl)
        return (sc, max(1, ec - sc + 1))
    }

    /// Greedy lane packing for events overlapping this week.
    private func packEvents() -> (placed: [(event: CalEvent, lane: Int, startCol: Int, span: Int)],
                                  extraPerCol: [Int]) {
        let weekEndExclusive = cal.date(byAdding: .day, value: 7, to: weekStart)!
        let evs = store.events(in: weekStart, end: weekEndExclusive)
            .sorted { a, b in
                if a.startDate != b.startDate { return a.startDate < b.startDate }
                return a.endDate > b.endDate
            }
        var laneLastEnd: [Int] = []
        var placed: [(CalEvent, Int, Int, Int)] = []
        var overflowPerCol = [Int](repeating: 0, count: 7)

        for ev in evs {
            let (sc, sp) = columnRange(for: ev)
            var assigned: Int? = nil
            for laneIdx in 0..<laneLastEnd.count {
                if laneLastEnd[laneIdx] < sc {
                    laneLastEnd[laneIdx] = sc + sp - 1
                    assigned = laneIdx
                    break
                }
            }
            if assigned == nil {
                if laneLastEnd.count < maxLanesPerWeek {
                    laneLastEnd.append(sc + sp - 1)
                    assigned = laneLastEnd.count - 1
                }
            }
            if let lane = assigned {
                placed.append((ev, lane, sc, sp))
            } else {
                for c in sc...min(6, sc + sp - 1) {
                    overflowPerCol[c] += 1
                }
            }
        }
        return (placed.map { (event: $0.0, lane: $0.1, startCol: $0.2, span: $0.3) },
                overflowPerCol)
    }

    var body: some View {
        let (placed, extras) = packEvents()
        let rowHeight = dayNumberRowHeight + CGFloat(maxLanesPerWeek) * (laneHeight + laneSpacing) + 4
        let mondayIdx = days.firstIndex(where: { cal.component(.weekday, from: $0) == 2 }) ?? 0

        // Where in this row does a new month start? (col 1...6 = mid-row step; nil = no step)
        let midRowBoundaryCol: Int? = {
            for idx in 1..<7 where cal.component(.day, from: days[idx]) == 1 { return idx }
            return nil
        }()
        let rowStartsNewMonth = cal.component(.day, from: days[0]) == 1

        GeometryReader { geo in
            let cellW = geo.size.width / 7

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
                        let edge: DividerEdge = {
                            if let b = midRowBoundaryCol {
                                return idx < b ? .bottomHighlight : .topHighlight
                            }
                            return rowStartsNewMonth ? .topHighlight : .none
                        }()
                        DayCell(date: day,
                                isToday: cal.isDateInToday(day),
                                monthLabelColor: labelColor,
                                dividerColor: dividerColor,
                                textColor: textColor,
                                lineColor: lineColor,
                                language: language,
                                extraCount: extras[idx],
                                weekNumber: idx == mondayIdx ? weekNumber : nil,
                                cwLabel: L10n.t("cal.cw", language),
                                edge: edge,
                                onTap: { onDayTap(day) },
                                onCreateEvent: { onCreateEvent(day) },
                                onShowWeek: { onShowWeek(day) },
                                onShowDay: { onShowDay(day) })
                            .frame(width: cellW, height: rowHeight)
                    }
                }

                ForEach(Array(placed.enumerated()), id: \.offset) { _, p in
                    Button { onEventTap(p.event) } label: {
                        EventBar(event: p.event)
                            .frame(width: cellW * CGFloat(p.span) - 2, height: laneHeight)
                    }
                    .buttonStyle(.plain)
                    .offset(x: CGFloat(p.startCol) * cellW + 1,
                            y: dayNumberRowHeight + CGFloat(p.lane) * (laneHeight + laneSpacing))
                }

                // Vertical connector at the month-boundary column – ties the bottom-line
                // of old-month cells to the top-line of new-month cells into a step.
                if let b = midRowBoundaryCol {
                    Rectangle()
                        .fill(dividerColor)
                        .frame(width: 1.5, height: rowHeight)
                        .offset(x: CGFloat(b) * cellW - 0.75, y: 0)
                }
            }
        }
        .frame(height: rowHeight)
    }
}

// MARK: – Day Cell

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    let monthLabelColor: Color
    let dividerColor: Color
    let textColor: Color
    let lineColor: Color
    let language: String
    let extraCount: Int
    let weekNumber: Int?
    let cwLabel: String
    let edge: DividerEdge
    let onTap: () -> Void
    let onCreateEvent: () -> Void
    let onShowWeek: () -> Void
    let onShowDay: () -> Void

    @AppStorage("textContrast") private var textContrast = 3
    @AppStorage("lineContrast") private var lineContrast = 3

    private var cal: Calendar { Calendar.current }
    private var dayNum: Int { cal.component(.day, from: date) }
    private var isFirstOfMonth: Bool { dayNum == 1 }

    private var monthAbbrev: String {
        let f = DateFormatter()
        f.locale = L10n.locale(language)
        f.dateFormat = "LLL"
        return f.string(from: date).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 4) {
                    Text("\(dayNum)")
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.white : textColor)
                        .frame(width: 22, height: 22)
                        .background(isToday ? Color.accentColor : Color.clear)
                        .clipShape(Circle())
                    if isFirstOfMonth {
                        Text(monthAbbrev)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(monthLabelColor)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 4)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(textColor.opacity(secondaryTextOpacity(textContrast)))
                        .padding(.leading, 4)
                }
                Spacer(minLength: 0)
                if let wn = weekNumber {
                    Text("\(cwLabel) \(wn)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(textColor.opacity(secondaryTextOpacity(textContrast)))
                        .padding(.trailing, 4)
                }
            }
            .padding(.bottom, 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .trailing) {
            Rectangle().fill(lineColor.opacity(gridLineOpacity(lineContrast))).frame(width: 0.5)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(edge == .topHighlight ? dividerColor : lineColor.opacity(gridLineOpacity(lineContrast)))
                .frame(height: edge == .topHighlight ? 1.5 : 0.5)
        }
        .overlay(alignment: .bottom) {
            if edge == .bottomHighlight {
                Rectangle().fill(dividerColor).frame(height: 1.5)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button { onCreateEvent() } label: {
                Label(L10n.t("cal.new_event", language), systemImage: "plus")
            }
            Button { onShowWeek() } label: {
                Label(L10n.t("cal.show_in_week_view", language),
                      systemImage: "calendar.day.timeline.leading")
            }
            Button { onShowDay() } label: {
                Label(L10n.t("cal.show_in_day_view", language), systemImage: "sun.max")
            }
        }
    }
}

// MARK: – Event Bar

private struct EventBar: View {
    let event: CalEvent
    @AppStorage("dimPastEvents") private var dimPast = false

    private var isPast: Bool { event.endDate < .now }

    var body: some View {
        HStack(spacing: 3) {
            Text(event.title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.leading, 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: event.effectiveColor))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .opacity(dimPast && isPast ? 0.5 : 1.0)
    }
}
