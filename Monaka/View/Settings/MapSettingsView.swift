//
//  MapSettingsView.swift
//  Monaka
//
//  A sheet off the gear in the Map tab: what the map pins beyond the places
//  you can still go. Each tab's gear opens that tab's options (§6.1).
//

import SwiftUI

struct MapSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("mapShowsVisited") private var showsVisited = false
    @AppStorage("mapShowsEnded") private var showsEnded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show Visited Spots", isOn: $showsVisited)
                    Toggle("Show Ended Spots", isOn: $showsEnded)
                } footer: {
                    Text("The map shows places you can still go. Turn these on to pin the ones you've been to, or missed, as well.")
                }
            }
            .navigationTitle("Map Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    MapSettingsView()
}
