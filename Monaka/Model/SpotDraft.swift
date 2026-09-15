//
//  SpotDraft.swift
//  Monaka
//
//  What every capture route produces and the Add form edits (§8). Plain value
//  types — no SwiftData, no MapKit.
//

import Foundation

/// `Equatable` so a form can tell whether anything was actually typed and warn
/// before throwing it away.
struct SpotDraft: Equatable {
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

    /// The run's two ends, kept in order the way Calendar's event editor does
    /// it: dragging the start past the end takes the end with it.
    ///
    /// `runInterval` normalizes a reversed pair anyway, so the spot would still
    /// land in a sensible section — but the form would be showing a run that
    /// reads backwards, which is a typo the user can't see they made.
    var runStart: Date? {
        get { startDate }
        set {
            startDate = newValue
            if let start = newValue, let end = endDate, end < start { endDate = start }
        }
    }

    var runEnd: Date? {
        get { endDate }
        set {
            endDate = newValue
            if let end = newValue, let start = startDate, end < start { startDate = end }
        }
    }

    /// What an end switched on in the form starts at: today, unless that would
    /// reverse the run and drag the end the user just typed back with it.
    var defaultRunStart: Date { min(endDate ?? .now, .now) }

    var defaultRunEnd: Date { max(startDate ?? .now, .now) }

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

// MARK: - What the run will mean

extension SpotDraft {
    /// `2026/04/11`, pinned to `Asia/Tokyo` (§6.1).
    ///
    /// A `FormatStyle` rather than the `DateFormatter.monakaDate` in
    /// Spot+Period.swift: this file compiles into the share extension too,
    /// which can't see anything app-only (§10).
    private static let dateStyle: Date.VerbatimFormatStyle = {
        let timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)/\(month: .twoDigits)/\(day: .twoDigits)",
            timeZone: timeZone,
            calendar: calendar
        )
    }()

    /// Spells out the §7.1 reading of whichever dates are set — with the dates
    /// themselves, because a `DatePicker` renders them in the device's locale
    /// and this is the form that says what the app actually stored.
    var runFooter: String {
        let format = { (date: Date) in Self.dateStyle.format(date) }
        switch (startDate, endDate) {
        case let (start?, end?):
            return "Open \(format(start)) – \(format(end))."
        case let (nil, end?):
            return "Open until \(format(end)). No opening date announced."
        case let (start?, nil):
            return "Open from \(format(start)). No end announced."
        case (nil, nil):
            return "No dates — the spot lands in Anytime and is always available."
        }
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
