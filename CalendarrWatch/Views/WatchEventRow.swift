import SwiftUI
import CalendarrCore

/// One event: a colour bar for the calendar, the time range, the title.
struct WatchEventRow: View {
    let event: SnapshotEvent
    let language: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(watchHex: event.colorHex))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(WatchEventFormat.timeRange(event, language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(event.title)
                    .font(.system(size: 14))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension Color {
    /// Local copy of the hex initialiser: `CalendarrCore` is Foundation-only by
    /// design, so colour parsing cannot live there.
    init(watchHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        guard cleaned.count == 6 else { self = .gray; return }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

enum WatchEventFormat {
    static func timeRange(_ event: SnapshotEvent, language: String,
                          calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        if event.isAllDay { return WatchL10n.t("watch.allday", language) }

        let time = DateFormatter()
        time.locale = WatchL10n.locale(language)
        time.dateFormat = "HH:mm"

        let start = time.string(from: event.start)
        guard event.end > event.start else { return start }

        // Without the weekday, an event running from Wednesday to Monday reads
        // as a one-hour slot: "00:00 – 01:00" is true and useless.
        if calendar.startOfDay(for: event.end) > calendar.startOfDay(for: event.start) {
            let day = DateFormatter()
            day.locale = WatchL10n.locale(language)
            day.setLocalizedDateFormatFromTemplate("EEE")
            return "\(day.string(from: event.start)) \(start) – "
                 + "\(day.string(from: event.end)) \(time.string(from: event.end))"
        }
        return "\(start) – \(time.string(from: event.end))"
    }

    static func time(_ date: Date, language: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "Heute", "Morgen", else "Do 11. Sep".
    static func dayHeader(_ day: Date, language: String,
                          calendar: Calendar, now: Date = Date()) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return WatchL10n.t("watch.today", language)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return WatchL10n.t("watch.tomorrow", language)
        }
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: day)
    }
}
