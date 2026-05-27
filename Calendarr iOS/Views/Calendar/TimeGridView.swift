import SwiftUI

// Shared constants used by WeekView, DayView, EventEditorSheet
let timeColumnWidth: CGFloat = 44
let hours = Array(0..<24)

/// Live hour-row height, driven by the synced `hourHeight` setting.
/// Falls back to 60 when unset (fresh install / value 0). Views that lay out
/// against this also observe `@AppStorage("hourHeight")` so their body
/// re-renders when it changes.
var hourHeight: CGFloat {
    let v = UserDefaults.standard.integer(forKey: "hourHeight")
    return v > 0 ? CGFloat(v) : 60
}

/// Opacity for secondary text (weekday headers, time labels, "+N"/"KW"),
/// mapped from the 1–4 `textContrast` level. Level 3 ≈ the previous hard-coded
/// look so existing installs are visually unchanged.
func secondaryTextOpacity(_ level: Int) -> Double {
    switch level {
    case 1:  return 0.4
    case 2:  return 0.55
    case 4:  return 1.0
    default: return 0.75
    }
}

/// Opacity for grid lines / separators, mapped from the 1–4 `lineContrast`
/// level. Level 3 ≈ the previous hard-coded ~0.4 look.
func gridLineOpacity(_ level: Int) -> Double {
    switch level {
    case 1:  return 0.15
    case 2:  return 0.3
    case 4:  return 0.8
    default: return 0.5
    }
}

/// A timed (non-all-day) event that crosses a day boundary. Such events must
/// NOT be placed in the hourly grid — their height would be `duration ×
/// hourHeight`, i.e. taller than the whole day, rendering as a giant block
/// (and, sharing one id across days, only drawing on the first day). They are
/// shown in the all-day strip instead, like all-day events.
func eventSpansMultipleDays(_ ev: CalEvent) -> Bool {
    guard !ev.isAllDay, ev.endDate > ev.startDate else { return false }
    let cal = Calendar.current
    // End is exclusive: an event ending exactly at midnight is still single-day.
    let lastInstant = ev.endDate.addingTimeInterval(-1)
    return !cal.isDate(ev.startDate, inSameDayAs: lastInstant)
}

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
    @AppStorage("dimPastEvents") private var dimPast = false

    private var isPast: Bool { event.endDate < .now }

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
            .opacity(dimPast && isPast ? 0.5 : 1.0)
    }
}
