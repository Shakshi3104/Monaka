//
//  SettingsView.swift
//  Monaka
//
//  A sheet off the gear in the All tab (§6.1).
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    /// `Ended` is the "missed it" bucket — hideable (§7.2).
    @AppStorage("hidesEndedSection") private var hidesEndedSection = false
    @AppStorage("sortsByDistance") private var sortsByDistance = false

    let locationProvider: LocationProvider

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        TagsView()
                    } label: {
                        Label("Tags", systemImage: "tag")
                    }
                }

                Section {
                    Toggle("Hide Ended Spots", isOn: $hidesEndedSection)
                } footer: {
                    Text("Hides the section of runs you missed.")
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

#Preview {
    SettingsView(locationProvider: LocationProvider())
        .modelContainer(Spot.previewContainer)
}
