import Foundation
import WidgetKit
import CalendarrCore

/// What the watch views read. Holds the last received snapshot, the calendar
/// list, and this watch's filter.
@MainActor
@Observable
final class WatchSnapshotModel {
    private(set) var result: SnapshotReadResult = .neverWritten
    private(set) var calendars: [SnapshotCalendar] = []
    private(set) var hiddenKeys: Set<String> = WatchFilterStore.load()

    private let store = SnapshotStore()
    private var changeToken: SnapshotChangeNotifier.ObservationToken?

    init() {
        reload()
        // The receiver writes through SnapshotStore, which broadcasts. Listening
        // here means the UI does not have to be notified separately.
        changeToken = SnapshotChangeNotifier.observe { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        result = store.read()
        calendars = store.readCalendars()
    }

    /// The snapshot with this watch's filter applied, or nil when there is
    /// nothing usable to show.
    var visible: CalendarrSnapshot? {
        result.snapshot?.filtered(excludingCalendarKeys: hiddenKeys)
    }

    var language: String { result.snapshot?.language ?? "system" }

    func isHidden(_ key: String) -> Bool { hiddenKeys.contains(key) }

    /// The display name for an event's calendar. Events carry only a
    /// `calendarKey`; the names travel separately, in the calendar list.
    func calendarName(for key: String) -> String? {
        calendars.first { $0.id == key }?.name
    }

    func setHidden(_ key: String, _ hidden: Bool) {
        if hidden { hiddenKeys.insert(key) } else { hiddenKeys.remove(key) }
        WatchFilterStore.save(hiddenKeys)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
