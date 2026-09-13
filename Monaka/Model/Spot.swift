//
//  Spot.swift
//  Monaka
//
//  A place worth going to, with or without a run.
//
//  Plain value types only — this file is compiled into the share extension
//  target verbatim (CLAUDE.md §10). Anything that *interprets* a spot goes in
//  Spot+Period.swift.
//

import Foundation
import SwiftData

@Model
final class Spot {
    var id: UUID = UUID()
    var title: String = ""          // exhibition / event / shop name
    var venue: String?              // venue or area
    var urlString: String?          // official page
    var mapURL: String?             // Google / Apple Maps link, kept verbatim
    var notes: String?
    var imageURL: String?           // filled from OGP

    // The run. Both nil means "anytime".
    var startDate: Date?
    var endDate: Date?

    var latitude: Double?
    var longitude: Double?
    var address: String?

    var isVisited: Bool = false
    var visitedAt: Date?
    var addedAt: Date = Date.now

    /// Free-form labels ("Exhibition", "Café"). Plain strings, not a relationship —
    /// renaming a tag does not retroactively update existing spots (§3).
    var tags: [String] = []

    init(
        id: UUID = UUID(),
        title: String = "",
        venue: String? = nil,
        urlString: String? = nil,
        mapURL: String? = nil,
        notes: String? = nil,
        imageURL: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String? = nil,
        isVisited: Bool = false,
        visitedAt: Date? = nil,
        addedAt: Date = .now,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.venue = venue
        self.urlString = urlString
        self.mapURL = mapURL
        self.notes = notes
        self.imageURL = imageURL
        self.startDate = startDate
        self.endDate = endDate
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.isVisited = isVisited
        self.visitedAt = visitedAt
        self.addedAt = addedAt
        self.tags = tags
    }
}
