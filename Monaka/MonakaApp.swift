//
//  MonakaApp.swift
//  Monaka
//

import SwiftUI
import SwiftData

@main
struct MonakaApp: App {
    // Phase 2 replaces this with the App Group container in SharedStore.
    let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Spot.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
