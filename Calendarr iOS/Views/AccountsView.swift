import SwiftUI

struct AccountsView: View {
    let api: CalendarrAPI
    @State private var caldavAccounts: [CalDAVAccount] = []
    @State private var localCalendars: [LocalCalendar] = []
    @State private var icalSubs: [ICalSubscription] = []
    @State private var googleAccounts: [GoogleAccount] = []
    @State private var haAccounts: [HomeAssistantAccount] = []
    @State private var isLoading = true

    @State private var showAddCalDAV = false
    @State private var showAddLocal = false
    @State private var showAddICal = false
    @State private var showAddHA = false
    @State private var errorAlert: String?
    @State private var banishedKeys: Set<String> = CalendarStore.loadBanishedKeys()

    @AppStorage("appLanguage") private var appLang = "system"

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(L10n.t("accounts.loading", appLang))
                } else {
                    List {
                        if !banishedKeys.isEmpty { banishedSection }
                        caldavSection
                        localSection
                        icalSection
                        googleSection
                        haSection
                    }
                }
            }
            .navigationTitle(L10n.t("accounts.title", appLang))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(L10n.t("accounts.add.caldav", appLang)) { showAddCalDAV = true }
                        Button(L10n.t("accounts.add.local",  appLang)) { showAddLocal  = true }
                        Button(L10n.t("accounts.add.ical",   appLang)) { showAddICal   = true }
                        Button(L10n.t("accounts.add.ha",     appLang)) { showAddHA     = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddCalDAV) {
                AddCalDAVSheet(api: api) { await load() }
            }
            .sheet(isPresented: $showAddLocal) {
                AddLocalCalSheet(api: api) { await load() }
            }
            .sheet(isPresented: $showAddICal) {
                AddICalSheet(api: api) { await load() }
            }
            .sheet(isPresented: $showAddHA) {
                AddHASheet(api: api) { await load() }
            }
            .alert(L10n.t("common.error", appLang), isPresented: .constant(errorAlert != nil), actions: {
                Button(L10n.t("common.ok", appLang)) { errorAlert = nil }
            }, message: {
                Text(errorAlert ?? "")
            })
        }
        .task { await load() }
    }

    // MARK: – Sections

    var caldavSection: some View {
        Section {
            if caldavAccounts.isEmpty {
                Text(L10n.t("accounts.caldav.empty", appLang))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(caldavAccounts) { acc in
                    HStack {
                        Circle()
                            .fill(Color(hex: acc.color))
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(acc.name).font(.body)
                            Text(acc.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .onDelete { offsets in
                    Task { await deleteCalDAV(offsets: offsets) }
                }
            }
            Button(L10n.t("accounts.caldav.add", appLang)) { showAddCalDAV = true }
                .foregroundStyle(Color.accentColor)
        } header: {
            Text(L10n.t("accounts.caldav.header", appLang))
        }
    }

    var localSection: some View {
        Section {
            if localCalendars.isEmpty {
                Text(L10n.t("accounts.local.empty", appLang))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(localCalendars) { cal in
                    HStack {
                        Circle()
                            .fill(Color(hex: cal.color))
                            .frame(width: 12, height: 12)
                        Text(cal.name)
                    }
                }
                .onDelete { offsets in
                    Task { await deleteLocal(offsets: offsets) }
                }
            }
            Button(L10n.t("accounts.local.add", appLang)) { showAddLocal = true }
                .foregroundStyle(Color.accentColor)
        } header: {
            Text(L10n.t("accounts.local.header", appLang))
        }
    }

    var icalSection: some View {
        Section {
            if icalSubs.isEmpty {
                Text(L10n.t("accounts.ical.empty", appLang))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(icalSubs) { sub in
                    HStack {
                        Circle()
                            .fill(Color(hex: sub.color))
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.name).font(.body)
                            Text(String(format: L10n.t("accounts.ical.every", appLang), sub.refreshMinutes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    Task { await deleteICal(offsets: offsets) }
                }
            }
            Button(L10n.t("accounts.ical.add", appLang)) { showAddICal = true }
                .foregroundStyle(Color.accentColor)
        } header: {
            Text(L10n.t("accounts.ical.header", appLang))
        }
    }

    var googleSection: some View {
        Section {
            if googleAccounts.isEmpty {
                Text(L10n.t("accounts.google.empty", appLang))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(googleAccounts) { acc in
                    HStack {
                        Image(systemName: "g.circle.fill")
                            .foregroundStyle(.red)
                        Text(acc.email)
                    }
                }
                .onDelete { offsets in
                    Task { await deleteGoogle(offsets: offsets) }
                }
            }
            Text(L10n.t("accounts.google.hint", appLang))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(L10n.t("accounts.google.header", appLang))
        }
    }

    var banishedSection: some View {
        Section {
            ForEach(Array(banishedKeys).sorted(), id: \.self) { key in
                let info = resolveBanished(key)
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: info.colorHex))
                        .frame(width: 12, height: 12)
                        .opacity(0.5)
                    Text(info.name)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.t("accounts.banished_unhide", appLang)) {
                        unbanish(key)
                    }
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
                }
            }
        } header: {
            Text(L10n.t("accounts.banished_header", appLang))
        }
    }

    /// Re-show a banished calendar. For server-backed sources this clears the
    /// server's sidebar_hidden (re-enabling the calendar); for local/ical it's
    /// just the local set.
    private func unbanish(_ key: String) {
        banishedKeys.remove(key)
        CalendarStore.saveBanishedKeys(banishedKeys)
        NotificationCenter.default.post(name: .banishedCalendarsChanged, object: nil)
        if let parsed = CalendarStore.parseCalendarKey(key),
           CalendarStore.serverManagedSources.contains(parsed.source) {
            // The server excluded this calendar's events while hidden, so they
            // aren't in the cache. Re-enable on the server, then force a refetch
            // so the events actually reappear without a manual sync.
            Task {
                try? await api.setCalendarSidebarHidden(source: parsed.source, calendarId: parsed.id, hidden: false)
                NotificationCenter.default.post(name: .manualSyncRequested, object: nil)
            }
        }
    }

    private func resolveBanished(_ key: String) -> (name: String, colorHex: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = Int(parts[1]) else {
            return (L10n.t("accounts.banished_unknown", appLang), "#888888")
        }
        switch parts[0] {
        case "local":
            if let c = localCalendars.first(where: { $0.id == id }) {
                return (c.name, c.color)
            }
        case "caldav":
            for acc in caldavAccounts {
                if let c = acc.calendars?.first(where: { $0.id == id }) {
                    return ("\(acc.name) – \(c.name)", c.color ?? acc.color)
                }
            }
        case "ical":
            if let s = icalSubs.first(where: { $0.id == id }) {
                return (s.name, s.color)
            }
        case "google":
            for acc in googleAccounts {
                if let c = acc.calendars?.first(where: { $0.id == id }) {
                    return ("\(acc.email) – \(c.name)", c.color ?? "#4285f4")
                }
            }
        case "homeassistant":
            for acc in haAccounts {
                if let c = acc.calendars?.first(where: { $0.id == id }) {
                    return ("\(acc.name) – \(c.name)", c.color ?? "#46bdc6")
                }
            }
        default: break
        }
        return (L10n.t("accounts.banished_unknown", appLang), "#888888")
    }

    var haSection: some View {
        Section {
            if haAccounts.isEmpty {
                Text(L10n.t("accounts.ha.empty", appLang))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(haAccounts) { acc in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(acc.name).font(.body)
                        Text(acc.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .onDelete { offsets in
                    Task { await deleteHA(offsets: offsets) }
                }
            }
            Button(L10n.t("accounts.ha.add", appLang)) { showAddHA = true }
                .foregroundStyle(Color.accentColor)
        } header: {
            Text(L10n.t("accounts.ha.header", appLang))
        }
    }

    // MARK: – Actions

    private func load() async {
        isLoading = true
        banishedKeys = CalendarStore.loadBanishedKeys()
        async let c = (try? await api.getCalDAVAccounts()) ?? []
        async let l = (try? await api.getLocalCalendars()) ?? []
        async let i = (try? await api.getICalSubscriptions()) ?? []
        async let g = (try? await api.getGoogleAccounts()) ?? []
        async let h = (try? await api.getHomeAssistantAccounts()) ?? []
        (caldavAccounts, localCalendars, icalSubs, googleAccounts, haAccounts) = await (c, l, i, g, h)

        // Reconcile banished list with the server's sidebar_hidden (server wins
        // for CalDAV/Google/HA; local/ical keep their local state).
        var b = banishedKeys
        func applyServerHidden(_ source: String, _ id: Int, _ hidden: Bool) {
            let key = CalendarStore.calendarKey(source: source, calendarId: "\(id)")
            if hidden { b.insert(key) } else { b.remove(key) }
        }
        for acc in caldavAccounts { for cal in acc.calendars ?? [] { applyServerHidden("caldav", cal.id, cal.sidebarHidden) } }
        for acc in googleAccounts { for cal in acc.calendars ?? [] { applyServerHidden("google", cal.id, cal.sidebarHidden) } }
        for acc in haAccounts     { for cal in acc.calendars ?? [] { applyServerHidden("homeassistant", cal.id, cal.sidebarHidden) } }
        if b != banishedKeys {
            banishedKeys = b
            CalendarStore.saveBanishedKeys(b)
            NotificationCenter.default.post(name: .banishedCalendarsChanged, object: nil)
        }
        isLoading = false
    }

    private func deleteCalDAV(offsets: IndexSet) async {
        for i in offsets {
            try? await api.deleteCalDAVAccount(id: caldavAccounts[i].id)
        }
        await load()
    }

    private func deleteLocal(offsets: IndexSet) async {
        for i in offsets {
            try? await api.deleteLocalCalendar(id: localCalendars[i].id)
        }
        await load()
    }

    private func deleteICal(offsets: IndexSet) async {
        for i in offsets {
            try? await api.deleteICalSubscription(id: icalSubs[i].id)
        }
        await load()
    }

    private func deleteGoogle(offsets: IndexSet) async {
        for i in offsets {
            try? await api.deleteGoogleAccount(id: googleAccounts[i].id)
        }
        await load()
    }

    private func deleteHA(offsets: IndexSet) async {
        for i in offsets {
            try? await api.deleteHomeAssistantAccount(id: haAccounts[i].id)
        }
        await load()
    }
}

// MARK: – Add Sheets

struct AddCalDAVSheet: View {
    let api: CalendarrAPI
    let onDone: () async -> Void
    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var appLang = "system"

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var color = Color(hex: "#4285f4")
    @State private var isLoading = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("caldav.section", appLang)) {
                    TextField(L10n.t("caldav.display_name", appLang), text: $name)
                    TextField(L10n.t("caldav.url", appLang), text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField(L10n.t("caldav.username", appLang), text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(L10n.t("caldav.password", appLang), text: $password)
                }
                Section(L10n.t("caldav.color_section", appLang)) {
                    ColorPicker(L10n.t("caldav.color_label", appLang), selection: $color, supportsOpacity: false)
                }
                if !error.isEmpty {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.t("caldav.title", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel", appLang)) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.t("caldav.connect", appLang)) {
                        Task { await save() }
                    }
                    .bold()
                    .disabled(name.isEmpty || url.isEmpty || username.isEmpty || password.isEmpty || isLoading)
                }
            }
        }
    }

    private func save() async {
        isLoading = true
        error = ""
        do {
            _ = try await api.addCalDAVAccount(name: name, url: url, username: username, password: password, color: color.toHex())
            await onDone()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct AddLocalCalSheet: View {
    let api: CalendarrAPI
    let onDone: () async -> Void
    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var appLang = "system"

    @State private var name = ""
    @State private var color = Color(hex: "#34a853")
    @State private var isLoading = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.t("local.name", appLang), text: $name)
                    ColorPicker(L10n.t("local.color", appLang), selection: $color, supportsOpacity: false)
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(L10n.t("local.title", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("common.cancel", appLang)) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.t("local.create", appLang)) {
                        Task { await save() }
                    }
                    .bold()
                    .disabled(name.isEmpty || isLoading)
                }
            }
        }
    }

    private func save() async {
        isLoading = true
        do {
            _ = try await api.addLocalCalendar(name: name, color: color.toHex())
            await onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}

struct AddICalSheet: View {
    let api: CalendarrAPI
    let onDone: () async -> Void
    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var appLang = "system"

    @State private var name = ""
    @State private var url = ""
    @State private var color = Color(hex: "#46bdc6")
    @State private var refreshMinutes = 60
    @State private var isLoading = false
    @State private var error = ""

    private var refreshOptions: [(Int, String)] {
        [(15,   L10n.t("ical.refresh.15m", appLang)),
         (30,   L10n.t("ical.refresh.30m", appLang)),
         (60,   L10n.t("ical.refresh.1h",  appLang)),
         (360,  L10n.t("ical.refresh.6h",  appLang)),
         (1440, L10n.t("ical.refresh.1d",  appLang))]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("ical.subscription", appLang)) {
                    TextField(L10n.t("ical.name", appLang), text: $name)
                    TextField(L10n.t("ical.url",  appLang), text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    ColorPicker(L10n.t("ical.color", appLang), selection: $color, supportsOpacity: false)
                }
                Section(L10n.t("ical.refresh_section", appLang)) {
                    Picker(L10n.t("ical.interval", appLang), selection: $refreshMinutes) {
                        ForEach(refreshOptions, id: \.0) { opt in
                            Text(opt.1).tag(opt.0)
                        }
                    }
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(L10n.t("ical.title", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("common.cancel", appLang)) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.t("ical.subscribe", appLang)) {
                        Task { await save() }
                    }
                    .bold()
                    .disabled(name.isEmpty || url.isEmpty || isLoading)
                }
            }
        }
    }

    private func save() async {
        isLoading = true
        do {
            _ = try await api.addICalSubscription(name: name, url: url, color: color.toHex(), refreshMinutes: refreshMinutes)
            await onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}

struct AddHASheet: View {
    let api: CalendarrAPI
    let onDone: () async -> Void
    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var appLang = "system"

    @State private var name = ""
    @State private var url = ""
    @State private var token = ""
    @State private var isLoading = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("ha.section", appLang)) {
                    TextField(L10n.t("ha.display_name",   appLang), text: $name)
                    TextField(L10n.t("ha.url_placeholder", appLang), text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section(L10n.t("ha.auth_section", appLang)) {
                    SecureField(L10n.t("ha.token", appLang), text: $token)
                    Text(L10n.t("ha.token_hint", appLang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(L10n.t("accounts.add.ha", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("common.cancel", appLang)) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.t("ha.connect", appLang)) {
                        Task { await save() }
                    }
                    .bold()
                    .disabled(name.isEmpty || url.isEmpty || token.isEmpty || isLoading)
                }
            }
        }
    }

    private func save() async {
        isLoading = true
        do {
            _ = try await api.addHomeAssistantAccount(name: name, url: url, token: token)
            await onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}
