//
//  AppRouter.swift
//  Monaka
//
//  Where the app should go next when something outside the view tree — a
//  tapped notification, later a widget — asks for a screen. One request at a
//  time: the tab that owns the destination picks it up and clears it.
//

import SwiftUI
import UIKit
import Observation
import UserNotifications

@Observable
final class AppRouter {
    /// A spot to open in the All tab. Set from outside, consumed by
    /// `SpotListView`.
    var pendingSpotID: UUID?

    /// One for the process: the notification delegate has no view tree to
    /// find an environment value in.
    static let shared = AppRouter()
}

/// Exists to be the notification center's delegate before the app finishes
/// launching, which a cold-start tap on a notification requires.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show a reminder even while the app is open — the list may be on
    /// screen, but the point of the reminder is the date, not the row.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let id = RunReminder.spotID(in: response) else { return }
        await MainActor.run { AppRouter.shared.pendingSpotID = id }
    }
}
