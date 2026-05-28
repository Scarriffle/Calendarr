import SwiftUI
import WidgetKit

struct NowNextWidgetView: View {
    let entry: CalendarrEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var lang: String { snapshot?.language ?? "system" }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = WidgetL10n.locale(lang)
        return c
    }

    private var timeFmt: DateFormatter {
        let f = DateFormatter(); f.locale = WidgetL10n.locale(lang); f.dateFormat = "HH:mm"; return f
    }
    private var dayOfWeekFmt: DateFormatter {
        let f = DateFormatter(); f.locale = WidgetL10n.locale(lang); f.dateFormat = "EEEE"; return f
    }

    // Currently running event, or next upcoming timed event, or first all-day event
    private var featuredEvent: WidgetEvent? {
        guard let s = snapshot else { return nil }
        let pool = WidgetHelpers.upcoming(from: entry.date, daysAhead: 1, in: s)
        if let running = pool.first(where: { !$0.isAllDay && $0.start <= entry.date }) { return running }
        if let next    = pool.first(where: { !$0.isAllDay }) { return next }
        return pool.first
    }

    // All upcoming events today except the featured one
    private var remainingEvents: [WidgetEvent] {
        guard let s = snapshot else { return [] }
        let pool = WidgetHelpers.upcoming(from: entry.date, daysAhead: 1, in: s)
        guard let featured = featuredEvent else { return pool }
        return pool.filter { $0.id != featured.id }
    }

    private func timeRange(_ ev: WidgetEvent) -> String {
        ev.isAllDay
            ? WidgetL10n.t("widget.allday", lang)
            : "\(timeFmt.string(from: ev.start)) – \(timeFmt.string(from: ev.end))"
    }

    var body: some View {
        if let s = snapshot {
            let line = Color(widgetHex: s.lineColorHex)
            VStack(spacing: 6) {
                featuredCard(snapshot: s)
                bottomRow(line: line)
            }
        } else {
            Text(WidgetL10n.t("widget.no_data", lang))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: – Featured event card

    private func featuredCard(snapshot: WidgetSnapshot) -> some View {
        let ev        = featuredEvent
        let baseColor = ev.map { Color(widgetHex: $0.colorHex) } ?? Color.accentColor.opacity(0.5)

        return ZStack(alignment: .leading) {
            LinearGradient(
                colors: [baseColor.opacity(0.75), baseColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ev?.title ?? WidgetL10n.t("widget.no_events", lang))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(ev.map { timeRange($0) } ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.leading, 10)
                .padding(.vertical, 9)
                Spacer()
                if ev != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.trailing, 12)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: – Bottom: date + event list

    private func bottomRow(line: Color) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: day name + large number
            VStack(alignment: .leading, spacing: 0) {
                Text(dayOfWeekFmt.string(from: entry.date).uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(cal.component(.day, from: entry.date))")
                    .font(.system(size: 30, weight: .light))
            }
            .frame(width: 50, alignment: .leading)

            // Divider
            line.opacity(0.4).frame(width: 0.5)
                .padding(.horizontal, 6)

            // Right: event list
            VStack(alignment: .leading, spacing: 4) {
                let shown = remainingEvents.prefix(2)
                if shown.isEmpty {
                    Text(WidgetL10n.t("widget.no_events", lang))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shown) { ev in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Circle()
                                .fill(Color(widgetHex: ev.colorHex))
                                .frame(width: 7, height: 7)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(ev.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Text(timeRange(ev))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            // +N badge
            if remainingEvents.count > 2 {
                Text("+\(remainingEvents.count - 2)")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.18), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
