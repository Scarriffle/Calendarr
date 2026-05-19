import SwiftUI

struct SettingsView: View {
    let api: CalendarrAPI
    @State private var settings = AppSettings()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var toast = ""
    @State private var showToast = false
    @AppStorage("liquidGlass")       private var liquidGlass = false
    @AppStorage("cacheMonths")       private var cacheMonths = 3
    @AppStorage("appLanguage")       private var appLang = "system"
    @AppStorage("monthDividerColor") private var dividerHex = "#7090c0"
    @AppStorage("monthLabelColor")   private var labelHex = "#7090c0"
    @AppStorage("todayColor")        private var todayHex = "#4285f4"
    @AppStorage("textColor")         private var textHex = "#FFFFFF"
    @AppStorage("backgroundColor")   private var bgHex = "#000000"
    @AppStorage("lineColor")         private var lineHex = "#3A3A3C"

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(L10n.t("settings.loading", appLang))
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
            .navigationTitle(L10n.t("settings.title", appLang))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(L10n.t("settings.save", appLang)).bold()
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
        } header: {
            Text(L10n.t("settings.appdesign", appLang))
        } footer: {
            Text(L10n.t("settings.liquidglass.footer", appLang))
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
            ColorPickerRow(label: L10n.t("settings.color.primary",    appLang), hex: $settings.primaryColor)
            ColorPickerRow(label: L10n.t("settings.color.accent",     appLang), hex: $settings.accentColor)
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
                    value: $settings.textContrast,
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
                    value: $settings.lineContrast,
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
            Picker(L10n.t("settings.defaultview", appLang), selection: $settings.defaultView) {
                Text(L10n.t("view.month",   appLang)).tag("month")
                Text(L10n.t("view.week",    appLang)).tag("week")
                Text(L10n.t("view.day",     appLang)).tag("day")
                Text(L10n.t("view.quarter", appLang)).tag("quarter")
                Text(L10n.t("view.agenda",  appLang)).tag("agenda")
            }
            Picker(L10n.t("settings.firstweekday", appLang), selection: $settings.weekStartDay) {
                Text(L10n.t("settings.monday", appLang)).tag("monday")
                Text(L10n.t("settings.sunday", appLang)).tag("sunday")
            }
            Toggle(L10n.t("settings.dimpast", appLang), isOn: $settings.dimPastEvents)
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
                    value: $settings.hourHeight,
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

    // MARK: – Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let s = try? await api.getSettings() {
            settings = s
            // Mirror server-side color settings so calendar views (which read AppStorage) see them.
            dividerHex = s.monthDividerColor
            labelHex   = s.monthLabelColor
            todayHex   = s.todayColor
            textHex    = s.textColor
            bgHex      = s.backgroundColor
            lineHex    = s.lineColor
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        // Push local AppStorage colors back into the settings struct before saving.
        settings.monthDividerColor = dividerHex
        settings.monthLabelColor   = labelHex
        settings.todayColor        = todayHex
        settings.textColor         = textHex
        settings.backgroundColor   = bgHex
        settings.lineColor         = lineHex
        do {
            try await api.updateSettings(settings)
            showNotice(L10n.t("settings.saved", appLang))
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
