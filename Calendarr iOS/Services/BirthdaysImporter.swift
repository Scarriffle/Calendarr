import Foundation
import Contacts

/// One stored birthday row as returned by GET /api/local/calendars/{id}/birthdays.
/// Contact-sourced rows carry an `externalUid`; manually added ones have `nil`.
struct BirthdayEntry: Codable, Identifiable {
    let uid: String
    let externalUid: String?
    let title: String
    let month: Int?
    let day: Int?
    let birthYear: Int?
    var id: String { uid }

    enum CodingKeys: String, CodingKey {
        case uid, title, month, day
        case externalUid = "external_uid"
        case birthYear = "birth_year"
    }
}

/// Reads birthdays from the system Contacts and mirrors them into a chosen
/// birthday `LocalCalendar` on the backend, so they show on every client.
///
/// The sync is a **mirror**: it reconciles contact-sourced rows by
/// `external_uid` (adds new, updates changed, deletes removed) and never touches
/// manually added birthdays (which have no `external_uid`). The heavy lifting —
/// age suffix, cake icon, "notify N days before" reminder — is done server-side;
/// this only uploads name + date + birth year.
enum BirthdaysImporter {

    // MARK: – Persisted binding (which calendar receives Contacts birthdays)

    enum Key {
        static let enabled = "birthdaysSyncEnabled"        // Bool
        static let calendarId = "birthdaysSyncCalendarId"  // Int (0 = none)
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: Key.enabled) }
    static var targetCalendarId: Int? {
        let v = UserDefaults.standard.object(forKey: Key.calendarId) as? Int ?? 0
        return v > 0 ? v : nil
    }
    static func setEnabled(_ on: Bool) { UserDefaults.standard.set(on, forKey: Key.enabled) }
    static func setTargetCalendarId(_ id: Int?) {
        UserDefaults.standard.set(id ?? 0, forKey: Key.calendarId)
    }

    // MARK: – Contacts access

    static var isAuthorized: Bool {
        let s = CNContactStore.authorizationStatus(for: .contacts)
        if s == .authorized { return true }
        if #available(iOS 18.0, *), s == .limited { return true }
        return false
    }

    /// Request Contacts access once. Returns true if usable for enumeration.
    @discardableResult
    static func requestAccess() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { return true }
        if #available(iOS 18.0, *), status == .limited { return true }
        guard status == .notDetermined else { return false }
        return await withCheckedContinuation { cont in
            CNContactStore().requestAccess(for: .contacts) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    // MARK: – Reading contact birthdays

    struct ContactBirthday {
        let externalUid: String   // "contact:<identifier>"
        let name: String
        let month: Int
        let day: Int
        let year: Int?            // nil = year unknown
    }

    static func readContactBirthdays() throws -> [ContactBirthday] {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
        ]
        let req = CNContactFetchRequest(keysToFetch: keys)
        var out: [ContactBirthday] = []
        try store.enumerateContacts(with: req) { contact, _ in
            guard let bday = contact.birthday, let m = bday.month, let d = bday.day else { return }
            var name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            if name.isEmpty {
                name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }.joined(separator: " ")
            }
            if name.isEmpty { name = contact.organizationName }
            guard !name.isEmpty else { return }
            let year = bday.year.flatMap { $0 > 0 ? $0 : nil }
            out.append(ContactBirthday(
                externalUid: "contact:\(contact.identifier)",
                name: name, month: m, day: d, year: year
            ))
        }
        return out
    }

    // MARK: – Sync

    /// Mirror the address book into the bound birthday calendar. No-op unless the
    /// sync is enabled, a target calendar is set, and access is granted.
    static func sync(api: CalendarrAPI) async {
        guard isEnabled, let calId = targetCalendarId else { return }
        guard await requestAccess() else { return }
        guard let contacts = try? readContactBirthdays() else { return }
        guard let existing = try? await api.getBirthdayEntries(calendarId: calId) else { return }

        // Only reconcile contact-sourced rows; leave manual entries untouched.
        var byExt: [String: BirthdayEntry] = [:]
        for e in existing { if let ext = e.externalUid { byExt[ext] = e } }

        var seen = Set<String>()
        for c in contacts {
            seen.insert(c.externalUid)
            let (start, end) = allDayRange(month: c.month, day: c.day, year: c.year)
            if let match = byExt[c.externalUid] {
                let changed = match.title != c.name || match.month != c.month
                    || match.day != c.day || match.birthYear != c.year
                if changed {
                    try? await api.updateLocalEvent(
                        uid: match.uid, title: c.name, start: start, end: end,
                        isAllDay: true, location: "", description: "", color: nil,
                        rrule: "FREQ=YEARLY", externalUid: c.externalUid,
                        birthYear: c.year ?? -1  // -1 clears birth_year server-side
                    )
                }
            } else {
                _ = try? await api.createLocalEvent(
                    calendarId: calId, title: c.name, start: start, end: end,
                    isAllDay: true, location: "", description: "", color: nil,
                    rrule: "FREQ=YEARLY", externalUid: c.externalUid, birthYear: c.year
                )
            }
        }
        // Remove contact-sourced rows whose contact no longer has a birthday.
        for (ext, entry) in byExt where !seen.contains(ext) {
            try? await api.deleteLocalEvent(uid: entry.uid)
        }
    }

    /// All-day [start, end) for a birthday. Anchor year = birth year when known,
    /// else 1970 so FREQ=YEARLY expands across any queried range. Built at local
    /// noon so day-only formatting can't roll to an adjacent day.
    private static func allDayRange(month: Int, day: Int, year: Int?) -> (Date, Date) {
        var comp = DateComponents()
        comp.year = year ?? 1970
        comp.month = month
        comp.day = day
        comp.hour = 12
        let cal = Calendar.current
        let start = cal.date(from: comp) ?? Date()
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }
}
