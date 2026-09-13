//
//  SpotMapView.swift
//  Monaka
//
//  The Map tab. A stub until the location picker lands and spots start
//  carrying coordinates.
//

import SwiftUI
import SwiftData

struct SpotMapView: View {
    @Query private var spots: [Spot]

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Locations Yet",
                systemImage: "map",
                description: Text("Spots you pin on the map will show up here.")
            )
            .navigationTitle("Map")
        }
    }
}

#Preview {
    SpotMapView()
        .modelContainer(Spot.previewContainer)
}
