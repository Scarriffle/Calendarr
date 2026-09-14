import SwiftUI

/// `.sheet(item:)` needs Identifiable and URL is not. A retroactive conformance
/// on a stdlib type would be visible module-wide, so wrap it instead.
private struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct EventDetailSheet: View {
    let event: CalEvent
    let api: CalendarrAPI
    let store: CalendarStore
    /// Called when the sheet should close.
    /// - `editEvent`: non-nil when the user wants to edit this event
    /// - `forceReload`: true when server data changed (create/copy) and the
    ///   caller must bypass the cache to fetch fresh events
    let onDone: (_ editEvent: CalEvent?, _ forceReload: Bool) async -> Void

    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var appLang = "system"
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showCopySheet = false
    @State private var attachments: [EventAttachment] = []
    @State private var thumbnails: [Int: UIImage] = [:]
    @State private var loadingAttachments = false
    @State private var sharedFile: SharedFile?

    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var timeString: String {
        if event.isAllDay {
            if Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate) ||
               event.endDate == event.startDate {
                return "\(L10n.t("event.allday", appLang)) · \(dateFmt.string(from: event.startDate))"
            }
            let end = Calendar.current.date(byAdding: .day, value: -1, to: event.endDate) ?? event.endDate
            return "\(L10n.t("event.allday", appLang)) · \(dateFmt.string(from: event.startDate)) – \(dateFmt.string(from: end))"
        }
        return "\(timeFmt.string(from: event.startDate)) – \(timeFmt.string(from: event.endDate))"
    }

    private var canEdit: Bool {
        event.source == "local" || event.source == "caldav" || event.source == "homeassistant"
    }

    private var canDelete: Bool { canEdit }

    private var currentUserId: Int? {
        let id = UserDefaults.standard.integer(forKey: "userId")
        return id == 0 ? nil : id
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: event.effectiveColor))
                            .frame(width: 6, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.renderTitle)
                                .font(.title3.bold())
                            Text(event.calendarName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Label(timeString, systemImage: "clock")

                    if !event.location.isEmpty {
                        Label(event.location, systemImage: "mappin.and.ellipse")
                    }

                    if !event.notes.isEmpty {
                        Label(event.notes, systemImage: "text.alignleft")
                    }
                }

                Section {
                    HStack {
                        Label(L10n.t("event.calendar_section", appLang), systemImage: "calendar")
                        Spacer()
                        Text(event.calendarName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label(L10n.t("detail.source", appLang), systemImage: "server.rack")
                        Spacer()
                        Text(event.source.capitalized)
                            .foregroundStyle(.secondary)
                    }
                    if let creator = event.creator, creator.id != currentUserId {
                        HStack {
                            Label(L10n.t("detail.created_by", appLang), systemImage: "person")
                            Spacer()
                            Text(creator.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if event.isPrivate {
                        Label(L10n.t("event.private", appLang), systemImage: "lock")
                            .foregroundStyle(.secondary)
                    }
                }

                // Attachments exist on local events only; the payload carries
                // just the count, so the list is fetched when the sheet opens.
                if event.source == "local" && event.attachmentCount > 0 {
                    Section(L10n.t("event.attachments", appLang)) {
                        if loadingAttachments && attachments.isEmpty {
                            ProgressView()
                        }
                        ForEach(attachments) { att in
                            Button {
                                Task { await shareAttachment(att) }
                            } label: {
                                HStack(spacing: 10) {
                                    if let image = thumbnails[att.id] {
                                        Image(uiImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 32, height: 32)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    } else {
                                        Image(systemName: att.symbolName)
                                            .frame(width: 32)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(att.filename)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text(att.displaySize)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !store.writableCalendars.isEmpty {
                    Section {
                        Button {
                            showCopySheet = true
                        } label: {
                            Label(L10n.t("event.copy_title", appLang), systemImage: "doc.on.doc")
                        }
                    }
                }

                if canDelete {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label(L10n.t("detail.delete", appLang), systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                        .disabled(isDeleting)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.t("detail.title", appLang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.close", appLang)) {
                        Task { await onDone(nil, false) }
                    }
                }
                if canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Button(L10n.t("detail.edit", appLang)) {
                            Task { await onDone(event, false) }
                        }
                    }
                }
            }
            .alert(L10n.t("detail.delete_confirm_title", appLang), isPresented: $showDeleteConfirm) {
                Button(L10n.t("common.delete", appLang), role: .destructive) {
                    Task { await deleteEvent() }
                }
                Button(L10n.t("common.cancel", appLang), role: .cancel) {}
            } message: {
                Text("\"\(event.renderTitle)\" \(L10n.t("detail.delete_msg_suffix", appLang))")
            }
            .sheet(isPresented: $showCopySheet) {
                EventEditorSheet(
                    api: api,
                    store: store,
                    initialDate: event.startDate,
                    editingEvent: nil,
                    copyFrom: event
                ) {
                    // Copy created a new server-side event → force reload so it appears
                    await onDone(nil, true)
                }
            }
            .task(id: event.id) { await loadAttachments() }
            .sheet(item: $sharedFile) { shared in
                ActivityView(items: [shared.url])
            }
        }
    }

    private func loadAttachments() async {
        guard event.source == "local", event.attachmentCount > 0 else {
            attachments = []
            return
        }
        loadingAttachments = true
        defer { loadingAttachments = false }
        guard let loaded = try? await api.listAttachments(eventUid: event.id) else { return }
        attachments = loaded
        // Thumbnails are small server-rendered JPEGs, so decoding them here is
        // cheap and needs no image-loading dependency.
        for att in loaded where att.hasThumbnail {
            if let data = await api.attachmentThumbnail(id: att.id),
               let image = UIImage(data: data) {
                thumbnails[att.id] = image
            }
        }
    }

    /// Download to a temporary file and hand it to the share sheet, so the user
    /// can save it to Files or open it in another app.
    private func shareAttachment(_ att: EventAttachment) async {
        guard let data = try? await api.downloadAttachment(id: att.id) else { return }
        let name = att.filename.isEmpty ? "anhang" : att.filename
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return }
        sharedFile = SharedFile(url: url)
    }

    private func deleteEvent() async {
        isDeleting = true
        do {
            switch event.source {
            case "local":
                try await api.deleteLocalEvent(uid: event.id)
            case "homeassistant":
                // calendarId looks like "homeassistant-42" → numeric DB id 42
                let calId = Int(event.calendarId.replacingOccurrences(of: "homeassistant-", with: "")) ?? 0
                try await api.deleteHAEvent(calendarId: calId, uid: event.id)
            default:
                let calId = Int(event.calendarId)
                try await api.deleteCalDAVEvent(uid: event.id, url: event.url, calendarId: calId)
            }
            // Optimistically drop it from the cache so it vanishes immediately,
            // regardless of how long the source takes to propagate the delete.
            store.removeCachedEvent(id: event.id)
            await onDone(nil, false)
        } catch {
            isDeleting = false
        }
    }
}
