//
//  SpotMapSnapshot.swift
//  Monaka
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10) — the share sheet shows the
//  place it pinned with the same map the form does.
//

import SwiftUI
import MapKit

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
