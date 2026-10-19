import Foundation

/// Stable identifier for one calendar, used to tie a snapshot event back to the
/// calendar it came from.
///
/// This exists because the server reports `calendar_id` inconsistently: a raw
/// numeric for CalDAV sources, but `"<source>-<id>"` for local, iCal, Google and
/// Home Assistant (e.g. `"local-3"`). Any consumer that filters by calendar has
/// to normalise the two forms identically, or filtering silently does nothing
/// for the prefixed sources — which is exactly the bug this rule was written to
/// fix. Keeping the rule in one shared place is why it lives here rather than
/// being reimplemented per app.
public enum CalendarKey {
    /// Build a key, stripping a redundant `"<source>-"` prefix from the id.
    public static func make(source: String, calendarId: String) -> String {
        var id = calendarId
        let prefix = "\(source)-"
        if id.hasPrefix(prefix) { id = String(id.dropFirst(prefix.count)) }
        return "\(source):\(id)"
    }

    /// Split a key back into its source and numeric id.
    /// Returns nil for malformed keys or non-numeric ids.
    public static func parse(_ key: String) -> (source: String, id: Int)? {
        guard let colon = key.firstIndex(of: ":") else { return nil }
        let source = String(key[..<colon])
        guard let id = Int(key[key.index(after: colon)...]) else { return nil }
        return (source, id)
    }
}
