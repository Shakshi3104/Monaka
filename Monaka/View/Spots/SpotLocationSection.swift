//
//  SpotLocationSection.swift
//  Monaka
//
//  The Location row the app's forms show: a map once the spot is pinned,
//  "Choose on Map" until then, and the picker sheet behind either. App-only —
//  the share sheet pins automatically instead (§8.1).
//

import SwiftUI
import MapKit

struct SpotLocationSection: View {
    @Binding var draft: SpotDraft
    /// Adding in the app pins the spot; a share may be saved without one.
    var isRequired = false
    /// Owned by the form, not by this section: a `.sheet` attached inside a
    /// `Form` is torn down and rebuilt whenever the form redraws, which
    /// dismissed the picker the instant it appeared. The section only asks;
    /// `.locationPicker(…)` at the form's root presents.
    @Binding var isPicking: Bool

    var body: some View {
        Section {
            if let location = draft.location {
                // Just the map. The marker already carries the name, and on
                // Edit that name is rebuilt from `venue` — so a row above it
                // repeated the Venue field two rows up, word for word.
                Button {
                    isPicking = true
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
                    isPicking = true
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
    }
}

extension View {
    /// The picker sheet, attached at the form's root where its presentation
    /// survives a redraw.
    func locationPicker(draft: Binding<SpotDraft>, isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            LocationPickerView(
                // An address the text spelled out beats a venue name for
                // finding the exact building.
                initialQuery: draft.wrappedValue.location?.name
                    ?? draft.wrappedValue.suggestedAddress
                    ?? draft.wrappedValue.venue,
                current: draft.wrappedValue.location,
                onPick: { location in
                    draft.wrappedValue.location = location
                    if draft.wrappedValue.venue.isEmpty { draft.wrappedValue.venue = location.name }
                },
                onClose: { isPresented.wrappedValue = false }
            )
        }
    }
}
