import SwiftUI

/// Minimal "new birthday" mask: pick a birthday calendar, enter a name and a
/// date (day + month, optionally a year). Saves an all-day, yearly-recurring
/// local event; the server adds the age suffix and cake icon on read.
struct BirthdayEditorSheet: View {
    let api: CalendarrAPI
    var onDone: () async -> Void

    @AppStorage("appLanguage") private var appLang = "system"
    @Environment(\.dismiss) private var dismiss

    @State private var calendars: [LocalCalendar] = []
    @State private var selectedCalId: Int? = nil
    @State private var name = ""
    @State private var date = Date()
    @State private var yearUnknown = false
    @State private var loading = true
    @State private var saving = false

    private var birthdayCalendars: [LocalCalendar] {
        calendars.filter { $0.isBirthday && ($0.owned || $0.permission == "read_write") }
    }

    private var canSave: Bool {
        !saving && selectedCalId != nil
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if birthdayCalendars.isEmpty {
                    Text(L10n.t("birthday.no_calendars", appLang))
                        .foregroundStyle(.secondary)
                } else {
                    Section(L10n.t("birthday.person", appLang)) {
                        TextField(L10n.t("birthday.person_placeholder", appLang), text: $name)
                    }
                    Section(L10n.t("birthday.date", appLang)) {
                        DatePicker(L10n.t("birthday.date", appLang), selection: $date,
                                   displayedComponents: [.date])
                        Toggle(L10n.t("birthday.year_unknown", appLang), isOn: $yearUnknown)
                    }
                    if birthdayCalendars.count > 1 {
                        Section(L10n.t("birthday.contacts.target", appLang)) {
                            Picker(L10n.t("birthday.contacts.target", appLang), selection: $selectedCalId) {
                                ForEach(birthdayCalendars) { c in
                                    Text(c.name).tag(Optional(c.id))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("birthday.new", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel", appLang)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("event.save", appLang)) { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        calendars = (try? await api.getLocalCalendars()) ?? []
        if selectedCalId == nil { selectedCalId = birthdayCalendars.first?.id }
        loading = false
    }

    private func save() async {
        guard let calId = selectedCalId else { return }
        saving = true
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let year = yearUnknown ? nil : comps.year
        // All-day anchor at local noon; anchor year = birth year (else 1970) so
        // the yearly rule expands across any queried range.
        var anchor = DateComponents()
        anchor.year = year ?? 1970
        anchor.month = month
        anchor.day = day
        anchor.hour = 12
        let start = cal.date(from: anchor) ?? date
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        _ = try? await api.createLocalEvent(
            calendarId: calId, title: name.trimmingCharacters(in: .whitespaces),
            start: start, end: end, isAllDay: true, location: "", description: "",
            color: nil, rrule: "FREQ=YEARLY", birthYear: year
        )
        await onDone()
        dismiss()
    }
}
