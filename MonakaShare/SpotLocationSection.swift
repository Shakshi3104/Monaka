//
//  SpotLocationSection.swift
//  Monaka
//
//  The Location row both forms show: a map once the spot is pinned, "Choose
//  on Map" until then, and the picker sheet behind either. One implementation
//  so the share sheet and the app agree on what pinning looks like.
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10).
//

import SwiftUI
import MapKit

struct SpotLocationSection: View {
    @Binding var draft: SpotDraft
    /// Adding in the app pins the spot; a share may be saved without one.
    var isRequired = false

    @State private var isPickingLocation = false

    var body: some View {
        Section {
            if let location = draft.location {
                // Just the map. The marker already carries the name, and on
                // Edit that name is rebuilt from `venue` — so a row above it
                // repeated the Venue field two rows up, word for word.
                Button {
                    isPickingLocation = true
                } label: {
                    SpotMapSnapshot(
                        coordinate: location.coordinate,
                        title: location.name,
                        cornerRadius: 0
                    )
                    .frame(height: 150)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
            } else {
                Button {
                    isPickingLocation = true
                } label: {
                    Label("Choose on Map", systemImage: "mappin.and.ellipse")
                }
            }
        } header: {
            Text("Location")
        } footer: {
            if let location = draft.location {
                // The address stays, but as a footer rather than a row: it is
                // the only thing that tells two branches of the same shop
                // apart, and the map can't.
                VStack(alignment: .leading, spacing: 2) {
                    if let address = location.address {
                        Text(address)
                    }
                    Text("Tap the map to change it.")
                }
            } else {
                Text(isRequired
                     ? "Required. Pin the spot so it shows up on the Map tab."
                     : "Not pinned yet, so it won't show up on the Map tab.")
            }
        }
        .sheet(isPresented: $isPickingLocation) {
            LocationPickerView(
                // An address the text spelled out beats a venue name for
                // finding the exact building.
                initialQuery: draft.location?.name ?? draft.suggestedAddress ?? draft.venue,
                current: draft.location
            ) { location in
                draft.location = location
                if draft.venue.isEmpty { draft.venue = location.name }
            }
        }
    }
}

/// A non-interactive map showing one pin.
///
/// `cornerRadius: 0` lets it sit full-bleed in a grouped list row, where the
/// section already does the clipping.
struct SpotMapSnapshot: View {
    let coordinate: CLLocationCoordinate2D
    let title: String
    var meters: CLLocationDistance = 500
    var cornerRadius: CGFloat = 10

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                )
            )
        ) {
            Marker(title, coordinate: coordinate)
                .tint(Color.accentColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .allowsHitTesting(false)
    }
}
