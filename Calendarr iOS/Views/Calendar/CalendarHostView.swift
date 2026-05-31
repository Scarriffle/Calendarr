import SwiftUI

private enum CalEditorContext: Identifiable {
    case create(Date)
    case edit(CalEvent)
    var id: String {
        switch self {
        case .create(let d): return "new-\(d.timeIntervalSince1970)"
        case .edit(let ev): return "edit-\(ev.id)"
        }
    }
}

struct CalendarHostView: View {
    let api: CalendarrAPI
    @Binding var showMenu: Bool

    @AppStorage("liquidGlass") private var liquidGlass = false
    @AppStorage("cacheMonths") private var cacheMonths = 3
    @AppStorage("appLanguage") private var appLang = "system"
    @AppStorage("backgroundColor") private var bgHex = "#000000"
    @AppStorage("weekStartDay") private var weekStartDay = "monday"
    @AppStorage("defaultView")  private var defaultView = "month"

    @Environment(\.scenePhase) private var scenePhase

    @State private var store = CalendarStore()
    @State private var editorContext: CalEditorContext? = nil
    @State private var selectedEvent: CalEvent? = nil
    @State private var visibleMonth: Date = .now
    @State private var showFilter = false
    @State private var didApplyDefaultView = false

    private var titleString: String {
        if store.viewType == .month {
            let f = DateFormatter()
            f.locale = L10n.locale(appLang)
            f.dateFormat = "LLLL yyyy"
            return f.string(from: visibleMonth).capitalized(with: L10n.locale(appLang))
        }
        return store.titleForCurrentView(language: appLang)
    }

    var body: some View {
        if liquidGlass {
            glassVariant
        } else {
            flatVariant
        }
    }

    // MARK: – Loading indicator

