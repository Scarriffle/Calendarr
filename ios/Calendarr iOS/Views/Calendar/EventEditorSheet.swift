import SwiftUI

struct EventEditorSheet: View {
    let api: CalendarrAPI
    let store: CalendarStore
    let initialDate: Date
    let editingEvent: CalEvent?
    var copyFrom: CalEvent? = nil
    let onSaved: () async -> Void

    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var appLang = "system"
    @AppStorage("defaultReminderMinutes") private var defaultReminderMinutes = -1
    @AppStorage("defaultEventDurationMinutes") private var defaultEventDurationMinutes = 60
    @State private var title = ""
    @State private var isAllDay = false
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var location = ""
    @State private var notes = ""
    @State private var selectedCalendarId: String = ""
    @State private var color = ""
    @State private var isPrivate = false
    @State private var reminders: [Int] = []
    @State private var isSaving = false
    @State private var error = ""

    private var isEditing: Bool { editingEvent != nil }
    private var isCopying: Bool { copyFrom != nil && editingEvent == nil }

    private var selectedCal: WritableCalendar? {
        store.writableCalendars.first { $0.id == selectedCalendarId }
    }

    /// True when the selected calendar has its reminders muted: we keep any
    /// existing reminders on the event (never delete them) but grey out the
    /// controls and explain that they won't fire.
    private var remindersDisabled: Bool {
        guard let cal = selectedCal else { return false }
        let key = CalendarStore.calendarKey(source: cal.source, calendarId: String(cal.numericId))
        return store.reminderDisabledKeys.contains(key)
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

                if selectedCal?.source == "local" {
                    Section {
                        Toggle(L10n.t("event.private", appLang), isOn: $isPrivate)
                            .tint(Color.accentColor)
                    }

                    Section {
                        ForEach(reminders.indices, id: \.self) { idx in
                            ReminderEditRow(minutes: $reminders[idx], appLang: appLang)
                        }
                        .onDelete { reminders.remove(atOffsets: $0) }
                        Button {
                            let next = ReminderOptions.presets.first { !reminders.contains($0) }
                                ?? ReminderOptions.customDefault
                            reminders.append(next)
                        } label: {
                            Label(ReminderOptions.addLabel(appLang), systemImage: "bell.badge.plus")
                        }
                    } header: {
                        Text(ReminderOptions.sectionTitle(appLang))
                    } footer: {
                        if remindersDisabled {
                            Text(ReminderOptions.disabledNote(appLang)).foregroundStyle(.orange)
                        }
                    }
                    .disabled(remindersDisabled)
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
            .navigationTitle(
                isEditing  ? L10n.t("event.edit_title",  appLang) :
                isCopying  ? L10n.t("event.copy_title",  appLang) :
                             L10n.t("event.new_title",   appLang)
            )
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
        .onChange(of: startDate) { oldStart, newStart in
            guard newStart >= endDate else { return }
            let duration = endDate.timeIntervalSince(oldStart)
            let minDuration: TimeInterval = isAllDay ? 86400 : 3600
            endDate = newStart.addingTimeInterval(max(duration, minDuration))
        }
    }

    private func setup() {
        if let ev = editingEvent {
            title = ev.title
            isAllDay = ev.isAllDay
            startDate = ev.startDate
            // All-day end dates are stored as exclusive (day after last); subtract 1 for the picker.
            endDate = ev.isAllDay
                ? Calendar.current.date(byAdding: .day, value: -1, to: ev.endDate) ?? ev.endDate
                : ev.endDate
            location = ev.location
            notes = ev.notes
            color = ev.color ?? ""
            isPrivate = ev.isPrivate
            reminders = ev.reminders
            // HA events use "homeassistant-42" in CalEvent but "ha-42" in WritableCalendar
            if ev.source == "homeassistant" {
                let num = ev.calendarId.replacingOccurrences(of: "homeassistant-", with: "")
                selectedCalendarId = "ha-\(num)"
            } else {
                selectedCalendarId = ev.calendarId
            }
        } else if let ev = copyFrom {
            title = ev.title
            isAllDay = ev.isAllDay
            startDate = ev.startDate
            endDate = ev.isAllDay
                ? Calendar.current.date(byAdding: .day, value: -1, to: ev.endDate) ?? ev.endDate
                : ev.endDate
            location = ev.location
            notes = ev.notes
            color = ev.color ?? ""
            isPrivate = ev.isPrivate
            reminders = ev.reminders
            selectedCalendarId = store.writableCalendars.first?.id ?? ""
        } else {
            let cal = Calendar.current
            startDate = cal.date(bySettingHour: cal.component(.hour, from: initialDate),
                                 minute: 0, second: 0, of: initialDate) ?? initialDate
            let durMin = defaultEventDurationMinutes > 0 ? defaultEventDurationMinutes : 60
            endDate = startDate.addingTimeInterval(Double(durMin) * 60)
            selectedCalendarId = store.writableCalendars.first?.id ?? ""
            // New events inherit the user's default reminder (editable).
            if defaultReminderMinutes >= 0 { reminders = [defaultReminderMinutes] }
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
                switch ev.source {
                case "local":
                    try await api.updateLocalEvent(uid: ev.id, title: title, start: start, end: end,
                                                   isAllDay: isAllDay, location: location, description: notes, color: colorVal,
                                                   isPrivate: isPrivate, reminders: reminders)
                case "homeassistant":
                    // No update API exists – delete the old event and recreate with new data.
                    let rawId = ev.calendarId.replacingOccurrences(of: "homeassistant-", with: "")
                    let haCalId = Int(rawId) ?? 0
                    try await api.deleteHAEvent(calendarId: haCalId, uid: ev.id)
                    try await api.createHAEvent(calendarId: haCalId, title: title,
                                                start: start, end: end, isAllDay: isAllDay,
                                                location: location, description: notes)
                default: // caldav
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
                                                       location: location, description: notes, color: colorVal,
                                                       isPrivate: isPrivate, reminders: reminders)
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

/// One reminder row: a preset picker plus, when "Custom" is chosen, a number
/// stepper and a unit picker. The value is always stored as minutes-before-start.
private struct ReminderEditRow: View {
    @Binding var minutes: Int
    let appLang: String
    private let customTag = -1

    private var isPreset: Bool { ReminderOptions.presets.contains(minutes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: Binding(
                get: { isPreset ? minutes : customTag },
                set: { newVal in
                    if newVal == customTag {
                        if ReminderOptions.presets.contains(minutes) { minutes = ReminderOptions.customDefault }
                    } else {
                        minutes = newVal
                    }
                }
            )) {
                ForEach(ReminderOptions.presets, id: \.self) { Text(ReminderOptions.label($0, appLang)).tag($0) }
                Text(ReminderOptions.customLabel(appLang)).tag(customTag)
            }
            .labelsHidden()

            if !isPreset {
                HStack {
                    Stepper(value: Binding(
                        get: { ReminderOptions.split(minutes).value },
                        set: { minutes = max(1, $0) * ReminderOptions.split(minutes).unit.mult }
                    ), in: 1...999) {
                        Text("\(ReminderOptions.split(minutes).value)")
                            .monospacedDigit()
                    }
                    Picker("", selection: Binding(
                        get: { ReminderOptions.split(minutes).unit },
                        set: { newUnit in minutes = ReminderOptions.split(minutes).value * newUnit.mult }
                    )) {
                        ForEach(ReminderOptions.Unit.allCases) { u in
                            Text(ReminderOptions.unitLabel(u, appLang)).tag(u)
                        }
                    }
                    .labelsHidden()
                    Text(ReminderOptions.beforeLabel(appLang)).foregroundStyle(.secondary)
                }
            }
        }
    }
}
