import AppIntents
import WidgetKit

/// An individual calendar option shown in the widget configuration picker.
struct CalendarAppEntity: AppEntity, Identifiable {
    let id: String
    let name: String
    let colorHex: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kalender"
    static var defaultQuery = CalendarEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

/// Reads available calendars from the App Group container so the widget
/// extension can offer options without a network call.
struct CalendarEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CalendarAppEntity] {
        let ids = Set(identifiers)
        return WidgetStore.readCalendars()
            .filter { ids.contains($0.id) }
            .map { CalendarAppEntity(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
    }

    func suggestedEntities() async throws -> [CalendarAppEntity] {
        WidgetStore.readCalendars()
            .map { CalendarAppEntity(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
    }
}

/// Widget configuration intent: lets the user pick which calendars to show.
/// No selection means "show all calendars" (the default).
///
/// The parameter must be optional: WidgetConfigurationIntent requires every
/// parameter type to be optional, and the macOS/Mac Catalyst SDK enforces that
/// where the iOS one lets a bare array through. `nil` and `[]` are treated
/// alike downstream, so this is behaviour-preserving.
struct CalendarSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Kalender auswählen"
    static var description = IntentDescription("Wähle welche Kalender im Widget angezeigt werden. Leer = alle Kalender.")

    @Parameter(title: "Kalender")
    var selectedCalendars: [CalendarAppEntity]?
}
