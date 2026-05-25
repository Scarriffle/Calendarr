import SwiftUI
import WidgetKit

private let rowHeight: CGFloat = 16
private let dayHeaderHeight: CGFloat = 14
private let maxEventsPerDay: Int = 3
private let maxTotalRows: Int = 15

struct UpcomingWidgetView: View {
    let entry: CalendarrEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var groupedWithLimits: [(Date, [WidgetEvent], Int)] {
        guard let s = snapshot else { return [] }
        let cal = Calendar.current
        let now = entry.date
        let events = WidgetHelpers.upcoming(from: now, daysAhead: 5, in: s)
        var buckets: [Date: [WidgetEvent]] = [:]
        for ev in events {
            let key = cal.startOfDay(for: ev.start)
            buckets[key, default: []].append(ev)
        }
        
        var result: [(Date, [WidgetEvent], Int)] = []
        var totalRows = 0
        
        for date in buckets.keys.sorted() {
            let allEventsForDay = buckets[date] ?? []
            let eventsToShow = Array(allEventsForDay.prefix(maxEventsPerDay))
            let hiddenCount = allEventsForDay.count - eventsToShow.count
            
            // Account for day header + event rows + potential "more" row
            let rowsForThisDay = 1 + eventsToShow.count + (hiddenCount > 0 ? 1 : 0)
            
            if totalRows + rowsForThisDay <= maxTotalRows {
                result.append((date, eventsToShow, hiddenCount))
                totalRows += rowsForThisDay
            } else {
                break
            }
        }
        
        return result
    }

    private var timeFmt: DateFormatter {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "HH:mm"
        return f
    }

    private var dayFmt: DateFormatter {
        let f = DateFormatter()
        f.locale = WidgetL10n.locale(lang)
        f.dateFormat = "EEE d. MMM"
        return f
    }

    var body: some View {
        let primary = Color(widgetHex: snapshot?.primaryColorHex ?? "#4285f4")
        let accent  = Color(widgetHex: snapshot?.accentColorHex ?? "#ea4335")
        VStack(alignment: .leading, spacing: 2) {
            Text(WidgetL10n.t("widget.upcoming", lang))
                .font(.caption.weight(.bold))
                .foregroundStyle(primary)
                .padding(.bottom, 2)
            if snapshot == nil {
                Text(WidgetL10n.t("widget.no_data", lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groupedWithLimits.isEmpty {
                Text(WidgetL10n.t("widget.no_events", lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(groupedWithLimits, id: \.0) { day, evs, hiddenCount in
                        dayHeader(d: day, accent: accent)
                        ForEach(evs) { ev in
                            eventRow(ev)
                        }
                        if hiddenCount > 0 {
                            moreRow(count: hiddenCount, accent: accent)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func dayHeader(d: Date, accent: Color) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(d)
        return Text(dayFmt.string(from: d))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isToday ? accent : .secondary)
            .frame(height: dayHeaderHeight, alignment: .bottomLeading)
            .padding(.top, 1)
    }

    private func eventRow(_ ev: WidgetEvent) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(widgetHex: ev.colorHex))
                .frame(width: 2.5)
            Text(ev.isAllDay ? WidgetL10n.t("widget.allday", lang) : timeFmt.string(from: ev.start))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
            Text(ev.title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: rowHeight)
    }
    
    private func moreRow(count: Int, accent: Color) -> some View {
        Text(String(format: WidgetL10n.t("widget.more", lang), count))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(accent)
            .frame(height: rowHeight)
    }
}
