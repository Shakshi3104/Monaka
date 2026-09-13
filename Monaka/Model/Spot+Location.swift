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

extension Array where Element == Spot {
    /// Nearest first. Spots with no coordinate keep to the back in their
    /// existing order — a café you never pinned shouldn't outrank one you did.
    func sortedByDistance(from location: CLLocation) -> [Spot] {
        enumerated()
            .sorted { left, right in
                switch (left.element.distance(from: location), right.element.distance(from: location)) {
                case let (first?, second?): first < second
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): left.offset < right.offset
                }
            }
            .map(\.element)
    }
}

extension CLLocationDistance {
    /// `850 m` / `1.2 km`, in the user's units.
    var formattedDistance: String {
        Measurement(value: self, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
