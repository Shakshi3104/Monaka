//
//  SettingsView.swift
//  Monaka
//
//  A sheet off the gear in the All tab (§6.1).
//

import SwiftUI
import SwiftData

/// Every screen inside the Settings sheet, addressed by value so a launch
/// argument can open one directly (§4) — and so a widget or notification can
/// later do the same without reaching into view state.
enum SettingsRoute: Hashable {
    case tags
    case newTag
    case renameTag(String)
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    /// `Ended` is the "missed it" bucket — hideable (§7.2). `Visited` is the
    /// "been there" bucket, and once the list is long it is the same kind of
    /// noise: neither is somewhere you can still go.
    @AppStorage("hidesEndedSection") private var hidesEndedSection = false
    @AppStorage("hidesVisitedSection") private var hidesVisitedSection = false
    @AppStorage("sortsByDistance") private var sortsByDistance = false

    let locationProvider: LocationProvider

    @State private var path: [SettingsRoute] = {
        #if DEBUG
        if DebugLaunchArgument.newTagScreen.isSet || DebugLaunchArgument.iconPicker.isSet {
            return [.tags, .newTag]
        }
        if DebugLaunchArgument.tagsScreen.isSet { return [.tags] }
        #endif
        return []
    }()

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    NavigationLink(value: SettingsRoute.tags) {
                        Label("Tags", systemImage: "tag")
                    }
                }

                Section {
                    Toggle("Hide Ended Spots", isOn: $hidesEndedSection)
                    Toggle("Hide Visited Spots", isOn: $hidesVisitedSection)
                } header: {
                    Text("All")
                } footer: {
                    Text("Ended holds the runs you missed, Visited the spots you've checked off. Hiding them keeps the All tab to places you can still go. Both stay on the map.")
                }

                Section {
                    Toggle("Sort by Distance", isOn: $sortsByDistance)
                } header: {
                    Text("Location")
                } footer: {
                    // §7.3 — this toggle is the only thing that asks for location.
                    switch locationProvider.access {
                    case .denied:
                        Text("Location is denied in Settings, so the list keeps its usual order.")
                    case .notDetermined:
                        Text("Orders each section nearest first. Turning this on asks for your location once, and it's used for nothing else.")
                    case .authorized:
                        Text("Each section is ordered nearest first. Sections themselves still go by how much of the run is left.")
                    }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .tags: TagsView()
                case .newTag: TagEditView()
                case let .renameTag(tag): TagEditView(tag: tag)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: sortsByDistance) { _, isOn in
                if isOn { locationProvider.start() } else { locationProvider.stop() }
            }
        }
    }
}

#if DEBUG
#Preview {
    SettingsView(locationProvider: LocationProvider())
        .modelContainer(Spot.previewContainer)
}
#endif
