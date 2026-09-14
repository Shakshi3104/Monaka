//
//  MonakaApp.swift
//  Monaka
//

import SwiftUI
import SwiftData

@main
struct MonakaApp: App {
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
                #if DEBUG
                // §4 — `-seed-samples` fills a simulator store with the same
                // spread the previews use. Additive: it never overwrites a spot
                // that's already there.
                .task {
                    guard ProcessInfo.processInfo.arguments.contains("-seed-samples") else { return }
                    Spot.seedSamples(into: modelContainer.mainContext)
                }
                #endif
        }
        .modelContainer(modelContainer)
    }
}
