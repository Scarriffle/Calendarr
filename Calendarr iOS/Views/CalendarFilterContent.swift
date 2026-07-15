import SwiftUI

/// A single calendar row in the flat, reorderable list.
private struct CalRow: Identifiable {
    let id: String        // "source:id" key
    let name: String
    let colorHex: String
    let readOnly: Bool
}

/// The calendar-visibility list, extracted so both the modal `CalendarFilterSheet`
/// and the side drawer render the same rows/logic. A single flat, drag-reorderable
/// list (no per-source grouping); visibility is client-side (`CalendarStore`),
/// order is device-local (`CalendarStore.calendarOrder`, mirrors the web).
struct CalendarFilterContent: View {
    let api: CalendarrAPI
    let store: CalendarStore
    @AppStorage("appLanguage") private var appLang = "system"

    @State private var caldavAccounts: [CalDAVAccount] = []
    @State private var localCalendars: [LocalCalendar] = []
    @State private var icalSubs: [ICalSubscription] = []
    @State private var googleAccounts: [GoogleAccount] = []
    @State private var haAccounts: [HomeAssistantAccount] = []
    @State private var isLoading = true
    @State private var hidden: Set<String> = []
    @State private var banished: Set<String> = []
    @State private var reminderDisabled: Set<String> = []
    @State private var allKeys: Set<String> = []
    @State private var rows: [CalRow] = []
    @State private var isSorting = false
    @State private var groupDetail: CalGroup? = nil
    @State private var hiddenGroup: Set<String> = []

