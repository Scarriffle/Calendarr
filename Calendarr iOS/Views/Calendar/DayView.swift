import SwiftUI

struct DayView: View {
    let store: CalendarStore
    let onEventTap: (CalEvent) -> Void
    let onTimeTap: (Date) -> Void

    private var cal: Calendar { store.userCalendar }
    private var allDayEvents: [CalEvent] { store.events(on: store.currentDate).filter(\.isAllDay) }
    private var timedEvents: [CalEvent] { store.events(on: store.currentDate).filter { !$0.isAllDay } }

    var body: some View {
        VStack(spacing: 0) {
            if !allDayEvents.isEmpty { allDayStrip }

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            // Background grid
                            HStack(alignment: .top, spacing: 0) {
                                timeLabels
                                VStack(spacing: 0) {
                                    ForEach(hours, id: \.self) { _ in
                                        Rectangle()
                                            .fill(Color(.separator).opacity(0.4))
                                            .frame(height: 0.5)
                                        Color.clear.frame(height: hourHeight - 0.5)
                                    }
                                }
                                .frame(width: geo.size.width - timeColumnWidth)
                                .contentShape(Rectangle())
                                .onTapGesture { loc in
                                    let h = Int(loc.y / hourHeight)
                                    let m = Int((loc.y.truncatingRemainder(dividingBy: hourHeight)) / hourHeight * 60)
                                    let date = cal.date(bySettingHour: h, minute: m, second: 0, of: store.currentDate) ?? store.currentDate
                                    onTimeTap(date)
                                }
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
                                HStack(spacing: 0) {
                                    Spacer().frame(width: timeColumnWidth - 4)
                                    Circle().fill(Color.red).frame(width: 8, height: 8)
                                    Rectangle().fill(Color.red)
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
                        .foregroundStyle(.secondary)
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
