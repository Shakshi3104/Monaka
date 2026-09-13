//
//  Spot+Location.swift
//  Monaka
//
//  Coordinate accessors. App-only, like Spot+Period.
//

import CoreLocation

extension Spot {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasCoordinate: Bool { coordinate != nil }

    /// Metres from `location`, or `nil` when the spot has no coordinate.
    /// Used by the `Anytime` distance sort (§7.3).
    func distance(from location: CLLocation) -> CLLocationDistance? {
        guard let coordinate else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: location)
    }
}
