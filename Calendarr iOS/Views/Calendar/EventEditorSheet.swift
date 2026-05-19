import SwiftUI

struct EventEditorSheet: View {
    let api: CalendarrAPI
    let store: CalendarStore
    let initialDate: Date
    let editingEvent: CalEvent?
    let onSaved: () async -> Void

    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var appLang = "system"
    @State private var title = ""
    @State private var isAllDay = false
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var location = ""
    @State private var notes = ""
    @State private var selectedCalendarId: String = ""
    @State private var color = ""
    @State private var isSaving = false
    @State private var error = ""

    private var isEditing: Bool { editingEvent != nil }

    private var selectedCal: WritableCalendar? {
        store.writableCalendars.first { $0.id == selectedCalendarId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.t("event.title_placeholder", appLang), text: $title)
                        .font(.body.weight(.medium))
                }

                Section {
                    Toggle(L10n.t("event.allday", appLang), isOn: $isAllDay.animation())
                        .tint(Color.accentColor)

                    if isAllDay {
                        DatePicker(L10n.t("event.start", appLang), selection: $startDate, displayedComponents: .date)
                        DatePicker(L10n.t("event.end",   appLang), selection: $endDate,   displayedComponents: .date)
                    } else {
                        DatePicker(L10n.t("event.start", appLang), selection: $startDate)
                        DatePicker(L10n.t("event.end",   appLang), selection: $endDate)
                    }
                }

                Section {
                    TextField(L10n.t("event.location",    appLang), text: $location)
                    TextField(L10n.t("event.description", appLang), text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section(L10n.t("event.calendar_section", appLang)) {
                    if store.writableCalendars.isEmpty {
                        Text(L10n.t("event.no_writable", appLang))
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        Picker(L10n.t("event.calendar_picker", appLang), selection: $selectedCalendarId) {
                            ForEach(store.writableCalendars) { cal in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: cal.color))
                                        .frame(width: 10, height: 10)
                                    Text(cal.name)
                                }
                                .tag(cal.id)
                            }
                        }
                    }
                }

                Section(L10n.t("event.color_section", appLang)) {
                    HStack {
                        Text(L10n.t("event.color", appLang))
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: color.isEmpty ? (selectedCal?.color ?? "#4285f4") : color) },
                            set: { color = $0.toHex() }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        if !color.isEmpty {
                            Button(L10n.t("event.reset_color", appLang)) { color = "" }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !error.isEmpty {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing
                             ? L10n.t("event.edit_title", appLang)
                             : L10n.t("event.new_title",  appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel", appLang)) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isEditing
                           ? L10n.t("event.save", appLang)
                           : L10n.t("event.add",  appLang)) {
                        Task { await save() }
                    }
                    .bold()
                    .disabled(title.isEmpty || selectedCalendarId.isEmpty || isSaving)
                }
            }
        }
        .onAppear { setup() }
    }

    private func setup() {
        if let ev = editingEvent {
            title = ev.title
            isAllDay = ev.isAllDay
            startDate = ev.startDate
            endDate = ev.endDate
            location = ev.location
            notes = ev.notes
            color = ev.color ?? ""
            selectedCalendarId = ev.calendarId
        } else {
            let cal = Calendar.current
            startDate = cal.date(bySettingHour: cal.component(.hour, from: initialDate),
                                 minute: 0, second: 0, of: initialDate) ?? initialDate
            endDate = startDate.addingTimeInterval(3600)
            selectedCalendarId = store.writableCalendars.first?.id ?? ""
        }
    }

    private func save() async {
        guard let cal = selectedCal else { return }
        isSaving = true
        error = ""
        defer { isSaving = false }

        let colorVal: String? = color.isEmpty ? nil : color
        let start = isAllDay ? Calendar.current.startOfDay(for: startDate) : startDate
        let end = isAllDay ? Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: endDate)!) : endDate

        do {
            if let ev = editingEvent {
                if ev.source == "local" {
                    try await api.updateLocalEvent(uid: ev.id, title: title, start: start, end: end,
                                                   isAllDay: isAllDay, location: location, description: notes, color: colorVal)
                } else {
                    let calId = Int(ev.calendarId)
                    try await api.updateCalDAVEvent(uid: ev.id, url: ev.url, calendarId: calId,
                                                    title: title, start: start, end: end, isAllDay: isAllDay,
                                                    location: location, description: notes, color: colorVal)
                }
            } else {
                switch cal.source {
                case "local":
                    _ = try await api.createLocalEvent(calendarId: cal.numericId, title: title,
                                                       start: start, end: end, isAllDay: isAllDay,
                                                       location: location, description: notes, color: colorVal)
                case "google":
                    try await api.createGoogleEvent(calendarDbId: cal.numericId, title: title,
                                                    start: start, end: end, isAllDay: isAllDay,
                                                    location: location, description: notes)
                case "homeassistant":
                    try await api.createHAEvent(calendarId: cal.numericId, title: title,
                                                start: start, end: end, isAllDay: isAllDay,
                                                location: location, description: notes)
                default: // caldav
                    try await api.createCalDAVEvent(calendarId: cal.numericId, title: title,
                                                    start: start, end: end, isAllDay: isAllDay,
                                                    location: location, description: notes, color: colorVal)
                }
            }
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
