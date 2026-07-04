import SwiftUI

/// Lets the user toggle which calendars contribute events to the displayed
/// calendar views (and the home-screen widgets). Filtering is purely
/// client-side: hidden keys live in UserDefaults via `CalendarStore`. No
/// server roundtrip is required to toggle visibility.
struct CalendarFilterSheet: View {
    let api: CalendarrAPI
    let store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLang = "system"

    @State private var caldavAccounts: [CalDAVAccount] = []
    @State private var localCalendars: [LocalCalendar] = []
    @State private var icalSubs: [ICalSubscription] = []
    @State private var googleAccounts: [GoogleAccount] = []
    @State private var haAccounts: [HomeAssistantAccount] = []
    @State private var isLoading = true
    @State private var hidden: Set<String> = []
    @State private var banished: Set<String> = []
    /// Calendars whose events do not generate reminder notifications.
    @State private var reminderDisabled: Set<String> = []
    /// All non-banished keys discovered during load — used by bulk show/hide.
    @State private var allKeys: Set<String> = []
    /// Group-mode: the active group's full detail (members + colours) and the
    /// per-member / group-calendar hidden keys.
    @State private var groupDetail: CalGroup? = nil
    @State private var hiddenGroup: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(L10n.t("filter.loading", appLang))
                } else if store.activeGroup != nil {
                    groupFilterList
                } else if allKeys.isEmpty {
                    Text(L10n.t("filter.empty", appLang))
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        let visibleLocals = localCalendars.filter {
                            !banished.contains(CalendarStore.calendarKey(source: "local", calendarId: "\($0.id)"))
                        }
                        if !visibleLocals.isEmpty {
                            Section(L10n.t("accounts.local.header", appLang)) {
                                ForEach(visibleLocals) { cal in
                                    // A calendar shared with me is shown under the owner's
                                    // name and flagged read-only when I can't write to it.
                                    row(name: cal.owned ? cal.name : (cal.sharedBy ?? cal.name),
                                        colorHex: cal.color,
                                        key: CalendarStore.calendarKey(source: "local", calendarId: "\(cal.id)"),
                                        readOnly: !cal.owned && cal.permission != "read_write")
                                }
                            }
                        }
                        ForEach(caldavAccounts) { acc in
                            let cals = (acc.calendars ?? []).filter {
                                !banished.contains(CalendarStore.calendarKey(source: "caldav", calendarId: "\($0.id)"))
                            }
                            if !cals.isEmpty {
                                Section(acc.name) {
                                    ForEach(cals) { cal in
                                        row(name: cal.name,
                                            colorHex: cal.color ?? acc.color,
                                            key: CalendarStore.calendarKey(source: "caldav", calendarId: "\(cal.id)"))
                                    }
                                }
                            }
                        }
                        let visibleSubs = icalSubs.filter {
                            !banished.contains(CalendarStore.calendarKey(source: "ical", calendarId: "\($0.id)"))
                        }
                        if !visibleSubs.isEmpty {
                            Section(L10n.t("accounts.ical.header", appLang)) {
                                ForEach(visibleSubs) { sub in
                                    row(name: sub.name, colorHex: sub.color,
                                        key: CalendarStore.calendarKey(source: "ical", calendarId: "\(sub.id)"))
                                }
                            }
                        }
                        ForEach(googleAccounts) { acc in
                            let cals = (acc.calendars ?? []).filter {
                                !banished.contains(CalendarStore.calendarKey(source: "google", calendarId: "\($0.id)"))
                            }
                            if !cals.isEmpty {
                                Section(acc.email) {
                                    ForEach(cals) { cal in
                                        row(name: cal.name,
                                            colorHex: cal.color ?? "#4285f4",
                                            key: CalendarStore.calendarKey(source: "google", calendarId: "\(cal.id)"))
                                    }
                                }
                            }
                        }
                        ForEach(haAccounts) { acc in
                            let cals = (acc.calendars ?? []).filter {
                                !banished.contains(CalendarStore.calendarKey(source: "homeassistant", calendarId: "\($0.id)"))
                            }
                            if !cals.isEmpty {
                                Section(acc.name) {
                                    ForEach(cals) { cal in
                                        row(name: cal.name,
                                            colorHex: cal.color ?? "#46bdc6",
                                            key: CalendarStore.calendarKey(source: "homeassistant", calendarId: "\(cal.id)"))
                                    }
                                }
                            }
                        }
                        if !banished.isEmpty {
                            Section {
                                Text(L10n.t("filter.banished_footer", appLang))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("filter.title", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button(L10n.t("filter.show_all", appLang)) {
                            hidden = []
                            store.setHiddenCalendars(hidden)
                        }
                        Button(L10n.t("filter.hide_all", appLang)) {
                            hidden = allKeys
                            store.setHiddenCalendars(hidden)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(allKeys.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.t("nav.done", appLang)) { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func row(name: String, colorHex: String, key: String, readOnly: Bool = false) -> some View {
        let isVisible = !hidden.contains(key)
        Button {
            if isVisible { hidden.insert(key) } else { hidden.remove(key) }
            // New hidden state == was-visible (flip). Previous code passed the
            // inverse, which persisted the opposite of what the UI showed.
            store.setCalendarHidden(key, hidden: isVisible)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 14, height: 14)
                    .opacity(isVisible ? 1.0 : 0.35)
                Text(name)
                    .foregroundStyle(isVisible ? .primary : .secondary)
                    .strikethrough(!isVisible, color: .secondary)
                if readOnly {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if reminderDisabled.contains(key) {
                    Image(systemName: "bell.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(isVisible ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            let disabled = reminderDisabled.contains(key)
            Button {
                toggleReminders(forKey: key)
            } label: {
                Label(L10n.t(disabled ? "filter.reminders_on" : "filter.reminders_off", appLang),
                      systemImage: disabled ? "bell" : "bell.slash")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                hidden.remove(key)
                banished.insert(key)
                store.setCalendarBanished(key, banished: true)
                pushBanishToServer(key: key, hidden: true)
            } label: {
                Label(L10n.t("filter.banish", appLang), systemImage: "archivebox")
            }
        }
    }

    /// Flip a calendar's reminder mute, persist locally + on the server, reschedule.
    private func toggleReminders(forKey key: String) {
        let nowDisabled = !reminderDisabled.contains(key)
        if nowDisabled { reminderDisabled.insert(key) } else { reminderDisabled.remove(key) }
        store.setReminderDisabled(key, disabled: nowDisabled)
        if let parsed = CalendarStore.parseCalendarKey(key) {
            Task { try? await api.setCalendarRemindersEnabled(
                source: parsed.source, calendarId: parsed.id, enabled: !nowDisabled) }
        }
    }

    // MARK: – Group overlay filter (hide individual members / the group calendar)

    @ViewBuilder
    private var groupFilterList: some View {
        if let g = groupDetail {
            List {
                Section(header: Label(g.name, systemImage: GroupIcons.symbol(g.icon))) {
                    ForEach(g.members ?? []) { m in
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
        // Group overlay: list members (+ the group calendar) to hide individually.
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

        // Reconcile banished state with the server's sidebar_hidden flags
        // (server wins for CalDAV/Google/HA; local/ical keep their local state).
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

        // Reconcile reminder-muted state from the server's reminders_enabled flags.
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

        var keys = Set<String>()
        for cal in localCalendars {
            keys.insert(CalendarStore.calendarKey(source: "local", calendarId: "\(cal.id)"))
        }
        for acc in caldavAccounts {
            for cal in acc.calendars ?? [] {
                keys.insert(CalendarStore.calendarKey(source: "caldav", calendarId: "\(cal.id)"))
            }
        }
        for sub in icalSubs {
            keys.insert(CalendarStore.calendarKey(source: "ical", calendarId: "\(sub.id)"))
        }
        for acc in googleAccounts {
            for cal in acc.calendars ?? [] {
                keys.insert(CalendarStore.calendarKey(source: "google", calendarId: "\(cal.id)"))
            }
        }
        for acc in haAccounts {
            for cal in acc.calendars ?? [] {
                keys.insert(CalendarStore.calendarKey(source: "homeassistant", calendarId: "\(cal.id)"))
            }
        }
        allKeys = keys
        isLoading = false
    }

    /// For server-backed sources, persist the banish on the server too.
    private func pushBanishToServer(key: String, hidden: Bool) {
        guard let parsed = CalendarStore.parseCalendarKey(key),
              CalendarStore.serverManagedSources.contains(parsed.source) else { return }
        Task { try? await api.setCalendarSidebarHidden(source: parsed.source, calendarId: parsed.id, hidden: hidden) }
    }
}
