import SwiftUI

/// Modal wrapper around `CalendarFilterContent` (kept for contexts that still
/// present the filter as a sheet). The drawer embeds the same content directly.
struct CalendarFilterSheet: View {
    let api: CalendarrAPI
    let store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLang = "system"

    var body: some View {
        NavigationStack {
            CalendarFilterContent(api: api, store: store)
                .navigationTitle(L10n.t("filter.title", appLang))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(L10n.t("nav.done", appLang)) { dismiss() }
                    }
                }
        }
    }
}
