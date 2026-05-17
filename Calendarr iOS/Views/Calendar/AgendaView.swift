import SwiftUI

struct AgendaView: View {
    let store: CalendarStore
    let onEventTap: (CalEvent) -> Void

    private var cal: Calendar { store.userCalendar }

    private var grouped: [(Date, [CalEvent])] {
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 90, to: start)!
        var dict: [Date: [CalEvent]] = [:]
        for ev in store.events(in: start, end: end) {
            let key = cal.startOfDay(for: ev.startDate)
            dict[key, default: []].append(ev)
        }
        return dict.keys.sorted().map { ($0, dict[$0]!.sorted { $0.startDate < $1.startDate }) }
    }

    private let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d. MMMM yyyy"
        return f
    }()

    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        if grouped.isEmpty {
            ContentUnavailableView(
                "Keine Termine",
                systemImage: "calendar",
                description: Text("In den nächsten 90 Tagen sind keine Termine vorhanden.")
            )
        } else {
            List {
                ForEach(grouped, id: \.0) { day, evs in
                    Section {
                        ForEach(evs) { ev in
                            Button { onEventTap(ev) } label: {
                                AgendaEventRow(event: ev, timeFmt: timeFmt)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(dayFmt.string(from: day))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(cal.isDateInToday(day) ? Color.accentColor : .secondary)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct AgendaEventRow: View {
    let event: CalEvent
    let timeFmt: DateFormatter

    var timeString: String {
        if event.isAllDay { return "Ganztägig" }
        return timeFmt.string(from: event.startDate)
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: event.effectiveColor))
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(timeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !event.location.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(event.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(event.calendarName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
