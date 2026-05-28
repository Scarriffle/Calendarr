import SwiftUI
import WidgetKit

struct CalendarDayWidgetView: View {
    let entry: CalendarrEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = WidgetL10n.locale(lang)
        c.firstWeekday = 2
        return c
    }

    private var weekDays: [Date] {
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date)) ?? entry.date
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var upcomingEvents: [WidgetEvent] {
        guard let s = snapshot else { return [] }
        return WidgetHelpers.upcoming(from: entry.date, daysAhead: 1, in: s)
    }

    private var monthFmt: DateFormatter {
        let f = DateFormatter(); f.locale = WidgetL10n.locale(lang); f.dateFormat = "LLLL"; return f
    }
    private var weekdayFmt: DateFormatter {
        let f = DateFormatter(); f.locale = WidgetL10n.locale(lang); f.dateFormat = "EEEE"; return f
    }
    private var timeFmt: DateFormatter {
        let f = DateFormatter(); f.locale = WidgetL10n.locale(lang); f.dateFormat = "HH:mm"; return f
    }

    var body: some View {
        if let s = snapshot {
            let primary = Color(widgetHex: s.primaryColorHex)
            let accent  = Color(widgetHex: s.accentColorHex)
            VStack(alignment: .leading, spacing: 0) {
                header(primary: primary)
                weekStrip(snapshot: s, primary: primary, accent: accent)
                    .padding(.vertical, 5)
                Rectangle()
                    .fill(Color(widgetHex: s.lineColorHex).opacity(0.4))
                    .frame(height: 0.5)
                    .padding(.bottom, 6)
                eventList(accent: accent)
            }
        } else {
            Text(WidgetL10n.t("widget.no_data", lang))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: – Header

    private func header(primary: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(cal.component(.day, from: entry.date))")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(primary)
                .frame(width: 44, alignment: .leading)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 1) {
                Text(monthFmt.string(from: entry.date).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(primary)
                Text("\(WidgetL10n.t("widget.today", lang)), \(weekdayFmt.string(from: entry.date))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    // MARK: – Week strip

    private func weekStrip(snapshot: WidgetSnapshot, primary: Color, accent: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                let isToday = cal.isDateInToday(day)
                let hasEvs  = !WidgetHelpers.events(for: day, in: snapshot).isEmpty
                VStack(spacing: 2) {
                    Text(shortDay(day))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isToday ? accent : .secondary)
                    ZStack {
                        if isToday {
                            Circle().fill(primary)
                        } else if hasEvs {
                            Circle().fill(accent.opacity(0.18))
                        }
                        Text("\(cal.component(.day, from: day))")
                            .font(.system(size: 11, weight: isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? .white : .primary)
                    }
                    .frame(width: 22, height: 22)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func shortDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "EEE"
        return String(f.string(from: date).prefix(2)).uppercased()
    }

    // MARK: – Event list

    @ViewBuilder
    private func eventList(accent: Color) -> some View {
        if upcomingEvents.isEmpty {
            Text(WidgetL10n.t("widget.no_events", lang))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(upcomingEvents.prefix(3)) { ev in
                    HStack(alignment: .center, spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(widgetHex: ev.colorHex))
                            .frame(width: 3, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ev.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(ev.isAllDay
                                 ? WidgetL10n.t("widget.allday", lang)
                                 : "\(timeFmt.string(from: ev.start)) – \(timeFmt.string(from: ev.end))")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
