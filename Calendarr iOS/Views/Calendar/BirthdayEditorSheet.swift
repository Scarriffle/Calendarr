import SwiftUI

/// Minimal "new birthday" mask for the single birthday calendar: enter a name
/// and a date (optionally "year unknown"). Saves an all-day, yearly-recurring
/// local event; the server adds the age suffix and cake icon on read. If no
/// birthday calendar exists yet, offers to activate one.
struct BirthdayEditorSheet: View {
    let api: CalendarrAPI
    var onDone: () async -> Void

    @AppStorage("appLanguage") private var appLang = "system"
    @Environment(\.dismiss) private var dismiss

    @State private var calendar: LocalCalendar? = nil
    @State private var name = ""
    @State private var date = Date()
    @State private var yearUnknown = false
    @State private var loading = true
    @State private var saving = false
    @State private var activating = false

    private var canSave: Bool {
        !saving && calendar != nil
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if calendar == nil {
                    Section {
                        Text(L10n.t("birthday.activate_hint", appLang))
                            .foregroundStyle(.secondary)
                        Button(L10n.t("birthday.activate", appLang)) { Task { await activate() } }
                            .disabled(activating)
                    }
                } else {
                    Section(L10n.t("birthday.person", appLang)) {
                        TextField(L10n.t("birthday.person_placeholder", appLang), text: $name)
                    }
                    Section(L10n.t("birthday.date", appLang)) {
                        DatePicker(L10n.t("birthday.date", appLang), selection: $date,
                                   displayedComponents: [.date])
                        Toggle(L10n.t("birthday.year_unknown", appLang), isOn: $yearUnknown)
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
        calendar = await BirthdaysImporter.birthdayCalendar(api: api)
        loading = false
    }

    private func activate() async {
        activating = true
        calendar = await BirthdaysImporter.ensureBirthdayCalendar(api: api)
        activating = false
    }

    private func save() async {
        guard let cal = calendar else { return }
        saving = true
        let calc = Calendar.current
        let comps = calc.dateComponents([.year, .month, .day], from: date)
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
        let start = calc.date(from: anchor) ?? date
        let end = calc.date(byAdding: .day, value: 1, to: start) ?? start
        _ = try? await api.createLocalEvent(
            calendarId: cal.id, title: name.trimmingCharacters(in: .whitespaces),
            start: start, end: end, isAllDay: true, location: "", description: "",
            color: nil, rrule: "FREQ=YEARLY", birthYear: year
        )
        await onDone()
        dismiss()
    }
}
