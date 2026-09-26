//
//  SettingsView.swift
//  Monaka
//
//  A sheet off the gear in the All tab (§6.1): the list's own options, and
//  the app-wide ones (tags, reminders, location) that have no better home.
//  The Map tab's gear opens `MapSettingsView` instead.
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
    @AppStorage(RunReminder.storageKey) private var remindsBeforeEnd = false
    @State private var reminderAccess: RunReminder.Access = .notDetermined

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
                    Text("Ended holds the runs you missed, Visited the spots you've checked off. Hiding them keeps the All tab to places you can still go.")
                }

                Section {
                    Toggle("Remind Me Before a Run Ends", isOn: $remindsBeforeEnd)
                } header: {
                    Text("Reminders")
                } footer: {
                    // Phase 3 — this toggle is the only thing that asks for
                    // notification permission.
                    switch reminderAccess {
                    case .denied:
                        Text("Notifications are off for Monaka in Settings, so no reminder can be sent.")
                    case .notDetermined:
                        Text("A notification at \(RunReminder.hour):00, \(RunReminder.leadDays) days before a run ends, for spots you haven't visited. Turning this on asks for permission once.")
                    case .authorized:
                        Text("A notification at \(RunReminder.hour):00, \(RunReminder.leadDays) days before a run ends, for spots you haven't visited.")
                    }
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
                        Text("Orders each section nearest first. Turning this on asks for your location once. It's used only for this and to show where you are on the Map.")
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
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .onChange(of: sortsByDistance) { _, isOn in
                if isOn { locationProvider.start() } else { locationProvider.stop() }
            }
            .task { reminderAccess = await RunReminder.access() }
            .onChange(of: remindsBeforeEnd) { _, isOn in
                guard isOn else { return }
                Task {
                    if reminderAccess == .notDetermined { _ = await RunReminder.requestAccess() }
                    reminderAccess = await RunReminder.access()
                }
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
