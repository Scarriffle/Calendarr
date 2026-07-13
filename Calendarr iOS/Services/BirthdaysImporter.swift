import Foundation
import Contacts
import UIKit

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

/// Reads birthdays from the system Contacts and mirrors them into the user's
/// single birthday calendar on the backend, so they show on every client.
///
/// The sync is a **mirror**, scoped to THIS device: it reconciles rows whose
/// `external_uid` starts with `contact:<deviceId>:` (adds new, updates changed,
/// deletes removed) and never touches other devices' rows or manually added
/// birthdays. Age suffix, cake icon and "notify N days before" are done
/// server-side; this only uploads name + date + birth year, and reports the
/// device so the web can list "birthdays come from these devices".
enum BirthdaysImporter {

    // MARK: – Persisted state

    enum Key {
        static let enabled = "birthdaysSyncEnabled"   // Bool
        static let deviceId = "birthdaysDeviceId"     // stable per-install UUID
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: Key.enabled) }
    static func setEnabled(_ on: Bool) { UserDefaults.standard.set(on, forKey: Key.enabled) }

    static var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: Key.deviceId) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: Key.deviceId)
        return id
    }

    @MainActor static var deviceName: String {
        let n = UIDevice.current.name
        return n.isEmpty ? "iPhone" : n
    }

    private static var appLang: String {
        UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
    }

    // MARK: – Contacts access

    static var isAuthorized: Bool {
        let s = CNContactStore.authorizationStatus(for: .contacts)
        if s == .authorized { return true }
        if #available(iOS 18.0, *), s == .limited { return true }
        return false
    }

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
        let contactId: String
        let name: String
        let month: Int
        let day: Int
        let year: Int?
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
                contactId: contact.identifier, name: name, month: m, day: d, year: year
            ))
        }
        return out
    }

    // MARK: – The single birthday calendar

    /// The user's birthday calendar, creating the single "Geburtstage" calendar
    /// if none exists yet.
    static func ensureBirthdayCalendar(api: CalendarrAPI) async -> LocalCalendar? {
        let cals = (try? await api.getLocalCalendars()) ?? []
        if let existing = cals.first(where: { $0.isBirthday && $0.owned }) { return existing }
        let name = L10n.t("birthday.calendar_name", appLang)
        return try? await api.addLocalCalendar(name: name, color: "#E0407F", isBirthday: true)
    }

    static func birthdayCalendar(api: CalendarrAPI) async -> LocalCalendar? {
        let cals = (try? await api.getLocalCalendars()) ?? []
        return cals.first(where: { $0.isBirthday && $0.owned })
    }

    // MARK: – Sync

    /// Mirror the address book into the birthday calendar (creating it if
    /// needed). No-op unless enabled and Contacts access is granted.
    static func sync(api: CalendarrAPI) async {
        guard isEnabled else { return }
        guard await requestAccess() else { return }
        guard let contacts = try? readContactBirthdays() else { return }
        guard let cal = await ensureBirthdayCalendar(api: api) else { return }
        guard let existing = try? await api.getBirthdayEntries(calendarId: cal.id) else { return }

        // Only reconcile THIS device's contact rows; leave other devices'
        // rows and manual entries untouched.
        let prefix = "contact:\(deviceId):"
        var byExt: [String: BirthdayEntry] = [:]
        for e in existing {
            if let ext = e.externalUid, ext.hasPrefix(prefix) { byExt[ext] = e }
        }

        var seen = Set<String>()
        for c in contacts {
            let ext = prefix + c.contactId
            seen.insert(ext)
            let (start, end) = allDayRange(month: c.month, day: c.day, year: c.year)
            if let match = byExt[ext] {
                let changed = match.title != c.name || match.month != c.month
                    || match.day != c.day || match.birthYear != c.year
                if changed {
                    try? await api.updateLocalEvent(
                        uid: match.uid, title: c.name, start: start, end: end,
                        isAllDay: true, location: "", description: "", color: nil,
                        rrule: "FREQ=YEARLY", externalUid: ext, birthYear: c.year ?? -1
                    )
                }
            } else {
                _ = try? await api.createLocalEvent(
                    calendarId: cal.id, title: c.name, start: start, end: end,
                    isAllDay: true, location: "", description: "", color: nil,
                    rrule: "FREQ=YEARLY", externalUid: ext, birthYear: c.year
                )
            }
        }
        for (ext, entry) in byExt where !seen.contains(ext) {
            try? await api.deleteLocalEvent(uid: entry.uid)
        }

        // Report this device so the web can list where birthdays come from.
        let name = await deviceName
        try? await api.reportBirthdaySync(deviceId: deviceId, deviceName: name, count: contacts.count)
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