    var body: some View {
        Group {
            if isLoading {
                ProgressView(L10n.t("filter.loading", appLang))
            } else if store.activeGroup != nil {
                groupFilterList
            } else if allKeys.isEmpty {
                Text(L10n.t("filter.empty", appLang)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    controlBar
                    List {
                        ForEach(rows) { cal in row(cal) }
                            .onMove(perform: move)
                        if !banished.isEmpty {
                            Section {
                                Text(L10n.t("filter.banished_footer", appLang))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(isSorting ? .active : .inactive))
                }
            }
        }
        .task { await load() }
    }

    // Section header + sort toggle, above the list so it stays tappable while
    // the list is in edit mode. (No show/hide-all buttons — rarely needed with a
    // handful of calendars, and the web has none either.)
    private var controlBar: some View {
        HStack {
            Text(L10n.t("filter.title", appLang))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(isSorting ? L10n.t("filter.done", appLang) : L10n.t("filter.sort", appLang)) {
                withAnimation { isSorting.toggle() }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
    }

    private func move(from source: IndexSet, to destination: Int) {
        rows.move(fromOffsets: source, toOffset: destination)
        store.setCalendarOrder(rows.map(\.id))
    }

    @ViewBuilder
    private func row(_ cal: CalRow) -> some View {
        let isVisible = !hidden.contains(cal.id)
        Button {
            if isVisible { hidden.insert(cal.id) } else { hidden.remove(cal.id) }
            store.setCalendarHidden(cal.id, hidden: isVisible)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: cal.colorHex))
                    .frame(width: 14, height: 14)
                    .opacity(isVisible ? 1.0 : 0.35)
                Text(cal.name)
                    .foregroundStyle(isVisible ? .primary : .secondary)
                    .strikethrough(!isVisible, color: .secondary)
                if cal.readOnly {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if reminderDisabled.contains(cal.id) {
                    Image(systemName: "bell.slash").font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(isVisible ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                toggleReminders(forKey: cal.id)
            } label: {
                let disabled = reminderDisabled.contains(cal.id)
                Label(L10n.t(disabled ? "filter.reminders_on" : "filter.reminders_off", appLang),
                      systemImage: disabled ? "bell" : "bell.slash")
            }
            Button(role: .destructive) {
                hidden.remove(cal.id)
                banished.insert(cal.id)
                store.setCalendarBanished(cal.id, banished: true)
                pushBanishToServer(key: cal.id, hidden: true)
                rows.removeAll { $0.id == cal.id }
            } label: {
                Label(L10n.t("filter.banish", appLang), systemImage: "archivebox")
            }
        }
    }

    private func toggleReminders(forKey key: String) {
        let nowDisabled = !reminderDisabled.contains(key)
        if nowDisabled { reminderDisabled.insert(key) } else { reminderDisabled.remove(key) }
        store.setReminderDisabled(key, disabled: nowDisabled)
        if let parsed = CalendarStore.parseCalendarKey(key) {
            Task { try? await api.setCalendarRemindersEnabled(
                source: parsed.source, calendarId: parsed.id, enabled: !nowDisabled) }
        }
    }

    // MARK: – Group overlay (unchanged: hide individual members / group calendar)

    @ViewBuilder
    private var groupFilterList: some View {
        if let g = groupDetail {
            List {
                Section(header: Label(g.name, systemImage: GroupIcons.symbol(g.icon))) {
                    ForEach((g.members ?? []).filter { $0.sharesCalendar }) { m in
                        groupRow(name: m.displayName ?? "—",
                                 colorHex: m.color ?? "#4285f4",
                                 key: CalendarStore.groupMemberKey(m.id))
                    }
                    groupRow(name: L10n.t("group.calendar", appLang),
                             colorHex: g.groupCalendarColor ?? "#4285f4",
                             key: CalendarStore.groupCalendarKey)
                }
            }
        } else {
            Text(L10n.t("filter.empty", appLang)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func groupRow(name: String, colorHex: String, key: String) -> some View {
        let isVisible = !hiddenGroup.contains(key)
        Button {
            if isVisible { hiddenGroup.insert(key) } else { hiddenGroup.remove(key) }
            store.setGroupKeyHidden(key, hidden: isVisible)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 14, height: 14)
                    .opacity(isVisible ? 1.0 : 0.35)
                Text(name)
                    .foregroundStyle(isVisible ? .primary : .secondary)
                    .strikethrough(!isVisible, color: .secondary)
                Spacer()
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(isVisible ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        if let g = store.activeGroup {
            hiddenGroup = store.hiddenGroupKeys
            groupDetail = try? await api.getGroup(id: g.id)
            isLoading = false
            return
        }
        hidden = store.hiddenCalendarKeys
        banished = store.banishedCalendarKeys
        async let c = (try? await api.getCalDAVAccounts()) ?? []
        async let l = (try? await api.getLocalCalendars()) ?? []
        async let i = (try? await api.getICalSubscriptions()) ?? []
        async let g = (try? await api.getGoogleAccounts()) ?? []
        async let h = (try? await api.getHomeAssistantAccounts()) ?? []
        (caldavAccounts, localCalendars, icalSubs, googleAccounts, haAccounts) = await (c, l, i, g, h)

        var b = store.banishedCalendarKeys
        func applyServerHidden(_ source: String, _ id: Int, _ hidden: Bool) {
            let key = CalendarStore.calendarKey(source: source, calendarId: "\(id)")
            if hidden { b.insert(key) } else { b.remove(key) }
        }
        for acc in caldavAccounts { for cal in acc.calendars ?? [] { applyServerHidden("caldav", cal.id, cal.sidebarHidden) } }
        for acc in googleAccounts { for cal in acc.calendars ?? [] { applyServerHidden("google", cal.id, cal.sidebarHidden) } }
        for acc in haAccounts     { for cal in acc.calendars ?? [] { applyServerHidden("homeassistant", cal.id, cal.sidebarHidden) } }
        store.setBanishedCalendars(b)
        banished = b

        var rd = Set<String>()
        func applyReminders(_ source: String, _ id: Int, _ enabled: Bool) {
            if !enabled { rd.insert(CalendarStore.calendarKey(source: source, calendarId: "\(id)")) }
        }
        for cal in localCalendars { applyReminders("local", cal.id, cal.remindersEnabled) }
        for acc in caldavAccounts { for cal in acc.calendars ?? [] { applyReminders("caldav", cal.id, cal.remindersEnabled ?? true) } }
        for sub in icalSubs       { applyReminders("ical", sub.id, sub.remindersEnabled ?? true) }
        for acc in googleAccounts { for cal in acc.calendars ?? [] { applyReminders("google", cal.id, cal.remindersEnabled ?? true) } }
        for acc in haAccounts     { for cal in acc.calendars ?? [] { applyReminders("homeassistant", cal.id, cal.remindersEnabled) } }
        store.setReminderDisabledKeys(rd)
        reminderDisabled = rd

        // Build the flat row list (banished excluded), then sort by stored order.
        var combined: [CalRow] = []
        func add(_ source: String, _ id: Int, _ name: String, _ colorHex: String, readOnly: Bool = false) {
            let key = CalendarStore.calendarKey(source: source, calendarId: "\(id)")
            if b.contains(key) { return }
            combined.append(CalRow(id: key, name: name, colorHex: colorHex, readOnly: readOnly))
        }
        for cal in localCalendars {
            add("local", cal.id, cal.owned ? cal.name : (cal.sharedBy ?? cal.name), cal.color,
                readOnly: !cal.owned && cal.permission != "read_write")
        }
        for acc in caldavAccounts { for cal in acc.calendars ?? [] { add("caldav", cal.id, cal.name, cal.color ?? acc.color) } }
        for sub in icalSubs { add("ical", sub.id, sub.name, sub.color) }
        for acc in googleAccounts { for cal in acc.calendars ?? [] { add("google", cal.id, cal.name, cal.color ?? "#4285f4") } }
        for acc in haAccounts { for cal in acc.calendars ?? [] { add("homeassistant", cal.id, cal.name, cal.color ?? "#46bdc6") } }

        allKeys = Set(combined.map(\.id))
        let orderedKeys = store.ordered(combined.map(\.id))
        let byKey = Dictionary(uniqueKeysWithValues: combined.map { ($0.id, $0) })
        rows = orderedKeys.compactMap { byKey[$0] }
        isLoading = false
    }

    private func pushBanishToServer(key: String, hidden: Bool) {
        guard let parsed = CalendarStore.parseCalendarKey(key),
              CalendarStore.serverManagedSources.contains(parsed.source) else { return }
        Task { try? await api.setCalendarSidebarHidden(source: parsed.source, calendarId: parsed.id, hidden: hidden) }
    }
}
