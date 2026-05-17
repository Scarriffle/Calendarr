import SwiftUI

// Shared constants used by WeekView, DayView, EventEditorSheet
let hourHeight: CGFloat = 60
let timeColumnWidth: CGFloat = 44
let hours = Array(0..<24)

// Position helpers
func eventTop(_ ev: CalEvent) -> CGFloat {
    let cal = Calendar.current
    let h = CGFloat(cal.component(.hour, from: ev.startDate))
    let m = CGFloat(cal.component(.minute, from: ev.startDate))
    return h * hourHeight + m * hourHeight / 60
}

func eventHeight(_ ev: CalEvent) -> CGFloat {
    let dur = ev.endDate.timeIntervalSince(ev.startDate)
    return max(CGFloat(dur / 3600) * hourHeight, 20)
}

// Shared event block used in WeekView and DayView
struct EventBlock: View {
    let event: CalEvent

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: event.effectiveColor).opacity(0.85))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if !event.location.isEmpty {
                        Text(event.location)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .padding(4)
            }
            .padding(.horizontal, 1)
    }
}
