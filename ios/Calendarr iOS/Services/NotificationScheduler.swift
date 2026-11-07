import Foundation
import UserNotifications

extension Notification.Name {
    /// Posted when the default-reminder setting changes, so the calendar host
    /// can recompute the scheduled local notifications from its cached events.
    static let rescheduleReminders = Notification.Name("rescheduleReminders")
}

/// Schedules local OS notifications for upcoming events. Per-event reminders
/// (local events) take precedence; otherwise the user's default reminder applies
/// to every event (incl. external). Re-run whenever events or the default change.
enum NotificationScheduler {

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Recompute and (re)schedule notifications from the given events. The iOS
    /// pending-notification cap is 64, so only the soonest are scheduled.
    /// `disabledCalendarKeys` ("source:id") are calendars with reminders turned
    /// off — their events never generate notifications.
    static func reschedule(events: [CalEvent], disabledCalendarKeys: Set<String> = []) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }

            let defaultMin = (UserDefaults.standard.object(forKey: "defaultReminderMinutes") as? Int) ?? -1
            let allDayDays = (UserDefaults.standard.object(forKey: "allDayReminderDays") as? Int) ?? -1
            let allDayTime = UserDefaults.standard.string(forKey: "allDayReminderTime") ?? "09:00"
            let now = Date()
            var pending: [(fire: Date, event: CalEvent)] = []
            for ev in events {
                // Skip calendars the user muted for reminders.
                if !disabledCalendarKeys.isEmpty {
                    let key = CalendarStore.calendarKey(source: ev.source, calendarId: ev.calendarId)
                    if disabledCalendarKeys.contains(key) { continue }
                }
                // Device calendars are already served by the system Calendar
                // app, so applying our default here notifies twice for one
                // event. They stay silent unless the event carries its own
                // reminder; the per-calendar toggle can still switch them on.
                let allowsDefault = (ev.isAllDay ? allDayDays >= 0 : defaultMin >= 0)
                    && ev.source != "device"
                let fallback = ev.isAllDay ? allDayDays * 1440 : defaultMin
                let offsets = ev.reminders.isEmpty
                    ? (allowsDefault ? [fallback] : [])
                    : ev.reminders
                for m in offsets {
                    guard let fire = fireDate(for: ev, offsetMinutes: m, allDayTime: allDayTime)
                    else { continue }
                    if fire > now { pending.append((fire, ev)) }
                }
            }
            pending.sort { $0.fire < $1.fire }
            let limited = pending.prefix(60)  // stay safely under the 64 system cap

            center.removeAllPendingNotificationRequests()
            for item in limited {
                let content = UNMutableNotificationContent()
                content.title = item.event.title
                let rel = item.event.isAllDay
                    ? allDayRelativeText(from: item.fire, to: item.event.startDate)
                    : relativeText(Int(item.event.startDate.timeIntervalSince(item.fire) / 60))
                let detail  = bodyText(item.event)
                content.body = detail.isEmpty ? rel : "\(rel) · \(detail)"
                content.sound = .default
                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: item.fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
            }
        }
    }

    /// When a reminder should fire.
    ///
    /// An all-day event starts at local midnight, so a minute offset puts the
    /// reminder in the middle of the night — 30 minutes before becomes 23:30.
    /// For those the offset is read as whole days instead, and the time of day
    /// comes from the setting. Birthday calendars inherit that for free: the
    /// offsets the server injects for them are always multiples of 1440.
    private static func fireDate(for ev: CalEvent, offsetMinutes m: Int,
                                 allDayTime: String) -> Date? {
        guard ev.isAllDay else {
            return ev.startDate.addingTimeInterval(-Double(m) * 60)
        }
        let cal = Calendar.current
        let days = Int((Double(m) / 1440.0).rounded())
        guard let day = cal.date(byAdding: .day, value: -days,
                                 to: cal.startOfDay(for: ev.startDate)) else { return nil }
        let parts = allDayTime.split(separator: ":")
        let hour = parts.count == 2 ? (Int(parts[0]) ?? 9) : 9
        let minute = parts.count == 2 ? (Int(parts[1]) ?? 0) : 0
        return cal.date(bySettingHour: min(max(hour, 0), 23),
                        minute: min(max(minute, 0), 59), second: 0, of: day)
    }

    private static func relativeText(_ minutes: Int) -> String {
        if minutes < 60    { return "in \(minutes) Min." }
        if minutes == 60   { return "in 1 Std." }
        if minutes < 1440  { return "in \(minutes / 60) Std." }
        if minutes == 1440 { return "morgen" }
        return "in \(minutes / 1440) Tagen"
    }

    /// "heute" / "morgen" / "in N Tagen" — counted in calendar days, because a
    /// reminder at 09:00 for a midnight start is 15 hours away, not a day.
    private static func allDayRelativeText(from fire: Date, to start: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: fire),
                                      to: cal.startOfDay(for: start)).day ?? 0
        switch days {
        case ..<1: return "heute"
        case 1:    return "morgen"
        default:   return "in \(days) Tagen"
        }
    }

    private static func bodyText(_ ev: CalEvent) -> String {
        var parts: [String] = []
        if !ev.isAllDay {
            let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
            parts.append(f.string(from: ev.startDate))
        }
        if !ev.location.isEmpty { parts.append(ev.location) }
        return parts.joined(separator: " · ")
    }
}
