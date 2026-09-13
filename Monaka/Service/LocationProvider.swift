//
//  LocationProvider.swift
//  Monaka
//
//  CoreLocation, When In Use, requested lazily — only when the user turns
//  distance sort on (§7.3, §13-14). Never at launch, never during import.
//  The app is fully usable with location denied; Anytime just falls back to
//  `addedAt` descending.
//

import Foundation
import CoreLocation
import Observation

@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    /// What the UI needs to know, without leaking CoreLocation's four cases.
    enum Access: Equatable {
        case notDetermined
        case denied
        case authorized
    }

    private(set) var location: CLLocation?
    private(set) var access: Access = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        access = Self.access(for: manager.authorizationStatus)
    }

    /// Asks for permission if it hasn't been asked yet, then starts updating.
    /// Call this from the distance-sort toggle, nowhere else.
    func start() {
        switch access {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized:
            manager.startUpdatingLocation()
        case .denied:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        access = Self.access(for: manager.authorizationStatus)
        if access == .authorized {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last ?? location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Nothing to say — the list just keeps its `addedAt` order.
    }

    private static func access(for status: CLAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted, .denied: .denied
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        @unknown default: .denied
        }
    }
}
