import Foundation
import WatchConnectivity
import CalendarrCore

/// Feeds the watch. App Groups are per-device, so the watch cannot read the
/// file this app just wrote — it has to be handed the data.
///
/// Three delivery paths, because each one alone leaves a gap:
///
/// 1. `updateApplicationContext` carries only the latest state and has no queue
///    to overflow. It is delivered when the watch app next launches or wakes.
/// 2. `transferCurrentComplicationUserInfo` is the only path that wakes the
///    watch app while it is not running. Its daily budget is small, so it is
///    spent only when the *next* appointment changed.
/// 3. A reply to `sendMessage` covers the watch app asking while it is open.
@MainActor
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

    private let sessions = SharedSessionStore()
    private static let lastIdentityKey = "watchLastPushedNextEvent"
    private static let pushTimesKey = "watchComplicationPushTimes"
    /// The system budget is roughly 50 a day; this keeps a burst of edits from
    /// spending it in an hour.
    private static let maxPushesPerHour = 4

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// Call once at launch.
    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Publish the current calendar to the watch.
    func push(snapshot: CalendarrSnapshot, calendars: [SnapshotCalendar]) {
        guard let session, session.activationState == .activated else { return }

        let trimmed = snapshot.trimmedForWatch()
        let payload = WatchTransportPayload(snapshot: trimmed,
                                            calendars: calendars,
                                            session: sessions.read())
        guard let dict = try? payload.encoded() else { return }

        try? session.updateApplicationContext(dict)

        guard session.isComplicationEnabled else { return }
        let current = WatchPushPolicy.nextEventIdentity(in: trimmed, at: Date())
        guard WatchPushPolicy.shouldPushComplicationUpdate(previous: loadLastIdentity(),
                                                          current: current),
              consumePushBudget()
        else { return }

        session.transferCurrentComplicationUserInfo(dict)
        storeLastIdentity(current)
    }

    /// Tell the watch the user signed out, so it stops showing their calendar.
    /// The watch keeps its own copy of the snapshot, so clearing ours is not
    /// enough.
    func pushSignedOut() {
        guard let session, session.activationState == .activated else { return }

        let now = Date()
        let empty = CalendarrSnapshot(
            writtenAt: now, coverageStart: now, coverageEnd: now,
            isLoggedIn: false, writerVersion: "signout", events: [],
            theme: SnapshotTheme(today: "#4285f4", text: "#FFFFFF", background: "#000000",
                                 line: "#3A3A52", primary: "#4285f4", accent: "#ea4335"),
            language: "system")
        let payload = WatchTransportPayload(snapshot: empty, calendars: [], session: sessions.read())
        guard let dict = try? payload.encoded() else { return }

        try? session.updateApplicationContext(dict)
        if session.isComplicationEnabled, consumePushBudget() {
            session.transferCurrentComplicationUserInfo(dict)
        }
        storeLastIdentity(nil)
    }

    /// The payload for a watch that asked directly. Built from the file we
    /// already wrote, so an on-demand pull cannot disagree with a push.
    fileprivate func currentPayloadDictionary() -> [String: Any]? {
        let store = SnapshotStore()
        guard case .ok(let snapshot) = store.read() else { return nil }
        let payload = WatchTransportPayload(snapshot: snapshot.trimmedForWatch(),
                                            calendars: store.readCalendars(),
                                            session: sessions.read())
        return try? payload.encoded()
    }

    // MARK: – Push budget

    private func consumePushBudget() -> Bool {
        let cutoff = Date().addingTimeInterval(-3600)
        var times = (UserDefaults.standard.array(forKey: Self.pushTimesKey) as? [Double] ?? [])
            .map { Date(timeIntervalSince1970: $0) }
            .filter { $0 > cutoff }

        guard times.count < Self.maxPushesPerHour else {
            UserDefaults.standard.set(times.map(\.timeIntervalSince1970), forKey: Self.pushTimesKey)
            return false
        }
        times.append(Date())
        UserDefaults.standard.set(times.map(\.timeIntervalSince1970), forKey: Self.pushTimesKey)
        return true
    }

    // MARK: – Last pushed identity

    private func loadLastIdentity() -> NextEventIdentity? {
        guard let data = UserDefaults.standard.data(forKey: Self.lastIdentityKey) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NextEventIdentity.self, from: data)
    }

    private func storeLastIdentity(_ identity: NextEventIdentity?) {
        guard let identity else {
            UserDefaults.standard.removeObject(forKey: Self.lastIdentityKey)
            return
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try? encoder.encode(identity), forKey: Self.lastIdentityKey)
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        if let error {
            print("[WatchSync] activation failed: \(error.localizedDescription)")
        }
    }

    /// The watch asking for the current state, which is what covers "it is open
    /// in front of me and looks stale".
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            replyHandler(self.currentPayloadDictionary() ?? [:])
        }
    }

    // Required on iOS: the session is torn down and re-activated when the user
    // switches to a different paired watch.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
