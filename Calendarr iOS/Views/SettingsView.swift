import SwiftUI

struct SettingsView: View {
    let api: CalendarrAPI
    @AppStorage("liquidGlass")       private var liquidGlass = false
    @AppStorage("settingsSync")      private var settingsSync = false
    @AppStorage("cacheMonths")       private var cacheMonths = 3
    @AppStorage("appLanguage")       private var appLang = "system"
    @AppStorage("monthDividerColor") private var dividerHex = "#7090c0"
    @AppStorage("monthLabelColor")   private var labelHex = "#7090c0"
    @AppStorage("todayColor")        private var todayHex = "#4285f4"
    @AppStorage("textColor")         private var textHex = "#FFFFFF"
    @AppStorage("backgroundColor")   private var bgHex = "#000000"
    @AppStorage("lineColor")         private var lineHex = "#3A3A3C"
    @AppStorage("primaryColor")      private var primaryHex = "#4285f4"
    @AppStorage("accentColor")       private var accentHex = "#ea4335"
    // Previously server-only; now AppStorage-backed so they persist and the
    // calendar views actually apply them.
    @AppStorage("textContrast")      private var textContrast = 3
    @AppStorage("lineContrast")      private var lineContrast = 3
    @AppStorage("hourHeight")        private var hourHeight = 60
    @AppStorage("defaultView")       private var defaultView = "month"
    @AppStorage("weekStartDay")      private var weekStartDay = "monday"
    @AppStorage("dimPastEvents")     private var dimPastEvents = false
    @AppStorage("defaultReminderMinutes") private var defaultReminderMinutes = -1
    @AppStorage("defaultEventDurationMinutes") private var defaultEventDurationMinutes = 60

    // Profile chapter (server-backed; loaded on appear).
    @State private var displayName = ""
    @State private var loginName = ""
    @State private var email = ""
    @State private var privateVisibility = "busy"
    @State private var groupVisibleId = 0      // 0 = none
    @State private var ownLocalCals: [LocalCalendar] = []
    @State private var profileMsg = ""

    var body: some View {
        NavigationStack {
            Form {
                profilSection
                privatsphaereSection
                termindauerSection
                benachrichtigungenSection
                geteilterKalenderSection
                liquidGlassSection
                cacheSection
                spracheSection
                farbenSection
                schriftSection
                linienSection
                ansichtSection
                stundenSection
            }
            .navigationTitle(L10n.t("settings.title", appLang))
            .navigationBarTitleDisplayMode(.large)
        }
        // Reflect the latest server values when opening the screen.
        .task { await SettingsSync.pull(api: api) }
        .task { await loadProfile() }
        // Appearance changes update widgets live; synced values are also pushed
        // to the server (debounced). `push` itself decides what actually gets
        // sent based on the sync toggle, so every change can simply call it.
        .onChange(of: primaryHex) { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: accentHex)  { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: todayHex)   { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: textHex)    { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: bgHex)      { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: lineHex)    { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: dividerHex) { _, _ in SettingsSync.push(api: api) }
        .onChange(of: labelHex)   { _, _ in SettingsSync.push(api: api) }
        .onChange(of: textContrast)  { _, _ in SettingsSync.push(api: api) }
        .onChange(of: lineContrast)  { _, _ in SettingsSync.push(api: api) }
        .onChange(of: hourHeight)    { _, _ in SettingsSync.push(api: api) }
        .onChange(of: defaultView)   { _, _ in SettingsSync.push(api: api) }
        .onChange(of: weekStartDay)  { _, _ in SettingsSync.push(api: api) }
        .onChange(of: dimPastEvents) { _, _ in SettingsSync.push(api: api) }
        .onChange(of: appLang)    { _, _ in WidgetStore.republishAppearanceOnly() }
        // Enabling sync adopts the server's appearance (server wins).
        .onChange(of: settingsSync) { _, on in if on { Task { await SettingsSync.pull(api: api) } } }
    }

    // MARK: – Profil