    @ViewBuilder
    private var loadingIndicator: some View {
        if store.isLoading || store.isCachingBackground {
            ProgressView()
                .padding(14)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }

    // MARK: – Flat variant

    private var flatVariant: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            errorBanner
            calendarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: bgHex))
                .overlay(alignment: .top) {
                    loadingIndicator.padding(.top, 12)
                }
                .animation(.easeInOut(duration: 0.2), value: store.isLoading || store.isCachingBackground)
        }
        .overlay(alignment: .bottomTrailing) { solidFAB }
        .modifier(calendarSheets)
        .task { await startup() }
        .onChange(of: store.currentDate) { _, _ in Task { await onNavigate() } }
        .onChange(of: store.viewType)    { _, _ in Task { await onNavigate() } }
        .onChange(of: cacheMonths)       { _, _ in Task { await recache() } }
        .onChange(of: visibleMonth)      { _, new in Task { await ensureLoaded(around: new) } }
        .onChange(of: scenePhase)        { _, phase in if phase == .active { Task { await SettingsSync.pull(api: api) } } }
        .onReceive(NotificationCenter.default.publisher(for: .banishedCalendarsChanged)) { _ in
            store.syncBanishedFromDefaults()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidChange)) { _ in
            applyServerDrivenSettings(initial: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .manualSyncRequested)) { _ in
            Task { await forceReload() }
        }
    }

    // MARK: – Liquid Glass variant

    private var glassVariant: some View {
        NavigationStack {
            calendarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: bgHex))
                .overlay(alignment: .top) {
                    loadingIndicator.padding(.top, 12)
                }
                .animation(.easeInOut(duration: 0.2), value: store.isLoading || store.isCachingBackground)
                .overlay(alignment: .top) {
                    if let err = store.lastError { errorBannerView(err).padding(.top, 8) }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 2) {
                            Button { store.navigatePrev() } label: { Image(systemName: "chevron.left") }
                            Button { store.navigateNext() } label: { Image(systemName: "chevron.right") }
                            Button(L10n.t("nav.today", appLang)) { store.moveToToday() }.font(.callout)
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        Text(titleString)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 8) {
                            viewPickerMenu
                            Button { showFilter = true } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(store.hiddenCalendarKeys.isEmpty ? .primary : Color.accentColor)
                            }
                            .accessibilityLabel(L10n.t("filter.button", appLang))
                            Button { showMenu = true } label: { Image(systemName: "line.3.horizontal") }
                        }
                    }
                }
        }
        .overlay(alignment: .bottomTrailing) { glassFAB }
        .modifier(calendarSheets)
        .task { await startup() }
        .onChange(of: store.currentDate) { _, _ in Task { await onNavigate() } }
        .onChange(of: store.viewType)    { _, _ in Task { await onNavigate() } }
        .onChange(of: cacheMonths)       { _, _ in Task { await recache() } }
        .onChange(of: visibleMonth)      { _, new in Task { await ensureLoaded(around: new) } }
        .onChange(of: scenePhase)        { _, phase in if phase == .active { Task { await SettingsSync.pull(api: api) } } }
        .onReceive(NotificationCenter.default.publisher(for: .banishedCalendarsChanged)) { _ in
            store.syncBanishedFromDefaults()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidChange)) { _ in
            applyServerDrivenSettings(initial: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .manualSyncRequested)) { _ in
            Task { await forceReload() }
        }
    }

    // MARK: – Top bar (flat mode)

    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                Button { store.navigatePrev() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                Button { store.navigateNext() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                Button(L10n.t("nav.today", appLang)) { store.moveToToday() }
                    .font(.callout).padding(.horizontal, 6)
            }
            .padding(.leading, 8)
            Spacer(minLength: 8)
            Text(titleString)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            viewPickerMenu
            filterButton
            Button { showMenu = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 40)
            }
            .padding(.trailing, 4)
        }
        .frame(height: 48)
        .background(.bar)
    }

    private var filterButton: some View {
        Button { showFilter = true } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(store.hiddenCalendarKeys.isEmpty ? .primary : Color.accentColor)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel(L10n.t("filter.button", appLang))
    }

    private var viewPickerMenu: some View {
        Menu {
            ForEach(CalViewType.allCases, id: \.self) { vt in
                Button { store.viewType = vt } label: {
                    Label(vt.label(appLang), systemImage: vt.systemImage)
                }
            }
        } label: {
            Image(systemName: store.viewType.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel(L10n.t("view.change", appLang))
    }

    // MARK: – Error banner

    @ViewBuilder private var errorBanner: some View {
        if let err = store.lastError { errorBannerView(err) }
    }

    private func errorBannerView(_ err: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(err).font(.caption).foregroundStyle(.white).lineLimit(2)
            Spacer()
            Button { Task { await onNavigate() } } label: {
                Image(systemName: "arrow.clockwise").foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.red.opacity(0.85))
    }

    // MARK: – Calendar content (with swipe)

    @ViewBuilder
    private var calendarContent: some View {
        let swipe = DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onEnded { val in
                let h = val.translation.width
                let v = val.translation.height
                guard abs(h) > abs(v) * 1.2, abs(h) > 28 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if h < 0 { store.navigateNext() } else { store.navigatePrev() }
                }
            }
        switch store.viewType {
        case .month:
            // Month view uses vertical scroll – no horizontal swipe.
            MonthView(store: store,
                      onDayTap: { store.currentDate = $0 },
                      onEventTap: { selectedEvent = $0 },
                      onCreateEvent: { day in editorContext = .create(day) },
                      onShowWeek: { day in
                          store.currentDate = day
                          store.viewType = .week
                      },
                      onShowDay: { day in
                          store.currentDate = day
                          store.viewType = .day
                      },
                      visibleMonth: $visibleMonth)
        case .week:
            WeekView(store: store,
                     onEventTap: { selectedEvent = $0 },
                     onCreateEvent: { date in editorContext = .create(date) },
                     onShowMonth: { date in
                         store.currentDate = date
                         store.viewType = .month
                     },
                     onShowDay: { date in
                         store.currentDate = date
                         store.viewType = .day
                     })
                .simultaneousGesture(swipe)
        case .day:
            DayView(store: store,
                    onEventTap: { selectedEvent = $0 },
                    onCreateEvent: { date in editorContext = .create(date) })
                .simultaneousGesture(swipe)
        case .quarter:
            QuarterView(store: store, onEventTap: { selectedEvent = $0 })
                .simultaneousGesture(swipe)
        case .agenda:
            AgendaView(store: store, onEventTap: { selectedEvent = $0 })
        }
    }

    // MARK: – FAB buttons

    /// Standard solid FAB (flat mode)
    private var solidFAB: some View {
        Button {
            editorContext = .create(.now)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(radius: 4, y: 2)
        }
        .padding(.trailing, 20).padding(.bottom, 20)
    }

    /// Liquid Glass FAB (iOS 26) with glass effect; falls back to solid on older OS
    @ViewBuilder
    private var glassFAB: some View {
        if #available(iOS 26, *) {
            Button {
                editorContext = .create(.now)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .glassEffect(in: Circle())
            .padding(.trailing, 20).padding(.bottom, 20)
        } else {
            solidFAB
        }
    }

    // MARK: – Sheets modifier

    private var calendarSheets: CalendarSheets {
        CalendarSheets(store: store, editorContext: $editorContext,
                       selectedEvent: $selectedEvent, showFilter: $showFilter,
                       api: api,
                       reload: { await onNavigate() },
                       reloadForce: { await reloadVisible(force: true) })
    }

    // MARK: – Loading logic

    private func startup() async {
        // 0. Pull settings first so week-start / default-view are correct
        //    before we compute the initial range and load events.
        await SettingsSync.pull(api: api)
        applyServerDrivenSettings(initial: true)

        await store.loadWritableCalendars(api: api)
        // 1. Load current view immediately (visible)
        let (s, e) = store.rangeForCurrentView()
        await store.loadEvents(api: api, start: s, end: e)
        // 2. Background prefetch for the configured range (non-blocking)
        Task(priority: .background) {
            await store.prefetchBackground(api: api, months: cacheMonths)
        }
        // 3. Periodic settings pull (tied to this .task's lifetime).
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(600))
            if Task.isCancelled { break }
            await SettingsSync.pull(api: api)
        }
    }

    /// Apply the server-driven "always sync" settings to the live store.
    /// `weekStartsOnMonday` is applied every time; the default view is applied
    /// only once at startup so it never overrides the user's manual switches.
    private func applyServerDrivenSettings(initial: Bool) {
        store.weekStartsOnMonday = (weekStartDay != "sunday")
        if initial, !didApplyDefaultView {
            didApplyDefaultView = true
            if let vt = CalViewType(rawValue: defaultView) {
                store.viewType = vt
            }
        }
    }

    /// Called on every navigation – instant if within cache, fetches otherwise.
    private func onNavigate() async {
        let (s, e) = store.rangeForCurrentView()
        await store.loadEvents(api: api, start: s, end: e)
    }

    /// Re-fetch the visible range. With `force` it bypasses the cache so a just
    /// created/edited event shows up immediately (the server is authoritative).
    private func reloadVisible(force: Bool) async {
        let (s, e) = store.rangeForCurrentView()
        await store.loadEvents(api: api, start: s, end: e, force: force)
    }

    /// Called when cacheMonths setting changes – clear cache and re-prefetch.
    private func recache() async {
        store.invalidateCache()
        await startup()
    }

    /// Manual sync from the menu: drop the event cache and re-fetch from the
    /// server (the periodic loop in `startup()` is untouched, so we don't spawn
    /// a second one). Settings were already pulled by the menu action.
    private func forceReload() async {
        store.invalidateCache()
        let (s, e) = store.rangeForCurrentView()
        await store.loadEvents(api: api, start: s, end: e)
        Task(priority: .background) {
            await store.prefetchBackground(api: api, months: cacheMonths)
        }
    }

    /// Called when the user scrolls into a new month – refreshes the visible range
    /// immediately from cache, then fetches on demand if needed.
    private func ensureLoaded(around month: Date) async {
        let cal = store.userCalendar
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let s = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let e = cal.date(byAdding: .month, value:  2, to: monthStart) ?? monthStart

        // Only narrow the visible event set if the requested window is already cached.
        // Otherwise keep the current events visible until the network fetch finishes,
        // so previous/current/next month events don't disappear temporarily.
        if store.isCached(start: s, end: e) {
            store.refreshFromCache(start: s, end: e)
        }

        await store.loadEvents(api: api, start: s, end: e)
    }
}

