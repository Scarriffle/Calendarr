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

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Lade Konten…")
                } else {
                    List {
                        caldavSection
                        localSection
                        icalSection
                        googleSection
                        haSection
                    }
                }
            }
            .navigationTitle("Konten")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("CalDAV-Konto") { showAddCalDAV = true }
                        Button("Lokaler Kalender") { showAddLocal = true }
                        Button("iCal-URL abonnieren") { showAddICal = true }
                        Button("Home Assistant") { showAddHA = true }
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
            .alert("Fehler", isPresented: .constant(errorAlert != nil), actions: {
                Button("OK") { errorAlert = nil }
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
                Text("Keine CalDAV-Konten")
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
            Button("CalDAV hinzufügen") { showAddCalDAV = true }
                .foregroundStyle(Color.accentColor)
        } header: {
            Text("CalDAV-Konten")
        }
    }

    var localSection: some View {
        Section {
            if localCalendars.isEmpty {
                Text("Keine lokalen Kalender")
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
            Button("Lokalen Kalender erstellen") { showAddLocal = true }
                .foregroundStyle(Color.accentColor)
        } header: {
            Text("Lokale Kalender")
        }
    }

    var icalSection: some View {
        Section {
            if icalSubs.isEmpty {
                Text("Keine Abonnements")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(icalSubs) { sub in
                    HStack {
                        Circle()
                            .fill(Color(hex: sub.color))
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.name).font(.body)
                            Text("Alle \(sub.refreshMinutes) Min.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    Task { await deleteICal(offsets: offsets) }
                }
            }
            Button("iCal-URL abonnieren") { showAddICal = true }
                .foregroundStyle(Color.accentColor)
        } header: {
            Text("iCal-Abonnements")
        }
    }

    var googleSection: some View {
        Section {
            if googleAccounts.isEmpty {
                Text("Keine Google-Konten")
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
            Text("Google-Konten werden über den Browser verknüpft")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Google-Konten")
        }
    }

    var haSection: some View {
        Section {
            if haAccounts.isEmpty {
                Text("Keine Home Assistant-Konten")
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
            Button("Home Assistant hinzufügen") { showAddHA = true }
                .foregroundStyle(Color.accentColor)
        } header: {
            Text("Home Assistant")
        }
    }

    // MARK: – Actions

    private func load() async {
        isLoading = true
        async let c = (try? await api.getCalDAVAccounts()) ?? []
        async let l = (try? await api.getLocalCalendars()) ?? []
        async let i = (try? await api.getICalSubscriptions()) ?? []
        async let g = (try? await api.getGoogleAccounts()) ?? []
        async let h = (try? await api.getHomeAssistantAccounts()) ?? []
        (caldavAccounts, localCalendars, icalSubs, googleAccounts, haAccounts) = await (c, l, i, g, h)
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
                Section("Konto-Details") {
                    TextField("Anzeigename", text: $name)
                    TextField("CalDAV-URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Benutzername", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passwort", text: $password)
                }
                Section("Farbe") {
                    ColorPicker("Farbe", selection: $color, supportsOpacity: false)
                }
                if !error.isEmpty {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("CalDAV-Konto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Verbinden") {
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

    @State private var name = ""
    @State private var color = Color(hex: "#34a853")
    @State private var isLoading = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    ColorPicker("Farbe", selection: $color, supportsOpacity: false)
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Lokaler Kalender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Erstellen") {
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

    @State private var name = ""
    @State private var url = ""
    @State private var color = Color(hex: "#46bdc6")
    @State private var refreshMinutes = 60
    @State private var isLoading = false
    @State private var error = ""

    let refreshOptions = [(15, "Alle 15 Min."), (30, "Alle 30 Min."), (60, "Stündlich"), (360, "Alle 6 Std."), (1440, "Täglich")]

    var body: some View {
        NavigationStack {
            Form {
                Section("Abonnement") {
                    TextField("Name", text: $name)
                    TextField("iCal-URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    ColorPicker("Farbe", selection: $color, supportsOpacity: false)
                }
                Section("Aktualisierung") {
                    Picker("Intervall", selection: $refreshMinutes) {
                        ForEach(refreshOptions, id: \.0) { opt in
                            Text(opt.1).tag(opt.0)
                        }
                    }
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("iCal abonnieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Abonnieren") {
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

    @State private var name = ""
    @State private var url = ""
    @State private var token = ""
    @State private var isLoading = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Home Assistant") {
                    TextField("Anzeigename", text: $name)
                    TextField("URL (z.B. http://homeassistant.local:8123)", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("Authentifizierung") {
                    SecureField("Long-Lived Access Token", text: $token)
                    Text("Token erstellen unter: Profil → Sicherheit → Long-Lived Access Tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Home Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Verbinden") {
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
