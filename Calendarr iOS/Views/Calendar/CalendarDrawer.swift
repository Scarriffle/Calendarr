import SwiftUI

/// The left side drawer: calendar visibility + group/view switching, plus a
/// single entry into the full menu (Settings/Accounts/Profile/…/Sync/Logout).
struct CalendarDrawer: View {
    let api: CalendarrAPI
    let store: CalendarStore
    let groups: [CalGroup]
    let onSwitchGroup: (CalGroup?) -> Void
    let onSelectView: (CalViewType) -> Void
    let onOpenMenu: () -> Void
    let onSync: () -> Void
    let onClose: () -> Void

    @Environment(AppState.self) private var appState
    @AppStorage("appLanguage") private var appLang = "system"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            viewSwitcher
            if !groups.isEmpty {
                Divider()
                groupSwitcher
            }
            Divider()
            CalendarFilterContent(api: api, store: store)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }

    // MARK: – Header

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(appState.username.prefix(1).uppercased())
                        .font(.headline).foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.username).font(.headline).lineLimit(1)
                Text(appState.serverURL
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 18) {
                Button { onSync() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                .accessibilityLabel(L10n.t("menu.sync", appLang))
                Button { onOpenMenu() } label: {
                    Image(systemName: "gearshape").font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                .accessibilityLabel(L10n.t("menu.section.settings", appLang))
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }

    // MARK: – View switcher

    private var viewSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CalViewType.allCases, id: \.self) { vt in
                    let selected = store.viewType == vt
                    Button { onSelectView(vt) } label: {
                        Label(vt.label(appLang), systemImage: vt.systemImage)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(selected ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundStyle(selected ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    // MARK: – Group switcher

    private var groupSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: L10n.t("groups.personal", appLang),
                     systemImage: "person",
                     selected: store.activeGroup == nil) { onSwitchGroup(nil) }
                ForEach(groups) { g in
                    chip(label: g.name,
                         systemImage: GroupIcons.symbol(g.icon),
                         selected: store.activeGroup?.id == g.id) { onSwitchGroup(g) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private func chip(label: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

}
