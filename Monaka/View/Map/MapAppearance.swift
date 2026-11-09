//
//  MapAppearance.swift
//  Monaka
//
//  The Map tab's base map, picked from the button over the map the way Maps
//  picks one (`MapModeView`).
//
//  MapKit has no public Transit style — `MapStyle` is only standard / hybrid /
//  imagery. Transit here is the standard map, colours untouched, with the
//  station symbols turned back on: every other point of interest stays off so
//  the spot pins aren't drowned out.
//

import SwiftUI
import MapKit

enum MapAppearance: String, CaseIterable, Identifiable {
    case standard
    case transit
    case satellite

    static let storageKey = "mapAppearance"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .standard: "Standard"
        case .transit: "Transit"
        case .satellite: "Satellite"
        }
    }

    /// The map-mode button's glyph says which map is on, as in Maps.
    var systemImage: String {
        switch self {
        case .standard: "map"
        case .transit: "tram"
        case .satellite: "globe.asia.australia"
        }
    }

    var style: MapStyle {
        switch self {
        case .standard: .standard(pointsOfInterest: .excludingAll)
        case .transit: .standard(pointsOfInterest: .including([.publicTransport]))
        case .satellite: .hybrid(pointsOfInterest: .excludingAll)
        }
    }
}
