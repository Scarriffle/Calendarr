import SwiftUI

struct SettingsView: View {
    let api: CalendarrAPI
    @State private var settings = AppSettings()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var toast = ""
    @State private var showToast = false
    @AppStorage("liquidGlass") private var liquidGlass = false
    @AppStorage("cacheMonths") private var cacheMonths = 3

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Lade Einstellungen…")
                } else {
                    Form {
                        liquidGlassSection
                        cacheSection
                        spracheSection
                        farbenSection
                        schriftSection
                        linienSection
                        ansichtSection
                        stundenSection
                    }
                }
            }
            .navigationTitle("Darstellung")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Speichern").bold()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .overlay(alignment: .bottom) {
                if showToast {
                    Text(toast)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: showToast)
        }
        .task { await load() }
    }

    // MARK: – Liquid Glass

    var liquidGlassSection: some View {
        Section {
            Toggle(isOn: $liquidGlass) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Liquid Glass")
                        Text("Verwendet die neue iOS\u{202F}26 Glasoptik mit transparenter Navigationsleiste")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.blue)
                }
            }
            .tint(Color.accentColor)
        } header: {
            Text("App-Design")
        } footer: {
            Text("Änderung wirkt sofort – kein Neustart nötig.")
                .font(.caption)
        }
    }

    // MARK: – Cache

    var cacheSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vorladen")
                        Text("Events werden beim Start im Hintergrund für diesen Zeitraum geladen, danach ist Wischen sofort.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.green)
                }

                Picker("Zeitraum", selection: $cacheMonths) {
                    Text("±1 Monat").tag(1)
                    Text("±3 Monate").tag(3)
                    Text("±6 Monate").tag(6)
                    Text("±1 Jahr").tag(12)
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Vorladen")
        } footer: {
            Text("Mehr Monate = längerer initialer Ladevorgang, danach komplett ohne Wartezeiten navigierbar.")
                .font(.caption)
        }
    }

    // MARK: – Sprache

    var spracheSection: some View {
        Section("Sprache") {
            Picker("Sprache", selection: $settings.language) {
                Text("Deutsch").tag("de")
                Text("English").tag("en")
            }
        }
    }

    // MARK: – Farben

    var farbenSection: some View {
        Section("Farben") {
            ColorPickerRow(label: "Primärfarbe", hex: $settings.primaryColor)
            ColorPickerRow(label: "Akzentfarbe", hex: $settings.accentColor)
            ColorPickerRow(label: "Heutige-Tag-Farbe", hex: $settings.todayColor)
            ColorPickerRow(label: "Monatswechsel-Linie", hex: $settings.monthDividerColor)
            ColorPickerRow(label: "Monatskürzel", hex: $settings.monthLabelColor)
        }
    }

    // MARK: – Schriftkontrast

    var schriftSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Schriftkontrast")
                    .font(.headline)
                Text("Helligkeit der Beschriftungen und Texte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ContrastSelector(
                    value: $settings.textContrast,
                    options: [
                        (1, "Dunkel"),
                        (2, "Mittel"),
                        (3, "Hell"),
                        (4, "Maximum")
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
                Text("Linienkontrast")
                    .font(.headline)
                Text("Sichtbarkeit von Trennlinien und Rahmen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ContrastSelector(
                    value: $settings.lineContrast,
                    options: [
                        (1, "Kaum"),
                        (2, "Subtil"),
                        (3, "Normal"),
                        (4, "Stark")
                    ]
                )
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: – Ansicht

    var ansichtSection: some View {
        Section("Kalenderansicht") {
            Picker("Standardansicht", selection: $settings.defaultView) {
                Text("Monat").tag("month")
                Text("Woche").tag("week")
                Text("Tag").tag("day")
                Text("Quartal").tag("quarter")
                Text("Termine").tag("agenda")
            }
            Picker("Erster Wochentag", selection: $settings.weekStartDay) {
                Text("Montag").tag("monday")
                Text("Sonntag").tag("sunday")
            }
            Toggle("Vergangene Termine ausgrauen", isOn: $settings.dimPastEvents)
                .tint(Color.accentColor)
        }
    }

    // MARK: – Stundenhöhe

    var stundenSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stundenhöhe")
                    .font(.headline)
                Text("Platz pro Stunde in der Wochen- & Tagesansicht")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ContrastSelector(
                    value: $settings.hourHeight,
                    options: [
                        (28, "Kompakt"),
                        (44, "Normal"),
                        (60, "Komfort"),
                        (80, "Gross")
                    ]
                )
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: – Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let s = try? await api.getSettings() { settings = s }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await api.updateSettings(settings)
            showNotice("Gespeichert")
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    private func showNotice(_ msg: String) {
        toast = msg
        withAnimation { showToast = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showToast = false }
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
