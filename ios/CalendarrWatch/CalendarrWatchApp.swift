import SwiftUI

@main
struct CalendarrWatchApp: App {
    @State private var model = WatchSnapshotModel()

    init() {
        // The session has to be live before the first payload arrives, and a
        // complication push can wake this app with no UI on screen at all.
        WatchSnapshotReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchAgendaView()
                .environment(model)
        }
    }
}
