import SwiftUI
import CalendarrCore

/// Everything the snapshot carries about one event, which is deliberately not
/// everything the server knows: notes, recurrence and permissions are dropped
/// on the way out, so there is nothing here to edit.
struct WatchEventDetailView: View {
    let event: SnapshotEvent
    /// Nil when the calendar list has not arrived yet, which is possible right
    /// after a first install.
    let calendarName: String?
    let language: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(Color(watchHex: event.colorHex))
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    Text(event.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label(WatchEventFormat.timeRange(event, language: language),
                      systemImage: "clock")
                    .font(.footnote)

                Label(dateLine, systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let calendarName {
                    Label(calendarName, systemImage: "list.bullet.rectangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: event.start)
    }
}
