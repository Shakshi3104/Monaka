//
//  RunReminder.swift
//  Monaka
//
//  A local notification some days before a run ends, for spots not yet
//  visited (Phase 3). How many days, and at what time, is set in Settings. Permission is asked for only when the user turns the
//  reminder on in Settings — never at launch — the same way location is
//  handled (§7.3). Denied, the toggle says so and nothing else changes.
//
//  The pending set is rebuilt from the store, in full, whenever the store is
//  saved or the app comes back: simpler than tracking edits, and the store is
//  small. Identifiers are `spot-end-<uuid>` so nothing else the app might
//  schedule later gets swept up.
//

import Foundation
import UserNotifications

struct RunReminder {
    static let storageKey = "remindsBeforeEnd"
    /// Days before `endDate` the reminder fires.
    static let leadDaysKey = "reminderLeadDays"
    /// Minutes after midnight, Asia/Tokyo — one `Int`, so `@AppStorage`
    /// holds it without a `Date` and its time zone to get wrong.
    static let minuteOfDayKey = "reminderMinuteOfDay"

    /// What Settings offers. A fixed handful reads faster than a stepper,
    /// and nothing past a week: by then it's the list's job, not a nudge.
    static let leadDayOptions = [1, 2, 3, 5, 7]
    nonisolated static let defaultLeadDays = 3
    /// 9:00 — after breakfast, before plans firm up.
    nonisolated static let defaultMinuteOfDay = 9 * 60
    private static let identifierPrefix = "spot-end-"
    /// iOS keeps at most 64 pending requests per app.
    private static let pendingLimit = 60

    enum Access: Equatable {
        case notDetermined
        case denied
        case authorized
    }

    static func access() async -> Access {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .denied
        }
    }

    /// Call from the Settings toggle, nowhere else.
    static func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Rebuild every reminder from `spots`. `enabled` false clears them.
    static func refresh(
        _ spots: [Spot],
        enabled: Bool,
        leadDays: Int = defaultLeadDays,
        minuteOfDay: Int = defaultMinuteOfDay,
        now: Date = .now,
        calendar: Calendar = .monaka
    ) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        guard enabled, await access() == .authorized else { return }

        let planned = spots
            .compactMap { plan(for: $0, leadDays: leadDays, minuteOfDay: minuteOfDay, now: now, calendar: calendar) }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(pendingLimit)

        for item in planned {
            try? await center.add(item.request)
        }
    }

    struct Planned {
        let fireDate: Date
        let request: UNNotificationRequest
    }

    /// `minuteOfDay`, `leadDays` before the last day, if that's still ahead.
    /// A spot ending sooner than that gets nothing — a reminder tomorrow for
    /// a run ending tomorrow is the list itself, and the Today tab has it.
    static func plan(for spot: Spot, leadDays: Int, minuteOfDay: Int, now: Date, calendar: Calendar) -> Planned? {
        guard !spot.isVisited, let end = spot.endDate else { return nil }
        let lastDay = calendar.startOfDay(for: end)
        guard let reminderDay = calendar.date(byAdding: .day, value: -leadDays, to: lastDay) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: reminderDay)
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        components.timeZone = calendar.timeZone
        guard let fireDate = calendar.date(from: components), fireDate > now else { return nil }

        let content = UNMutableNotificationContent()
        content.title = spot.title
        let ends = DateFormatter.monakaDateWithWeekday.string(from: end)
        content.body = [spot.venue?.nilIfBlank, "Ends \(ends) — \(daysLeftText(leadDays))."]
            .compactMap { $0 }
            .joined(separator: " · ")
        content.sound = .default
        content.userInfo = ["spotID": spot.id.uuidString]
        content.threadIdentifier = "run-ending"

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifierPrefix + spot.id.uuidString,
            content: content,
            trigger: trigger
        )
        return Planned(fireDate: fireDate, request: request)
    }

    // MARK: - Wording

    /// `1 day` / `3 days` / `1 week` — the Settings picker and its footer.
    static func leadText(_ days: Int) -> String {
        switch days {
        case 1: "1 day"
        case 7: "1 week"
        default: "\(days) days"
        }
    }

    private static func daysLeftText(_ days: Int) -> String {
        days == 1 ? "1 day left" : "\(days) days left"
    }

    /// `9:00`, read in Asia/Tokyo like every other time in the app (§6.1).
    static func timeText(_ minuteOfDay: Int) -> String {
        String(format: "%d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    /// The spot a tapped notification points at, if it was one of ours.
    static func spotID(in response: UNNotificationResponse) -> UUID? {
        guard response.notification.request.identifier.hasPrefix(identifierPrefix),
              let raw = response.notification.request.content.userInfo["spotID"] as? String
        else { return nil }
        return UUID(uuidString: raw)
    }
}
