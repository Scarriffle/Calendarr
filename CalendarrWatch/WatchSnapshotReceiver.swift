import Foundation
import WatchConnectivity
import WidgetKit
@_spi(Writer) import CalendarrCore

/// Takes what the phone sends and writes it into this watch's own App Group
/// container, using the same `SnapshotStore` the phone writes with. One wire
/// format, one reader, no drift.
///
/// Only the app runs a `WCSession`; a widget extension cannot. The complications
/// always read what this wrote.
@MainActor
final class WatchSnapshotReceiver: NSObject {
    static let shared = WatchSnapshotReceiver()

    private let store = SnapshotStore()
    private let sessions = SharedSessionStore()

    /// Shown in the agenda footer, because a silent failure here looks exactly
    /// like an empty calendar.
    private(set) var lastError: String?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Ask the phone for the current state. Covers "the app is open in front of
    /// me and looks stale"; the other two paths are push-driven.
    func requestRefresh() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }

        session.sendMessage(["request": "snapshot"],
                            replyHandler: { reply in
                                Task { @MainActor in self.apply(reply) }
                            },
                            errorHandler: { error in
                                Task { @MainActor in self.lastError = error.localizedDescription }
                            })
    }

    func apply(_ dict: [String: Any]) {
        guard !dict.isEmpty else { return }
        do {
            let payload = try WatchTransportPayload.decode(dict)
            // This write posts SnapshotChangeNotifier, which is what the read
            // model listens for — so the UI updates without being told twice.
            try store.write(payload.snapshot)
            try store.writeCalendars(payload.calendars)
            if let session = payload.session { try sessions.write(session) }
            WidgetCenter.shared.reloadAllTimelines()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

extension WatchSnapshotReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        if let error {
            Task { @MainActor in self.lastError = error.localizedDescription }
        }
    }

    /// The main path: latest state only, delivered when this app launches or wakes.
    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    /// The complication push, which is the only path that wakes this app while
    /// it is not running.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.apply(userInfo) }
    }
}
