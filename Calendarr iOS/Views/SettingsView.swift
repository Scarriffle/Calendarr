import SwiftUI

struct SettingsView: View {
    let api: CalendarrAPI
    @AppStorage("liquidGlass")       private var liquidGlass = false
    @AppStorage("hideMenuButton")    private var hideMenuButton = false
    @AppStorage("cacheMonths")       private var cacheMonths = 3
    @AppStorage("appLanguage")       private var appLang = "system"
    @AppStorage("monthDividerColor") private var dividerHex = "#7090C0"
    @AppStorage("monthLabelColor")   private var labelHex = "#7090C0"
    @AppStorage("todayColor")        private var todayHex = "#4285F4"
    @AppStorage("textColor")         private var textHex = "#FFFFFF"
    @AppStorage("backgroundColor")   private var bgHex = "#000000"
    @AppStorage("lineColor")         private var lineHex = "#3A3A52"
    // Device-local top-bar/surface colour. Empty = translucent .bar material.
    @AppStorage("surfaceColor")      private var surfaceHex = ""
    @AppStorage("primaryColor")      private var primaryHex = "#4285F4"
    @AppStorage("accentColor")       private var accentHex = "#EA4335"
    // iOS-only opacity controls (drive secondary text / grid-line opacity in the
    // calendar views); kept device-local, not part of the cross-device sync.
    @AppStorage("textContrast")      private var textContrast = 3
    @AppStorage("lineContrast")      private var lineContrast = 3
    @AppStorage("hourHeight")        private var hourHeight = 60
    @AppStorage("defaultView")       private var defaultView = "month"
    @AppStorage("weekStartDay")      private var weekStartDay = "monday"
    @AppStorage("dimPastEvents")     private var dimPastEvents = false
    @AppStorage("monthViewPaged")    private var monthViewPaged = false
    @AppStorage("defaultReminderMinutes") private var defaultReminderMinutes = -1
    @AppStorage("defaultEventDurationMinutes") private var defaultEventDurationMinutes = 60

    // Profile chapter (server-backed; loaded on appear). Account settings are not
    // part of the per-device sync — they are always account-wide.
    @State private var displayName = ""
    @State private var loginName = ""
    @State private var email = ""
    @State private var privateVisibility = "busy"
    @State private var groupVisibleId = 0      // 0 = none
    @State private var ownLocalCals: [LocalCalendar] = []
    @State private var directoryHidden = false
    @State private var profileMsg = ""

    // Per-setting sync flags (account-wide; refreshed from the server on pull).
    @State private var syncFlags: [String: Bool] = SettingsSync.flags()

    // Canonical default colours (single source for the reset buttons).
    private static let defaultHex: [String: String] = [
        "primaryColor": "#4285F4", "accentColor": "#EA4335", "todayColor": "#4285F4",
        "textColor": "#FFFFFF", "backgroundColor": "#000000", "lineColor": "#3A3A52",
        "monthDividerColor": "#7090C0", "monthLabelColor": "#7090C0",
    ]

    var body: some View {
        NavigationStack {
            Form {
                globalSyncSection
                profilSection
                privatsphaereSection
                geteilterKalenderSection
                termineSection
                ansichtSection
                farbenSection
                cacheSection
                geraetSection
            }
            .navigationTitle(L10n.t("settings.title", appLang))
            .navigationBarTitleDisplayMode(.large)
        }
        // Reflect the latest server values (and flag map) when opening the screen.
        .task { await SettingsSync.pull(api: api); syncFlags = SettingsSync.flags() }
        .task { await loadProfile() }
        // Value edits update widgets live; a synced value is also pushed (debounced).
        // `push` decides what actually gets sent based on each key's flag.
        .onChange(of: primaryHex) { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: accentHex)  { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: todayHex)   { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: textHex)    { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: bgHex)      { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: lineHex)    { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: dividerHex) { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: labelHex)   { _, _ in WidgetStore.republishAppearanceOnly(); SettingsSync.push(api: api) }
        .onChange(of: hourHeight)    { _, _ in SettingsSync.push(api: api) }
        .onChange(of: defaultView)   { _, _ in SettingsSync.push(api: api) }
        .onChange(of: weekStartDay)  { _, _ in SettingsSync.push(api: api) }
        .onChange(of: dimPastEvents) { _, _ in SettingsSync.push(api: api) }
        .onChange(of: monthViewPaged){ _, _ in SettingsSync.push(api: api) }
        .onChange(of: cacheMonths)   { _, _ in SettingsSync.push(api: api) }
        .onChange(of: defaultEventDurationMinutes) { _, _ in SettingsSync.push(api: api) }
        .onChange(of: appLang)    { _, _ in WidgetStore.republishAppearanceOnly() }
    }

