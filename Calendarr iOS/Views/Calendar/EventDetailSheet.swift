import SwiftUI

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
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showCopySheet = false

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
                return "Ganztägig · \(dateFmt.string(from: event.startDate))"
            }
            let end = Calendar.current.date(byAdding: .day, value: -1, to: event.endDate) ?? event.endDate
            return "Ganztägig · \(dateFmt.string(from: event.startDate)) – \(dateFmt.string(from: end))"
        }
        return "\(timeFmt.string(from: event.startDate)) – \(timeFmt.string(from: event.endDate))"
    }

    private var canEdit: Bool {
        event.source == "local" || event.source == "caldav" || event.source == "homeassistant"
    }

    private var canDelete: Bool { canEdit }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: event.effectiveColor))
                            .frame(width: 6, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
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
                        Label("Kalender", systemImage: "calendar")
                        Spacer()
                        Text(event.calendarName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Quelle", systemImage: "server.rack")
                        Spacer()
                        Text(event.source.capitalized)
                            .foregroundStyle(.secondary)
                    }
                }

                if !store.writableCalendars.isEmpty {
                    Section {
                        Button {
                            showCopySheet = true
                        } label: {
                            Label("Termin kopieren", systemImage: "doc.on.doc")
                        }
                    }
                }

                if canDelete {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Termin löschen", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                        .disabled(isDeleting)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Termin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") {
                        Task { await onDone(nil, false) }
                    }
                }
                if canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Bearbeiten") {
                            Task { await onDone(event, false) }
                        }
                    }
                }
            }
            .alert("Termin löschen?", isPresented: $showDeleteConfirm) {
                Button("Löschen", role: .destructive) {
                    Task { await deleteEvent() }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("\"\(event.title)\" wird dauerhaft gelöscht.")
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
        }
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
