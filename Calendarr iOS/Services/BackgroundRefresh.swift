import BackgroundTasks
import Foundation
import CalendarrCore

/// Keeps the shared snapshot fresh while the app is not in the foreground.
///
/// Without this, `publishWidgetSnapshot()` only ever runs from a user action,
/// so an event created on the web or on Android does not reach the widgets — or
/// the watch — until the app is opened again. iOS decides when this actually
/// runs, based on how the user uses the app: it improves freshness, it does not
/// guarantee it.
@MainActor
enum BackgroundRefresh {
    static let taskIdentifier = "com.scarriffleservices.calendarr.ios.refresh"

    /// Minimum gap between runs we ask for. iOS treats this as the earliest
    /// acceptable time, not a promise.
    private static let interval: TimeInterval = 30 * 60

    /// Call once at launch, before the app finishes starting up.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier,
                                        using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in await handle(refresh) }
        }
    }

    /// Ask for the next run. Safe to call repeatedly; a duplicate submission
    /// replaces the pending request rather than queueing a second one.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do { try BGTaskScheduler.shared.submit(request) }
        catch {
            // Submission fails on a simulator and when the user has disabled
            // background refresh. Neither is worth interrupting anyone over.
            print("[BackgroundRefresh] submit failed: \(error.localizedDescription)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) async {
        // Reschedule first: if the work below throws or is killed, the chain
        // must not end here.
        schedule()

        let work = Task { @MainActor in await refreshSnapshot() }
        task.expirationHandler = { work.cancel() }

        let succeeded = await work.value
        task.setTaskCompleted(success: succeeded)
    }

    /// Fetch the snapshot window and republish. Returns false when there was
    /// nothing to do or the fetch failed.
    private static func refreshSnapshot() async -> Bool {
        let state = AppState()
        guard state.isConfigured, state.isLoggedIn else { return false }

        // An SSO session can lapse while the app is closed; renewing first
        // avoids spending the whole background window on a 401.
        await OIDCSessionRefresher.refreshIfNeeded(state)

        let api = CalendarrAPI(baseURL: state.serverURL, token: state.authToken)
        let store = CalendarStore()

        let calendar = Calendar(identifier: .gregorian)
        let dayStart = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .day, value: -SnapshotCoverage.daysBehind, to: dayStart),
              let to = calendar.date(byAdding: .day, value: SnapshotCoverage.daysAhead, to: dayStart)
        else { return false }

        // force: a freshly created store has an empty in-memory cache, so
        // without this the "already cached" short-circuit would skip the fetch.
        await store.loadEvents(api: api, start: from, end: to, force: true)

        return store.lastError == nil
    }
}
