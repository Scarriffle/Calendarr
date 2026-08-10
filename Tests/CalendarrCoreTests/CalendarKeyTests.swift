import Testing
@testable import CalendarrCore

/// The server reports `calendar_id` two different ways, and normalising them
/// inconsistently is what made per-calendar filtering silently do nothing for
/// some sources. These pin the rule down.
struct CalendarKeyTests {

    @Test("CalDAV ids arrive bare and are used as-is")
    func bareNumericId() {
        #expect(CalendarKey.make(source: "caldav", calendarId: "12") == "caldav:12")
    }

    @Test("Prefixed ids from the other sources get the prefix stripped")
    func strippedPrefix() {
        #expect(CalendarKey.make(source: "local", calendarId: "local-3") == "local:3")
        #expect(CalendarKey.make(source: "google", calendarId: "google-5") == "google:5")
        #expect(CalendarKey.make(source: "ical", calendarId: "ical-7") == "ical:7")
        #expect(CalendarKey.make(source: "homeassistant",
                                 calendarId: "homeassistant-9") == "homeassistant:9")
    }

    @Test("Both spellings of the same calendar produce the same key")
    func bothFormsAgree() {
        #expect(CalendarKey.make(source: "local", calendarId: "local-3")
             == CalendarKey.make(source: "local", calendarId: "3"))
    }

    @Test("Only a leading prefix is stripped, and only once")
    func stripsOnlyLeadingPrefix() {
        // A prefix appearing later in the id must survive untouched.
        #expect(CalendarKey.make(source: "local", calendarId: "3-local") == "local:3-local")
        // Two prefixes: only the first goes.
        #expect(CalendarKey.make(source: "local", calendarId: "local-local-3") == "local:local-3")
    }

    @Test("parse round-trips make")
    func roundTrip() {
        let key = CalendarKey.make(source: "local", calendarId: "local-42")
        let parsed = CalendarKey.parse(key)
        #expect(parsed?.source == "local")
        #expect(parsed?.id == 42)
    }

    @Test("parse rejects what it cannot represent")
    func rejectsMalformed() {
        #expect(CalendarKey.parse("nocolon") == nil)
        #expect(CalendarKey.parse("local:abc") == nil)   // non-numeric id
        #expect(CalendarKey.parse("local:") == nil)
    }
}
