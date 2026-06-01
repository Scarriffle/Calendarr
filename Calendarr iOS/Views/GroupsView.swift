import SwiftUI

// MARK: - Group icons (cross-platform, non-emoji)

/// Canonical group-icon keys stored server-side and rendered as native SF
/// Symbols here (Material on Android, SVG on web), so groups look consistent
/// instead of relying on OS-specific emoji rendering.
enum GroupIcons {
    static let keys = ["people", "home", "heart", "work", "school", "sports",
                       "party", "pet", "travel", "music", "food", "star"]

    static func symbol(_ key: String?) -> String {
        switch key {
        case "people": return "person.2.fill"
        case "home": return "house.fill"
        case "heart": return "heart.fill"
        case "work": return "briefcase.fill"
        case "school": return "graduationcap.fill"
        case "sports": return "figure.run"
        case "party": return "party.popper.fill"
        case "pet": return "pawprint.fill"
        case "travel": return "airplane"
        case "music": return "music.note"
        case "food": return "fork.knife"
        case "star": return "star.fill"
        default: return "person.2.fill"
        }
    }

    static func isKey(_ s: String?) -> Bool { if let s { return keys.contains(s) }; return false }
}

/// Render a group's icon: native SF Symbol for known keys, the legacy emoji for
/// pre-migration groups, else a default people glyph.
struct GroupIconView: View {
    let icon: String?
    var body: some View {
        if GroupIcons.isKey(icon) {
            Image(systemName: GroupIcons.symbol(icon))
        } else if let e = icon, !e.isEmpty {
            Text(e)
        } else {
            Image(systemName: "person.2.fill")
        }
    }
}

// MARK: - Groups list

struct GroupsView: View {
    let api: CalendarrAPI
    @AppStorage("appLanguage") private var appLang = "system"
    @State private var groups: [CalGroup] = []
    @State private var isLoading = true
    @State private var showCreate = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                List {
                    if groups.isEmpty {
                        Text(L10n.t("groups.none", appLang)).foregroundStyle(.secondary)
                    }
                    ForEach(groups) { g in
                        NavigationLink {
                            GroupCombinedView(api: api, group: g)
                        } label: {
                            HStack {
                                GroupIconView(icon: g.icon)
                                Text(g.name)
                                Spacer()
                                if let n = g.memberCount {
                                    Text("\(n)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            NavigationLink {
                                GroupManageSheet(api: api, groupId: g.id) { await load() }
                            } label: {
                                Label(L10n.t("group.manage", appLang), systemImage: "slider.horizontal.3")
                            }.tint(.gray)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.t("groups.title", appLang))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) {
            GroupEditSheet(api: api, existing: nil) { await load() }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        groups = (try? await api.getGroups()) ?? []
        isLoading = false
    }
}

// MARK: - Create / edit a group (name + icon + members)

struct GroupEditSheet: View {
    let api: CalendarrAPI
    let existing: CalGroup?
    let onDone: () async -> Void
    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var appLang = "system"

    @State private var name = ""
    @State private var icon = "people"
    @State private var directory: [DirectoryUser] = []
    @State private var selected: Set<Int> = []
    @State private var error = ""

    private let icons = GroupIcons.keys
    private let cols = [GridItem(.adaptive(minimum: 46))]

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("group.name", appLang)) {
                    TextField(L10n.t("group.name", appLang), text: $name)
                }
                Section(L10n.t("group.icon", appLang)) {
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(icons, id: \.self) { ic in
                            Image(systemName: GroupIcons.symbol(ic))
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(ic == icon ? Color.accentColor.opacity(0.25) : Color(.systemGray6))
                                .foregroundStyle(ic == icon ? Color.accentColor : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { icon = ic }
                        }
                    }
                }
                Section(L10n.t("group.members", appLang)) {
                    ForEach(directory) { u in
                        Button {
                            if selected.contains(u.id) { selected.remove(u.id) } else { selected.insert(u.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(u.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selected.contains(u.id) ? Color.accentColor : .secondary)
                                Text(u.displayName).foregroundStyle(.primary)
                            }
                        }
                    }
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(existing == nil ? L10n.t("group.create", appLang) : L10n.t("group.manage", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("common.cancel", appLang)) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.t("event.save", appLang)) { Task { await save() } }
                        .bold().disabled(name.isEmpty)
                }
            }
        }
        .task { directory = (try? await api.getUserDirectory()) ?? [] }
    }

