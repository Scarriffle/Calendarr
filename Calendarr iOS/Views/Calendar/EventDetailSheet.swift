import SwiftUI

struct EventDetailSheet: View {
    let event: CalEvent
    let api: CalendarrAPI
    let store: CalendarStore
    let onDone: (CalEvent?) async -> Void

    @Environment(\.dismiss) var dismiss
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

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
        event.source == "local" || event.source == "caldav"
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

                if canEdit {
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
                        Task { await onDone(nil) }
                    }
                }
                if canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Bearbeiten") {
                            Task { await onDone(event) }
                        }
                    }
                }
            }
            .confirmationDialog("Termin löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    Task { await deleteEvent() }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("\"\(event.title)\" wird dauerhaft gelöscht.")
            }
        }
    }

    private func deleteEvent() async {
        isDeleting = true
        do {
            if event.source == "local" {
                try await api.deleteLocalEvent(uid: event.id)
            } else {
                let calId = Int(event.calendarId)
                try await api.deleteCalDAVEvent(uid: event.id, url: event.url, calendarId: calId)
            }
            await onDone(nil)
        } catch {
            isDeleting = false
        }
    }
}
