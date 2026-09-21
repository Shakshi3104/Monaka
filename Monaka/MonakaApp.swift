//
//  MonakaApp.swift
//  Monaka
//

import SwiftUI
import SwiftData

@main
struct MonakaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(RunReminder.storageKey) private var remindsBeforeEnd = false

    let modelContainer: ModelContainer = {
        do {
            return try SharedStore.makeModelContainer()
        } catch {
            // A missing App Group is a build misconfiguration, not a runtime
            // condition — there is nothing useful to show the user.
            fatalError("Could not open the shared store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AppRouter.shared)
                // Reminders are rebuilt from the store whenever it changes
                // or the app comes back — cheap, and never out of date.
                .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                    Task { await refreshReminders() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await refreshReminders() } }
                }
                .onChange(of: remindsBeforeEnd) { _, _ in
                    Task { await refreshReminders() }
                }
                #if DEBUG
                // §4 — `-seed-samples` fills a simulator store with the same
                // spread the previews use. Additive: it never overwrites a spot
                // that's already there.
                .task {
                    guard DebugLaunchArgument.seedSamples.isSet else { return }
                    Spot.seedSamples(into: modelContainer.mainContext)
                }
                #endif
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private func refreshReminders() async {
        let spots = (try? modelContainer.mainContext.fetch(FetchDescriptor<Spot>())) ?? []
        await RunReminder.refresh(spots, enabled: remindsBeforeEnd)
    }
}
