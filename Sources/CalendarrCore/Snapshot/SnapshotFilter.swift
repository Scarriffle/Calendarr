import Foundation

extension CalendarrSnapshot {
    /// Keep only the listed calendars. An empty set means "every calendar",
    /// which is what an unconfigured widget or complication asks for.
    ///
    /// Filtering narrows the events but deliberately not the window: the
    /// snapshot still speaks for the same range, it just has fewer calendars
    /// in it.
    public func filtered(toCalendarKeys keys: Set<String>) -> CalendarrSnapshot {
        guard !keys.isEmpty else { return self }
        return replacingEvents(events.filter { keys.contains($0.calendarKey) })
    }

    /// Remove the listed calendars, keeping everything else. An empty set is a
    /// no-op.
    public func filtered(excludingCalendarKeys keys: Set<String>) -> CalendarrSnapshot {
        guard !keys.isEmpty else { return self }
        return replacingEvents(events.filter { !keys.contains($0.calendarKey) })
    }

    private func replacingEvents(_ events: [SnapshotEvent]) -> CalendarrSnapshot {
        CalendarrSnapshot(writtenAt: writtenAt,
                          coverageStart: coverageStart,
                          coverageEnd: coverageEnd,
                          isLoggedIn: isLoggedIn,
                          writerVersion: writerVersion,
                          events: events,
                          theme: theme,
                          language: language)
    }
}