    // MARK: – Reusable row builders

    /// Leading per-row sync toggle: linked (accent) = synced across devices.
    @ViewBuilder
    private func syncIcon(_ key: String) -> some View {
        let on = syncFlags[key] == true
        Button {
            SettingsSync.setSynced(key, !on, api: api)
            syncFlags = SettingsSync.flags()
        } label: {
            Image(systemName: on ? "link.circle.fill" : "link.circle")
                .imageScale(.large)
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("settings.sync_this", appLang))
    }

    private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.toHex() })
    }

    // Surface colour: empty string means "auto" (translucent .bar); the picker
    // shows a neutral dark until the user chooses a concrete colour.
    private var surfaceBinding: Binding<Color> {
        Binding(
            get: { Color(hex: surfaceHex.isEmpty ? "#1C1C1E" : surfaceHex) },
            set: { surfaceHex = $0.toHex() }
        )
    }

    @ViewBuilder
    private func colorRow(_ syncKey: String, _ defaultsKey: String, _ label: String, _ hex: Binding<String>) -> some View {
        HStack(spacing: 12) {
            syncIcon(syncKey)
            Text(label)
            Spacer()
            ColorPicker("", selection: colorBinding(hex), supportsOpacity: false)
                .labelsHidden()
            Text(hex.wrappedValue.uppercased())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Button {
                hex.wrappedValue = Self.defaultHex[defaultsKey] ?? "#000000"
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(L10n.t("settings.reset", appLang))
        }
    }

    // MARK: – Global sync

    var globalSyncSection: some View {
        Section {
            Toggle(isOn: allSyncedBinding) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("settings.sync_all", appLang))
                        Text(L10n.t("settings.sync_all.desc", appLang))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.teal)
                }
            }
            .tint(Color.accentColor)
        }
    }

    private var allSyncedBinding: Binding<Bool> {
        Binding(
            get: { SettingsSync.syncableKeys.allSatisfy { syncFlags[$0] == true } },
            set: { on in SettingsSync.setAllSynced(on, api: api); syncFlags = SettingsSync.flags() }
        )
    }

    // MARK: – Profil (account identity — not synced)

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
            Toggle(isOn: $directoryHidden) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("settings.directory_hidden", appLang))
                    Text(L10n.t("settings.directory_hidden.desc", appLang))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button(L10n.t("event.save", appLang)) { Task { await saveProfile() } }
            if !profileMsg.isEmpty {
                Text(profileMsg).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: – Privatsphäre (account — not synced)

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

    // MARK: – Geteilter Kalender (account — not synced)

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

    // MARK: – Termine (synced)

    var termineSection: some View {
        Section(L10n.t("settings.calview", appLang)) {
            HStack(spacing: 12) {
                syncIcon("default_event_duration_minutes")
                Text(L10n.t("settings.default_duration", appLang))
                Spacer()
                Picker("", selection: $defaultEventDurationMinutes) {
                    ForEach([15, 30, 45, 60, 90, 120, 240], id: \.self) { m in
                        Text(ReminderOptions.durationLabel(m, appLang)).tag(m)
                    }
                }
                .pickerStyle(.menu).labelsHidden()
            }
            HStack(spacing: 12) {
                syncIcon("default_reminder_minutes")
                Text(ReminderOptions.defaultTitle(appLang))
                Spacer()
                Picker("", selection: $defaultReminderMinutes) {
                    Text(ReminderOptions.off(appLang)).tag(-1)
                    ForEach(ReminderOptions.all, id: \.self) { m in
                        Text(ReminderOptions.label(m, appLang)).tag(m)
                    }
                }
                .pickerStyle(.menu).labelsHidden()
                .onChange(of: defaultReminderMinutes) { _, _ in
                    SettingsSync.push(api: api)
                    NotificationCenter.default.post(name: .rescheduleReminders, object: nil)
                }
            }
        }
    }

    // MARK: – Ansicht (synced)

    var ansichtSection: some View {
        Section(L10n.t("settings.appearance", appLang)) {
            HStack(spacing: 12) {
                syncIcon("default_view")
                Text(L10n.t("settings.defaultview", appLang))
                Spacer()
                Picker("", selection: $defaultView) {
                    Text(L10n.t("view.month",   appLang)).tag("month")
                    Text(L10n.t("view.week",    appLang)).tag("week")
                    Text(L10n.t("view.day",     appLang)).tag("day")
                    Text(L10n.t("view.quarter", appLang)).tag("quarter")
                    Text(L10n.t("view.agenda",  appLang)).tag("agenda")
                }
                .pickerStyle(.menu).labelsHidden()
            }
            HStack(spacing: 12) {
                syncIcon("week_start_day")
                Text(L10n.t("settings.firstweekday", appLang))
                Spacer()
                Picker("", selection: $weekStartDay) {
                    Text(L10n.t("settings.monday", appLang)).tag("monday")
                    Text(L10n.t("settings.sunday", appLang)).tag("sunday")
                }
                .pickerStyle(.menu).labelsHidden()
            }
            HStack(spacing: 12) {
                syncIcon("dim_past_events")
                Toggle(L10n.t("settings.dimpast", appLang), isOn: $dimPastEvents).tint(Color.accentColor)
            }
            HStack(spacing: 12) {
                syncIcon("month_view_paged")
                Text(L10n.t("settings.month_mode", appLang))
                Spacer()
                Picker("", selection: $monthViewPaged) {
                    Text(L10n.t("settings.month_mode.scroll", appLang)).tag(false)
                    Text(L10n.t("settings.month_mode.paged", appLang)).tag(true)
                }
                .pickerStyle(.menu).labelsHidden()
            }
            HStack(spacing: 12) {
                syncIcon("hour_height")
                Text(L10n.t("settings.hourheight", appLang))
                Spacer()
                Picker("", selection: $hourHeight) {
                    Text(L10n.t("settings.hourheight.compact", appLang)).tag(28)
                    Text(L10n.t("settings.hourheight.normal",  appLang)).tag(44)
                    Text(L10n.t("settings.hourheight.comfort", appLang)).tag(60)
                    Text(L10n.t("settings.hourheight.large",   appLang)).tag(80)
                }
                .pickerStyle(.menu).labelsHidden()
            }
        }
    }

    // MARK: – Farben (synced)

    var farbenSection: some View {
        Section(L10n.t("settings.colors", appLang)) {
            colorRow("primary_color",       "primaryColor",      L10n.t("settings.color.primary",    appLang), $primaryHex)
            colorRow("accent_color",        "accentColor",       L10n.t("settings.color.accent",     appLang), $accentHex)
            colorRow("today_color",         "todayColor",        L10n.t("settings.color.today",      appLang), $todayHex)
            colorRow("text_color",          "textColor",         L10n.t("settings.color.text",       appLang), $textHex)
            colorRow("bg_color",            "backgroundColor",   L10n.t("settings.color.background", appLang), $bgHex)
            colorRow("line_color",          "lineColor",         L10n.t("settings.color.line",       appLang), $lineHex)
            colorRow("month_divider_color", "monthDividerColor", L10n.t("settings.color.divider",    appLang), $dividerHex)
            colorRow("month_label_color",   "monthLabelColor",   L10n.t("settings.color.label",      appLang), $labelHex)
        }
    }

    // MARK: – Cache (synced)

    var cacheSection: some View {
        Section {
            HStack(spacing: 12) {
                syncIcon("cache_months")
                Text(L10n.t("settings.cache.range", appLang))
                Spacer()
                Picker("", selection: $cacheMonths) {
                    Text(L10n.t("settings.cache.1m", appLang)).tag(1)
                    Text(L10n.t("settings.cache.3m", appLang)).tag(3)
                    Text(L10n.t("settings.cache.6m", appLang)).tag(6)
                    Text(L10n.t("settings.cache.1y", appLang)).tag(12)
                }
                .pickerStyle(.menu).labelsHidden()
            }
        } header: {
            Text(L10n.t("settings.cache.header", appLang))
        } footer: {
            Text(L10n.t("settings.cache.footer", appLang)).font(.caption)
        }
    }

    // MARK: – Gerät (device-local: language, contrast, liquid glass)

    var geraetSection: some View {
        Section {
            Picker(L10n.t("settings.language", appLang), selection: $appLang) {
                Text(L10n.t("lang.system",  appLang)).tag("system")
                Text(L10n.t("lang.german",  appLang)).tag("de")
                Text(L10n.t("lang.english", appLang)).tag("en")
            }
            Picker(L10n.t("settings.textcontrast", appLang), selection: $textContrast) {
                Text(L10n.t("settings.contrast.dark",   appLang)).tag(1)
                Text(L10n.t("settings.contrast.medium", appLang)).tag(2)
                Text(L10n.t("settings.contrast.bright", appLang)).tag(3)
                Text(L10n.t("settings.contrast.max",    appLang)).tag(4)
            }
            Picker(L10n.t("settings.linecontrast", appLang), selection: $lineContrast) {
                Text(L10n.t("settings.linecontrast.barely", appLang)).tag(1)
                Text(L10n.t("settings.linecontrast.subtle", appLang)).tag(2)
                Text(L10n.t("settings.linecontrast.normal", appLang)).tag(3)
                Text(L10n.t("settings.linecontrast.strong", appLang)).tag(4)
            }
            Toggle(isOn: $liquidGlass) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("settings.liquidglass", appLang))
                        Text(L10n.t("settings.liquidglass.desc", appLang))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(.blue)
                }
            }
            .tint(Color.accentColor)
            HStack(spacing: 12) {
                Text(L10n.t("settings.color.surface", appLang))
                Spacer()
                Text(surfaceHex.isEmpty ? L10n.t("settings.surface.auto", appLang) : surfaceHex.uppercased())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                ColorPicker("", selection: surfaceBinding, supportsOpacity: false)
                    .labelsHidden()
                Button { surfaceHex = "" } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.t("settings.surface.auto", appLang))
            }
            Toggle(L10n.t("settings.hide_menu_button", appLang), isOn: $hideMenuButton)
                .tint(Color.accentColor)
        } header: {
            Text(L10n.t("settings.device", appLang))
        } footer: {
            Text(L10n.t("settings.device.footer", appLang)).font(.caption)
        }
    }

    // MARK: – Profile load / save

    private func loadProfile() async {
        if let p = try? await api.getProfile() {
            displayName = p.displayName ?? p.username
            loginName = p.username
            email = p.email ?? ""
            directoryHidden = p.directoryHidden
        }
        if let s = try? await api.getSettings() {
            privateVisibility = s.privateEventVisibility
            groupVisibleId = s.groupVisibleCalendarId ?? 0
        }
        if let cals = try? await api.getLocalCalendars() {
            // A birthday calendar may be shared directly, but never stand in as
            // the group-visible personal calendar.
            ownLocalCals = cals.filter { $0.owned && !$0.group && !$0.isBirthday }
        }
    }

    private func saveProfile() async {
        do {
            _ = try await api.updateProfile(displayName: displayName.isEmpty ? nil : displayName,
                                            username: nil,
                                            email: email.isEmpty ? "" : email,
                                            directoryHidden: directoryHidden)
            UserDefaults.standard.set(displayName, forKey: "displayName")
            profileMsg = L10n.t("settings.saved", appLang)
        } catch {
            profileMsg = error.localizedDescription
        }
    }
}
