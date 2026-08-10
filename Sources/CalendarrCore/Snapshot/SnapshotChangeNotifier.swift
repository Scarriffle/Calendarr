import Foundation

/// Cross-process "the snapshot changed" broadcast.
///
/// Two sandboxed apps cannot see each other's `NotificationCenter`, and neither
/// can poll the container cheaply. Darwin notifications are the one signal that
/// crosses the process boundary without an extra entitlement, a running
/// connection, or a shared framework.
///
/// The payload is always empty — Darwin notifications carry no data. The signal
/// means only "read again". If it is ever missed, a consumer that also reloads
/// on window activation degrades to a slightly stale view rather than a wrong one.
public enum SnapshotChangeNotifier {
    public static let name = "com.scarriffleservices.calendarr.snapshot-changed"

    /// Announce that the snapshot was rewritten. Called by `SnapshotStore`.
    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true)
    }

    /// Start listening. The handler runs on an arbitrary thread, so hop to
    /// whatever actor your UI needs before touching state.
    ///
    /// Returns a token you must keep alive; deinit removes the observer.
    public static func observe(_ handler: @escaping @Sendable () -> Void) -> ObservationToken {
        ObservationToken(handler: handler)
    }

    public final class ObservationToken: @unchecked Sendable {
        private let handler: @Sendable () -> Void

        fileprivate init(handler: @escaping @Sendable () -> Void) {
            self.handler = handler
            // Darwin notifications hand back no context pointer we can rely on
            // across process boundaries, so route through an unretained pointer
            // to this token and look it up in the callback.
            let observer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                observer,
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    Unmanaged<ObservationToken>.fromOpaque(observer)
                        .takeUnretainedValue().handler()
                },
                SnapshotChangeNotifier.name as CFString,
                nil,
                .deliverImmediately)
        }

        deinit {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                CFNotificationName(SnapshotChangeNotifier.name as CFString),
                nil)
        }
    }
}
