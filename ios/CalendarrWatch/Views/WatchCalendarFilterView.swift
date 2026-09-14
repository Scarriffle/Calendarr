import SwiftUI
import CalendarrCore

/// Narrows what this watch shows, on top of what the phone already filtered.
/// One toggle here affects the agenda and every complication at once.
struct WatchCalendarFilterView: View {
    @Environment(WatchSnapshotModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if model.calendars.isEmpty {
                    Text(WatchL10n.t("watch.waiting", model.language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.calendars) { calendar in
                        row(calendar)
                    }
                }
            }
            .navigationTitle(WatchL10n.t("watch.calendars", model.language))
        }
    }

    private func row(_ calendar: SnapshotCalendar) -> some View {
        let shown = !model.isHidden(calendar.id)
        return Button {
            model.setHidden(calendar.id, shown)
        } label: {
            HStack(spacing: 8) {
                // A checkbox, not a Toggle: a switch reads as a state indicator
                // you wait on rather than a control you tap.
                Image(systemName: shown ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(shown ? Color.accentColor : Color.secondary)
                Circle()
                    .fill(Color(watchHex: calendar.colorHex))
                    .frame(width: 7, height: 7)
                Text(calendar.name)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(shown ? [.isSelected] : [])
    }
}
