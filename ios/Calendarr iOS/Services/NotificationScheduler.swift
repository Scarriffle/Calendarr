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
            let now = Date()
            var pending: [(fire: Date, event: CalEvent)] = []
            for ev in events {
                // Skip calendars the user muted for reminders.
                if !disabledCalendarKeys.isEmpty {
                    let key = CalendarStore.calendarKey(source: ev.source, calendarId: ev.calendarId)
                    if disabledCalendarKeys.contains(key) { continue }
                }
                let offsets = ev.reminders.isEmpty
                    ? (defaultMin >= 0 ? [defaultMin] : [])
                    : ev.reminders
                for m in offsets {
                    let fire = ev.startDate.addingTimeInterval(-Double(m) * 60)
                    if fire > now { pending.append((fire, ev)) }
                }
            }
            pending.sort { $0.fire < $1.fire }
            let limited = pending.prefix(60)  // stay safely under the 64 system cap

            center.removeAllPendingNotificationRequests()
            for item in limited {
                let content = UNMutableNotificationContent()
                content.title = item.event.title
                let minutes = Int(item.event.startDate.timeIntervalSince(item.fire) / 60)
                let rel     = relativeText(minutes)
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

    private static func relativeText(_ minutes: Int) -> String {
        if minutes < 60    { return "in \(minutes) Min." }
        if minutes == 60   { return "in 1 Std." }
        if minutes < 1440  { return "in \(minutes / 60) Std." }
        if minutes == 1440 { return "morgen" }
        return "in \(minutes / 1440) Tagen"
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
