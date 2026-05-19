import SwiftUI

struct CalendarHostView: View {
    let api: CalendarrAPI
    @Binding var showMenu: Bool

    @AppStorage("liquidGlass") private var liquidGlass = false
    @AppStorage("cacheMonths") private var cacheMonths = 3
    @AppStorage("appLanguage") private var appLang = "system"
    @AppStorage("backgroundColor") private var bgHex = "#000000"

    @State private var store = CalendarStore()
    @State private var showEditor = false
    @State private var editorDate: Date = .now
    @State private var editingEvent: CalEvent? = nil
    @State private var selectedEvent: CalEvent? = nil
    @State private var visibleMonth: Date = .now

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
                    if store.isLoading {
                        ProgressView().padding(.top, 10).transition(.opacity)
                    }
                }
        }
        .overlay(alignment: .bottomTrailing) { solidFAB }
        // Subtle background cache indicator (top-leading)
        .overlay(alignment: .topLeading) {
            if store.isCachingBackground {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .modifier(calendarSheets)
        .task { await startup() }
        .onChange(of: store.currentDate) { _, _ in Task { await onNavigate() } }
        .onChange(of: store.viewType)    { _, _ in Task { await onNavigate() } }
        .onChange(of: cacheMonths)       { _, _ in Task { await recache() } }
        .onChange(of: visibleMonth)      { _, new in Task { await ensureLoaded(around: new) } }
    }

    // MARK: – Liquid Glass variant

    private var glassVariant: some View {
        NavigationStack {
            calendarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: bgHex))
                .overlay(alignment: .top) {
                    if store.isLoading {
                        ProgressView().padding(.top, 10).transition(.opacity)
                    }
                }
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
                      onDayTap: { editorDate = $0 },
                      onEventTap: { selectedEvent = $0 },
                      onCreateEvent: { day in
                          editingEvent = nil
                          editorDate = day
                          showEditor = true
                      },
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
                     onCreateEvent: { date in
                         editingEvent = nil
                         editorDate = date
                         showEditor = true
                     },
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
                    onCreateEvent: { date in
                        editingEvent = nil
                        editorDate = date
                        showEditor = true
                    })
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
            editingEvent = nil; editorDate = .now; showEditor = true
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
                editingEvent = nil; editorDate = .now; showEditor = true
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
        CalendarSheets(store: store, showEditor: $showEditor,
                       editorDate: $editorDate, editingEvent: $editingEvent,
                       selectedEvent: $selectedEvent, api: api,
                       reload: { await onNavigate() })
    }

    // MARK: – Loading logic

    private func startup() async {
        await store.loadWritableCalendars(api: api)
        // 1. Load current view immediately (visible)
        let (s, e) = store.rangeForCurrentView()
        await store.loadEvents(api: api, start: s, end: e)
        // 2. Background prefetch for the configured range (non-blocking)
        Task(priority: .background) {
            await store.prefetchBackground(api: api, months: cacheMonths)
        }
    }

    /// Called on every navigation – instant if within cache, fetches otherwise.
    private func onNavigate() async {
        let (s, e) = store.rangeForCurrentView()
        await store.loadEvents(api: api, start: s, end: e)
    }

    /// Called when cacheMonths setting changes – clear cache and re-prefetch.
    private func recache() async {
        store.invalidateCache()
        await startup()
    }

    /// Called when the user scrolls into a new month – fetches a ±1 month window
    /// around it on demand. `loadEvents` skips the network if cached.
    private func ensureLoaded(around month: Date) async {
        let cal = store.userCalendar
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let s = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let e = cal.date(byAdding: .month, value:  2, to: monthStart) ?? monthStart
        await store.loadEvents(api: api, start: s, end: e)
    }
}

// MARK: – Shared sheet modifier

private struct CalendarSheets: ViewModifier {
    let store: CalendarStore
    @Binding var showEditor: Bool
    @Binding var editorDate: Date
    @Binding var editingEvent: CalEvent?
    @Binding var selectedEvent: CalEvent?
    let api: CalendarrAPI
    let reload: () async -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showEditor) {
                EventEditorSheet(api: api, store: store,
                                 initialDate: editorDate, editingEvent: editingEvent) {
                    editingEvent = nil; await reload()
                }
            }
            .sheet(item: $selectedEvent) { ev in
                EventDetailSheet(event: ev, api: api, store: store) { updated in
                    selectedEvent = nil
                    if let u = updated { editingEvent = u; showEditor = true }
                    await reload()
                }
            }
    }
}