// MARK: – Shared sheet modifier

private struct CalendarSheets: ViewModifier {
    let store: CalendarStore
    @Binding var editorContext: CalEditorContext?
    @Binding var selectedEvent: CalEvent?
    @Binding var showFilter: Bool
    let api: CalendarrAPI
    let reload: () async -> Void
    let reloadForce: () async -> Void

    func body(content: Content) -> some View {
        content
            // Use sheet(item:) so the editing event is captured atomically –
            // avoiding the race where sheet(isPresented:) evaluates its content
            // before the editingEvent state update propagates.
            .sheet(item: $editorContext) { ctx in
                let editingEv: CalEvent? = { if case .edit(let ev) = ctx { return ev }; return nil }()
                let date: Date = { if case .create(let d) = ctx { return d }; return .now }()
                EventEditorSheet(api: api, store: store,
                                 initialDate: date, editingEvent: editingEv) {
                    editorContext = nil
                    await reloadForce()
                }
            }
            .sheet(item: $selectedEvent) { ev in
                EventDetailSheet(event: ev, api: api, store: store) { updated, needsForce in
                    selectedEvent = nil
                    if let u = updated { editorContext = .edit(u) }
                    if needsForce { await reloadForce() } else { await reload() }
                }
            }
            .sheet(isPresented: $showFilter) {
                CalendarFilterSheet(api: api, store: store)
            }
    }
}
