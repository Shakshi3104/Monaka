//
//  RunReminder.swift
//  Monaka
//
//  A local notification three days before a run ends, for spots not yet
//  visited (Phase 3). Permission is asked for only when the user turns the
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
    /// Days before `endDate` the reminder fires.
    static let leadDays = 3
    /// 9:00, Asia/Tokyo — after breakfast, before plans firm up.
    static let hour = 9

    static let storageKey = "remindsBeforeEnd"
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
    static func refresh(_ spots: [Spot], enabled: Bool, now: Date = .now, calendar: Calendar = .monaka) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        guard enabled, await access() == .authorized else { return }

        let planned = spots
            .compactMap { plan(for: $0, now: now, calendar: calendar) }
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

    /// 9:00 three days before the last day, if that's still ahead. A spot
    /// ending sooner than that gets nothing — a reminder at 9:00 tomorrow for
    /// a run ending tomorrow is the list itself, and the Today tab has it.
    static func plan(for spot: Spot, now: Date, calendar: Calendar) -> Planned? {
        guard !spot.isVisited, let end = spot.endDate else { return nil }
        let lastDay = calendar.startOfDay(for: end)
        guard let reminderDay = calendar.date(byAdding: .day, value: -leadDays, to: lastDay) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: reminderDay)
        components.hour = hour
        components.timeZone = calendar.timeZone
        guard let fireDate = calendar.date(from: components), fireDate > now else { return nil }

        let content = UNMutableNotificationContent()
        content.title = spot.title
        let ends = DateFormatter.monakaDateWithWeekday.string(from: end)
        content.body = [spot.venue?.nilIfBlank, "Ends \(ends) — \(leadDays) days left."]
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

    /// The spot a tapped notification points at, if it was one of ours.
    static func spotID(in response: UNNotificationResponse) -> UUID? {
        guard response.notification.request.identifier.hasPrefix(identifierPrefix),
              let raw = response.notification.request.content.userInfo["spotID"] as? String
        else { return nil }
        return UUID(uuidString: raw)
    }
}
