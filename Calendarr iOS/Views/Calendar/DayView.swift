import SwiftUI

struct DayView: View {
    let store: CalendarStore
    let onEventTap: (CalEvent) -> Void
    let onCreateEvent: (Date) -> Void

    @AppStorage("appLanguage")   private var appLang = "system"
    @AppStorage("todayColor")    private var todayHex = "#4285f4"
    @AppStorage("textColor")     private var textHex = "#FFFFFF"
    @AppStorage("lineColor")     private var lineHex = "#3A3A3C"
    @AppStorage("textContrast")  private var textContrast = 3
    @AppStorage("hourHeight")    private var hourHeightPref = 60   // observed for live re-layout

    private var cal: Calendar { store.userCalendar }
    private var allDayEvents: [CalEvent] {
        store.events(on: store.currentDate).filter { $0.isAllDay || eventSpansMultipleDays($0) }
    }
    private var timedEvents: [CalEvent] {
        store.events(on: store.currentDate).filter { !$0.isAllDay && !eventSpansMultipleDays($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !allDayEvents.isEmpty { allDayStrip }

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            // Background grid with per-hour context menus
                            HStack(alignment: .top, spacing: 0) {
                                timeLabels
                                VStack(spacing: 0) {
                                    ForEach(hours, id: \.self) { hour in
                                        DayHourSlot(day: store.currentDate, hour: hour,
                                                    hourHeight: hourHeight,
                                                    language: appLang,
                                                    onCreateEvent: onCreateEvent)
                                    }
                                }
                                .frame(width: geo.size.width - timeColumnWidth)
                            }

                            // Events
                            let evWidth = geo.size.width - timeColumnWidth - 2
                            ForEach(timedEvents) { ev in
                                Button(action: { onEventTap(ev) }) {
                                    EventBlock(event: ev)
                                }
                                .buttonStyle(.plain)
                                .frame(width: evWidth, height: max(eventHeight(ev), 18))
                                .offset(x: timeColumnWidth + 1, y: eventTop(ev))
                            }

                            // Current time
                            if cal.isDateInToday(store.currentDate) {
                                let lineY = nowLineY()
                                let nowColor = Color(hex: todayHex)
                                HStack(spacing: 0) {
                                    Spacer().frame(width: timeColumnWidth - 4)
                                    Circle().fill(nowColor).frame(width: 8, height: 8)
                                    Rectangle().fill(nowColor)
                                        .frame(width: geo.size.width - timeColumnWidth - 4, height: 1.5)
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
    }

    private var allDayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(allDayEvents) { ev in
                    Button(action: { onEventTap(ev) }) {
                        Text(ev.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color(hex: ev.effectiveColor))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var timeLabels: some View {
        VStack(spacing: 0) {
            ForEach(hours, id: \.self) { h in
                ZStack(alignment: .topTrailing) {
                    Color.clear.frame(height: hourHeight)
                    Text(String(format: "%02d:00", h))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: textHex).opacity(secondaryTextOpacity(textContrast)))
                        .offset(y: -6)
                }
            }
            Color.clear.frame(height: 80)
        }
        .frame(width: timeColumnWidth)
    }

    private func nowLineY() -> CGFloat {
        let cal = Calendar.current
        let h = CGFloat(cal.component(.hour, from: Date()))
        let m = CGFloat(cal.component(.minute, from: Date()))
        return h * hourHeight + m * hourHeight / 60
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

// One-hour slot for the single-column day view.
private struct DayHourSlot: View {
    let day: Date
    let hour: Int
    let hourHeight: CGFloat
    let language: String
    let onCreateEvent: (Date) -> Void

    @AppStorage("lineColor")    private var lineHex = "#3A3A3C"
    @AppStorage("lineContrast") private var lineContrast = 3

    private var date: Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(hex: lineHex).opacity(gridLineOpacity(lineContrast))).frame(height: 0.5)
            Color.clear.frame(height: hourHeight - 0.5)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button { onCreateEvent(date) } label: {
                Label(L10n.t("cal.new_event", language), systemImage: "plus")
            }
        }
    }
}
