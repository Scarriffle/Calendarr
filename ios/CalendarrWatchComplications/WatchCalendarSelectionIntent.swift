import AppIntents
import WidgetKit
import CalendarrCore

/// One calendar option in a complication's configuration.
struct WatchCalendarEntity: AppEntity, Identifiable {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kalender"
    static var defaultQuery = WatchCalendarEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

/// Reads the calendars from this watch's App Group container, so configuration
/// needs no network call and no phone.
struct WatchCalendarEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WatchCalendarEntity] {
        let wanted = Set(identifiers)
        return SnapshotStore().readCalendars()
            .filter { wanted.contains($0.id) }
            .map { WatchCalendarEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [WatchCalendarEntity] {
        SnapshotStore().readCalendars().map { WatchCalendarEntity(id: $0.id, name: $0.name) }
    }
}

/// Per-complication override of the calendar selection. The in-app toggles are
/// the primary path — intent configuration on a watch face is awkward to
/// operate — so an empty selection means "whatever the app is set to".
struct WatchCalendarSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Kalender auswählen"
    static var description = IntentDescription("Leer = die Auswahl aus der Watch-App.")

    // Must be optional: WidgetConfigurationIntent requires optional parameter
    // types, and the watchOS SDK enforces it where iOS lets a bare array pass.
    @Parameter(title: "Kalender")
    var selectedCalendars: [WatchCalendarEntity]?
}
