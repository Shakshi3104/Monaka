//
//  PlaceSearch.swift
//  Monaka
//
//  Turning a place's name into a coordinate, and the bridging between
//  `PickedLocation` and MapKit that both the picker and the share sheet need.
//  User-initiated only — one search per spot the user is saving, which is not
//  the bulk geocoding §3 rules out.
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10).
//

import Foundation
import MapKit

extension PickedLocation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ item: MKMapItem) {
        self.init(
            name: item.name ?? "",
            address: item.formattedAddress,
            latitude: item.coordinate.latitude,
            longitude: item.coordinate.longitude
        )
    }

    /// The first place `MKLocalSearch` returns — what the share sheet pins
    /// without asking, since it has no picker to ask with. Wrong often enough
    /// to say so in the form, right often enough to beat leaving every shared
    /// spot off the map.
    ///
    /// `checkingName` guards a search by *name*: MKLocalSearch answers even
    /// nonsense, and 「存在しない店名ZZZQQQ」 came back as a hamlet called 名 in
    /// Saitama. A result is kept only when its name and the query contain one
    /// another once folded — 「タカセ」 and 「たかせ」 do. An address search is
    /// exempt: the result is named after the street, not after the query.
    ///
    /// Finding nothing is normal, not an error (§13-10).
    static func firstMatch(for query: String, checkingName: Bool = true) async -> PickedLocation? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        guard let response = try? await MKLocalSearch(request: request).start(),
              let first = response.mapItems.first
        else { return nil }

        if checkingName {
            let name = Self.folded(first.name ?? "")
            let asked = Self.folded(text)
            // One character overlapping proves nothing: 「存在しない店名ZZZQQQ」
            // "matched" a hamlet called 名 because the query contains 名.
            guard name.count > 1, asked.count > 1,
                  name.contains(asked) || asked.contains(name)
            else { return nil }
        }
        return PickedLocation(first)
    }

    /// Case, width, accents and katakana all folded away, so 「タカセ」 and
    /// 「たかせ」 compare equal.
    private static func folded(_ text: String) -> String {
        let flat = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return (flat.applyingTransform(.hiraganaToKatakana, reverse: true) ?? flat)
            .replacingOccurrences(of: " ", with: "")
    }

    /// Address first, name second: an address search lands on the building,
    /// while a shop's full name — `Pâtisserie TEN & 日比谷okuroji店` — often
    /// matches nothing at all.
    static func firstMatch(forAnyOf queries: [String?]) async -> PickedLocation? {
        for (index, query) in queries.enumerated() {
            guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            // The first entry is the address when there is one.
            if let match = await firstMatch(for: query, checkingName: index > 0) { return match }
        }
        return nil
    }
}

extension MKMapItem {
    /// `placemark` is deprecated as of iOS 26 — `location` / `address` replace it.
    var coordinate: CLLocationCoordinate2D { location.coordinate }

    var formattedAddress: String? { address?.fullAddress }
}
