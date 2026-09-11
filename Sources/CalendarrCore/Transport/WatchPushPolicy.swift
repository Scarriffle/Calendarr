import Foundation

/// Identifies the appointment a complication is currently showing.
///
/// The start date is part of the identity on purpose: a moved event keeps its
/// id, and the complication is wrong until it is told.
public struct NextEventIdentity: Equatable, Sendable, Codable {
    public let id: String
    public let start: Date

    public init(id: String, start: Date) {
        self.id = id
        self.start = start
    }
}

public enum WatchPushPolicy {
    /// The first event that has not ended yet — which is what every "next
    /// appointment" complication renders, including one that is running now.
    public static func nextEventIdentity(in snapshot: CalendarrSnapshot,
                                         at now: Date) -> NextEventIdentity? {
        snapshot.events
            .filter { $0.end > now }
            .min { $0.start < $1.start }
            .map { NextEventIdentity(id: $0.id, start: $0.start) }
    }

    /// Whether this change is worth one of the day's limited complication
    /// pushes. Only a changed next appointment is — everything else reaches the
    /// watch on the next application-context delivery.
    public static func shouldPushComplicationUpdate(previous: NextEventIdentity?,
                                                    current: NextEventIdentity?) -> Bool {
        previous != current
    }
}