    var profilSection: some View {
        Section(L10n.t("settings.nav.profile", appLang)) {
            HStack {
                Text(L10n.t("profile.display_name", appLang))
                Spacer()
                TextField(L10n.t("profile.display_name", appLang), text: $displayName)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text(L10n.t("profile.login_name", appLang))
                Spacer()
                Text(loginName).foregroundStyle(.secondary)
            }
            HStack {
                Text(L10n.t("settings.email", appLang))
                Spacer()
                TextField(L10n.t("settings.email", appLang), text: $email)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }
            Button(L10n.t("event.save", appLang)) { Task { await saveProfile() } }
            if !profileMsg.isEmpty {
                Text(profileMsg).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: – Benachrichtigungen

    var benachrichtigungenSection: some View {
        Section {
            Picker(ReminderOptions.defaultTitle(appLang), selection: $defaultReminderMinutes) {
                Text(ReminderOptions.off(appLang)).tag(-1)
                ForEach(ReminderOptions.all, id: \.self) { m in
                    Text(ReminderOptions.label(m, appLang)).tag(m)
                }
            }
            .onChange(of: defaultReminderMinutes) { _, _ in
                SettingsSync.push(api: api)
                NotificationCenter.default.post(name: .rescheduleReminders, object: nil)
            }
        } header: {
            Text(ReminderOptions.sectionTitle(appLang))
        } footer: {
            Text(ReminderOptions.defaultFooter(appLang)).font(.caption)
        }
    }

    // MARK: – Privatsphäre

    var privatsphaereSection: some View {
        Section {
            Picker(L10n.t("settings.private_visibility", appLang), selection: $privateVisibility) {
                Text(L10n.t("settings.private.busy", appLang)).tag("busy")
                Text(L10n.t("settings.private.hidden", appLang)).tag("hidden")
            }
            .onChange(of: privateVisibility) { _, v in
                Task { try? await api.updatePrivateVisibility(v) }
            }
        } header: {
            Text(L10n.t("settings.privacy", appLang))
        } footer: {
            Text(L10n.t("settings.private_visibility.desc", appLang)).font(.caption)
        }
    }

    // MARK: – Standardtermindauer

    var termindauerSection: some View {
        Section {
            Picker(L10n.t("settings.default_duration", appLang), selection: $defaultEventDurationMinutes) {
                ForEach([15, 30, 45, 60, 90, 120, 240], id: \.self) { m in
                    Text(ReminderOptions.durationLabel(m, appLang)).tag(m)
                }
            }
            .onChange(of: defaultEventDurationMinutes) { _, _ in SettingsSync.push(api: api) }
        } header: {
            Text(L10n.t("settings.calview", appLang))
        }
    }

    // MARK: – Geteilter Kalender

    var geteilterKalenderSection: some View {
        Section {
            Picker(L10n.t("settings.group_visible", appLang), selection: $groupVisibleId) {
                Text(L10n.t("group.visible.none", appLang)).tag(0)
                ForEach(ownLocalCals) { cal in
                    Text(cal.name).tag(cal.id)
                }
            }
            .onChange(of: groupVisibleId) { _, id in
                Task { try? await api.updateGroupVisibleCalendar(id == 0 ? nil : id) }
            }
        } header: {
            Text(L10n.t("settings.calendars", appLang))
        } footer: {
            Text(L10n.t("settings.group_visible.desc", appLang)).font(.caption)
        }
    }

    private func loadProfile() async {
        if let p = try? await api.getProfile() {
            displayName = p.displayName ?? p.username
            loginName = p.username
            email = p.email ?? ""
        }
        if let s = try? await api.getSettings() {
            privateVisibility = s.privateEventVisibility
            groupVisibleId = s.groupVisibleCalendarId ?? 0
        }
        if let cals = try? await api.getLocalCalendars() {
            ownLocalCals = cals.filter { $0.owned && !$0.group }
        }
    }

    private func saveProfile() async {
        do {
            _ = try await api.updateProfile(displayName: displayName.isEmpty ? nil : displayName,
                                            username: nil,
                                            email: email.isEmpty ? "" : email)
            UserDefaults.standard.set(displayName, forKey: "displayName")
            profileMsg = L10n.t("settings.saved", appLang)
        } catch {
            profileMsg = error.localizedDescription
        }
    }

    // MARK: – Liquid Glass

    var liquidGlassSection: some View {
        Section {
            Toggle(isOn: $liquidGlass) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("settings.liquidglass", appLang))
                        Text(L10n.t("settings.liquidglass.desc", appLang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.blue)
                }
            }
            .tint(Color.accentColor)

            Toggle(isOn: $settingsSync) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("settings.sync", appLang))
                        Text(L10n.t("settings.sync.desc", appLang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.teal)
                }
            }
            .tint(Color.accentColor)
        } header: {
            Text(L10n.t("settings.appdesign", appLang))
        } footer: {
            Text(L10n.t("settings.sync.footer", appLang))
                .font(.caption)
        }
    }

    // MARK: – Cache

    var cacheSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("settings.cache.title", appLang))
                        Text(L10n.t("settings.cache.desc", appLang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.green)
                }

                Picker(L10n.t("settings.cache.range", appLang), selection: $cacheMonths) {
                    Text(L10n.t("settings.cache.1m", appLang)).tag(1)
                    Text(L10n.t("settings.cache.3m", appLang)).tag(3)
                    Text(L10n.t("settings.cache.6m", appLang)).tag(6)
                    Text(L10n.t("settings.cache.1y", appLang)).tag(12)
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
        } header: {
            Text(L10n.t("settings.cache.header", appLang))
        } footer: {
            Text(L10n.t("settings.cache.footer", appLang))
                .font(.caption)
        }
    }

    // MARK: – Sprache

    var spracheSection: some View {
        Section(L10n.t("settings.language", appLang)) {
            Picker(L10n.t("settings.language", appLang), selection: $appLang) {
                Text(L10n.t("lang.system",  appLang)).tag("system")
                Text(L10n.t("lang.german",  appLang)).tag("de")
                Text(L10n.t("lang.english", appLang)).tag("en")
            }
        }
    }

    // MARK: – Farben

    var farbenSection: some View {
        Section(L10n.t("settings.colors", appLang)) {
            ColorPickerRow(label: L10n.t("settings.color.primary",    appLang), hex: $primaryHex)
            ColorPickerRow(label: L10n.t("settings.color.accent",     appLang), hex: $accentHex)
            ColorPickerRow(label: L10n.t("settings.color.today",      appLang), hex: $todayHex)
            ColorPickerRow(label: L10n.t("settings.color.text",       appLang), hex: $textHex)
            ColorPickerRow(label: L10n.t("settings.color.background", appLang), hex: $bgHex)
            ColorPickerRow(label: L10n.t("settings.color.line",       appLang), hex: $lineHex)
            ColorPickerRow(label: L10n.t("settings.color.divider",    appLang), hex: $dividerHex)
            ColorPickerRow(label: L10n.t("settings.color.label",      appLang), hex: $labelHex)
        }
    }

    // MARK: – Schriftkontrast

    var schriftSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("settings.textcontrast", appLang))
                    .font(.headline)
                Text(L10n.t("settings.textcontrast.desc", appLang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ContrastSelector(
                    value: $textContrast,
                    options: [
                        (1, L10n.t("settings.contrast.dark",   appLang)),
                        (2, L10n.t("settings.contrast.medium", appLang)),
                        (3, L10n.t("settings.contrast.bright", appLang)),
                        (4, L10n.t("settings.contrast.max",    appLang))
                    ]
                )
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: – Linienkontrast

    var linienSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("settings.linecontrast", appLang))
                    .font(.headline)
                Text(L10n.t("settings.linecontrast.desc", appLang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ContrastSelector(
                    value: $lineContrast,
                    options: [
                        (1, L10n.t("settings.linecontrast.barely", appLang)),
                        (2, L10n.t("settings.linecontrast.subtle", appLang)),
                        (3, L10n.t("settings.linecontrast.normal", appLang)),
                        (4, L10n.t("settings.linecontrast.strong", appLang))
                    ]
                )
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: – Ansicht

    var ansichtSection: some View {
        Section(L10n.t("settings.calview", appLang)) {
            Picker(L10n.t("settings.defaultview", appLang), selection: $defaultView) {
                Text(L10n.t("view.month",   appLang)).tag("month")
                Text(L10n.t("view.week",    appLang)).tag("week")
                Text(L10n.t("view.day",     appLang)).tag("day")
                Text(L10n.t("view.quarter", appLang)).tag("quarter")
                Text(L10n.t("view.agenda",  appLang)).tag("agenda")
            }
            Picker(L10n.t("settings.firstweekday", appLang), selection: $weekStartDay) {
                Text(L10n.t("settings.monday", appLang)).tag("monday")
                Text(L10n.t("settings.sunday", appLang)).tag("sunday")
            }
            Toggle(L10n.t("settings.dimpast", appLang), isOn: $dimPastEvents)
                .tint(Color.accentColor)
        }
    }

    // MARK: – Stundenhöhe

    var stundenSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("settings.hourheight", appLang))
                    .font(.headline)
                Text(L10n.t("settings.hourheight.desc", appLang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ContrastSelector(
                    value: $hourHeight,
                    options: [
                        (28, L10n.t("settings.hourheight.compact", appLang)),
                        (44, L10n.t("settings.hourheight.normal",  appLang)),
                        (60, L10n.t("settings.hourheight.comfort", appLang)),
                        (80, L10n.t("settings.hourheight.large",   appLang))
                    ]
                )
            }
            .padding(.vertical, 4)
        }
    }

}

// MARK: – Reusable Components

struct ColorPickerRow: View {
    let label: String
    @Binding var hex: String

    var color: Binding<Color> {
        Binding(
            get: { Color(hex: hex) },
            set: { hex = $0.toHex() }
        )
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
            Text(hex.uppercased())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
        }
    }
}

struct ContrastSelector<T: Hashable & Equatable>: View {
    @Binding var value: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                Button {
                    value = opt.0
                } label: {
                    Text(opt.1)
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(value == opt.0 ? Color.accentColor : Color(.systemGray5))
                        .foregroundStyle(value == opt.0 ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