    private func save() async {
        do {
            _ = try await api.createGroup(name: name, memberIds: Array(selected), icon: icon)
            await onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Manage existing group (rename, icon, members, colors, delete)

struct GroupManageSheet: View {
    let api: CalendarrAPI
    let groupId: Int
    let onDone: () async -> Void
    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var appLang = "system"

    @State private var group: CalGroup?
    @State private var name = ""
    @State private var icon = "people"
    @State private var directory: [DirectoryUser] = []
    @State private var memberIds: Set<Int> = []
    @State private var showDeleteConfirm = false
    @State private var error = ""

    private let icons = GroupIcons.keys
    private let cols = [GridItem(.adaptive(minimum: 46))]

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("group.name", appLang)) {
                    TextField(L10n.t("group.name", appLang), text: $name)
                }
                Section(L10n.t("group.icon", appLang)) {
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(icons, id: \.self) { ic in
                            Image(systemName: GroupIcons.symbol(ic))
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(ic == icon ? Color.accentColor.opacity(0.25) : Color(.systemGray6))
                                .foregroundStyle(ic == icon ? Color.accentColor : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { icon = ic }
                        }
                    }
                }
                Section(L10n.t("group.members", appLang)) {
                    ForEach(directory) { u in
                        Button {
                            if memberIds.contains(u.id) { memberIds.remove(u.id) } else { memberIds.insert(u.id) }
                        } label: {
                            HStack {
                                Image(systemName: memberIds.contains(u.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(memberIds.contains(u.id) ? Color.accentColor : .secondary)
                                Text(u.displayName).foregroundStyle(.primary)
                            }
                        }
                    }
                }
                if let members = group?.members {
                    Section(L10n.t("group.member_colors", appLang)) {
                        ForEach(members) { m in
                            MemberColorRow(api: api, groupId: groupId, member: m)
                        }
                    }
                }
                Section {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label(L10n.t("group.delete", appLang), systemImage: "trash")
                    }
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(L10n.t("group.manage", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("common.cancel", appLang)) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.t("event.save", appLang)) { Task { await save() } }.bold()
                }
            }
            .alert(L10n.t("group.delete", appLang), isPresented: $showDeleteConfirm) {
                Button(L10n.t("group.delete", appLang), role: .destructive) { Task { await deleteGroup() } }
                Button(L10n.t("common.cancel", appLang), role: .cancel) {}
            }
        }
        .task { await load() }
    }

    private func load() async {
        directory = (try? await api.getUserDirectory()) ?? []
        if let g = try? await api.getGroup(id: groupId) {
            group = g
            name = g.name
            icon = GroupIcons.isKey(g.icon) ? g.icon! : "people"
            let me = UserDefaults.standard.integer(forKey: "userId")
            memberIds = Set((g.members ?? []).map { $0.id }.filter { $0 != me })
        }
    }

    private func save() async {
        do {
            try await api.updateGroup(id: groupId, name: name, icon: icon)
            let me = UserDefaults.standard.integer(forKey: "userId")
            let current = Set((group?.members ?? []).map { $0.id }.filter { $0 != me })
            for id in memberIds where !current.contains(id) { try await api.addGroupMember(groupId: groupId, userId: id) }
            for id in current where !memberIds.contains(id) { try await api.removeGroupMember(groupId: groupId, userId: id) }
            await onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func deleteGroup() async {
        do { try await api.deleteGroup(id: groupId); await onDone(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct MemberColorRow: View {
    let api: CalendarrAPI
    let groupId: Int
    let member: GroupMember
    @State private var color: Color

    init(api: CalendarrAPI, groupId: Int, member: GroupMember) {
        self.api = api; self.groupId = groupId; self.member = member
        _color = State(initialValue: Color(hex: member.color ?? "#4285f4"))
    }

    var body: some View {
        HStack {
            Text(member.displayName ?? "—")
            Spacer()
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: color) { _, c in
                    Task { try? await api.setGroupMemberColor(groupId: groupId, userId: member.id, color: c.toHex()) }
                }
        }
    }
}

// MARK: - Combined (overlay) agenda view

struct GroupCombinedView: View {
    let api: CalendarrAPI
    let group: CalGroup
    @AppStorage("appLanguage") private var appLang = "system"

    @State private var anchor = Date()
    @State private var events: [CalEvent] = []
    @State private var isLoading = false

    private var monthRange: (Date, Date) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: anchor)) ?? anchor
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? anchor
        return (start, end)
    }

    private var grouped: [(day: Date, items: [CalEvent])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: events.sorted { $0.startDate < $1.startDate }) {
            cal.startOfDay(for: $0.startDate)
        }
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }

    private let monthFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()
    private let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, d. MMM"; return f
    }()
    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    var body: some View {
        List {
            ForEach(grouped, id: \.day) { section in
                Section(dayFmt.string(from: section.day)) {
                    ForEach(section.items) { ev in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: ev.effectiveColor))
                                .frame(width: 5, height: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayTitle(ev)).font(.body)
                                Text(ev.isAllDay ? L10n.t("event.allday", appLang) : timeFmt.string(from: ev.startDate))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !isLoading && events.isEmpty {
                Text(L10n.t("groups.combined_empty", appLang)).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
            }
            ToolbarItem(placement: .principal) {
                Text(monthFmt.string(from: anchor)).font(.headline)
            }
        }
        .task(id: anchor) { await load() }
    }

    // Prefer the server-decorated title; fall back to a name prefix.
    private func displayTitle(_ ev: CalEvent) -> String {
        if let dt = ev.displayTitle, !dt.isEmpty { return dt }
        let me = UserDefaults.standard.integer(forKey: "userId")
        if let c = ev.creator, ev.isGroupEvent, c.id != me { return "\(firstName(c.displayName)): \(ev.title)" }
        if let o = ev.owner, o.id != me { return "\(firstName(o.displayName)): \(ev.title)" }
        return ev.title
    }
    private func firstName(_ s: String) -> String { s.split(separator: " ").first.map(String.init) ?? s }

    private func shift(_ months: Int) {
        anchor = Calendar.current.date(byAdding: .month, value: months, to: anchor) ?? anchor
    }

    private func load() async {
        isLoading = true
        let (s, e) = monthRange
        events = (try? await api.fetchGroupCombined(groupId: group.id, start: s, end: e)) ?? []
        isLoading = false
    }
}
