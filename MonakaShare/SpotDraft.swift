//
//  SpotDraft.swift
//  Monaka
//
//  What every capture route produces and the Add form edits (§8). Plain value
//  types — no SwiftData, no MapKit.
//

import Foundation

struct SpotDraft {
    var title: String = ""
    var venue: String = ""
    var urlString: String = ""
    var mapURL: String?
    var notes: String = ""
    var imageURL: String?

    var startDate: Date?
    var endDate: Date?

    var location: PickedLocation?

    var tags: [String] = []

    var hasLocation: Bool { location != nil }

    /// What a spot actually needs. Editing requires only this — a spot
    /// captured through the share sheet has no location (§8.1), and demanding
    /// one here would make it impossible to correct anything about it,
    /// including its run.
    var isSaveable: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Adding a spot in the app additionally pins it, so it reaches the Map
    /// tab (§8.1).
    var isAddable: Bool {
        isSaveable && hasLocation
    }

    init() {}

    /// Load an existing spot for editing.
    init(_ spot: Spot) {
        title = spot.title
        venue = spot.venue ?? ""
        urlString = spot.urlString ?? ""
        mapURL = spot.mapURL
        notes = spot.notes ?? ""
        imageURL = spot.imageURL
        startDate = spot.startDate
        endDate = spot.endDate
        tags = spot.tags
        if let latitude = spot.latitude, let longitude = spot.longitude {
            location = PickedLocation(
                name: spot.venue ?? spot.title,
                address: spot.address,
                latitude: latitude,
                longitude: longitude
            )
        }
    }

    /// Write the edits back. `addedAt`, `isVisited` and `visitedAt` are the
    /// spot's own history and are never touched by the form.
    func apply(to spot: Spot) {
        spot.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        spot.venue = venue.nilIfBlank
        spot.urlString = urlString.nilIfBlank
        spot.mapURL = mapURL
        spot.notes = notes.nilIfBlank
        spot.imageURL = imageURL
        spot.startDate = startDate
        spot.endDate = endDate
        spot.latitude = location?.latitude
        spot.longitude = location?.longitude
        spot.address = location?.address
        spot.tags = tags
    }

    func makeSpot() -> Spot {
        Spot(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            venue: venue.nilIfBlank,
            urlString: urlString.nilIfBlank,
            mapURL: mapURL,
            notes: notes.nilIfBlank,
            imageURL: imageURL,
            startDate: startDate,
            endDate: endDate,
            latitude: location?.latitude,
            longitude: location?.longitude,
            address: location?.address,
            tags: tags
        )
    }
}

/// A place chosen on the map. Kept free of MapKit so the draft stays portable
/// to the share extension.
struct PickedLocation: Equatable {
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
