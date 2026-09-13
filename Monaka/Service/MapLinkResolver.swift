//
//  MapLinkResolver.swift
//  Monaka
//
//  A Google or Apple Maps link → a name and coordinates (§8.2).
//
//  Google's short-link format is NOT a public API. The redirect behaviour and
//  the path shape can change without notice, so every field here is optional
//  and nothing is load-bearing: on any mismatch we keep the URL, fill nothing,
//  and let the user type the name. Never throws, never alerts (§13-11).
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10).
//

import Foundation

struct MapLinkResolver: Sendable {
    struct ResolvedPlace: Equatable, Sendable {
        var name: String?
        var latitude: Double?
        var longitude: Double?
        /// The resolved URL, never the short link — `maps.app.goo.gl` links are
        /// opaque and can stop resolving (§13-12).
        var mapURL: String
    }

    static let googleHosts = ["maps.app.goo.gl", "goo.gl", "google.com", "www.google.com", "maps.google.com"]
    static let appleHosts = ["maps.apple.com"]

    static func isMapLink(_ url: URL) -> Bool {
        isGoogleMapLink(url) || isAppleMapLink(url)
    }

    static func isGoogleMapLink(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        if host == "maps.app.goo.gl" || host.hasSuffix(".app.goo.gl") { return true }
        if host == "goo.gl" || host == "www.goo.gl" { return url.path().contains("/maps") }
        if host.hasPrefix("maps.google.") { return true }
        // google.com / www.google.com only count on a /maps path.
        return host.hasSuffix("google.com") && url.path().hasPrefix("/maps")
    }

    static func isAppleMapLink(_ url: URL) -> Bool {
        url.host()?.lowercased() == "maps.apple.com"
    }

    func resolve(_ url: URL) async -> ResolvedPlace? {
        if Self.isAppleMapLink(url) { return Self.parseAppleMapURL(url) }
        guard Self.isGoogleMapLink(url) else { return nil }

        let resolved = await followRedirect(url) ?? url
        return Self.parseGoogleMapURL(resolved)
    }

    // MARK: - Redirect

    /// `HEAD` first; some servers reject it, so fall back to a `GET` whose body
    /// we cancel as soon as the headers land.
    private func followRedirect(_ url: URL) async -> URL? {
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 10
        if let (_, response) = try? await URLSession.shared.data(for: head),
           let final = response.url, final != url {
            return final
        }

        var get = URLRequest(url: url)
        get.timeoutInterval = 10
        guard let (stream, response) = try? await URLSession.shared.bytes(for: get) else { return nil }
        stream.task.cancel()
        return response.url
    }

    // MARK: - Google

    /// `https://www.google.com/maps/place/<name>/@<lat>,<lng>,17z/data=…!3d<lat>!4d<lng>…`
    static func parseGoogleMapURL(_ url: URL) -> ResolvedPlace {
        var place = ResolvedPlace(mapURL: url.absoluteString)
        let absolute = url.absoluteString

        let components = url.pathComponents
        if let index = components.firstIndex(of: "place"), components.indices.contains(index + 1) {
            place.name = decodePlaceName(components[index + 1])
        }

        // `!3d` / `!4d` is the place itself; `/@lat,lng` is only the map centre.
        if let (latitude, longitude) = firstPair(#"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)"#, in: absolute)
            ?? firstPair(#"/@(-?\d+\.\d+),(-?\d+\.\d+)"#, in: absolute) {
            place.latitude = latitude
            place.longitude = longitude
        } else if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "q" || $0.name == "query" })?.value,
                  let (latitude, longitude) = parseCoordinatePair(query) {
            place.latitude = latitude
            place.longitude = longitude
        }

        return place
    }

    private static func decodePlaceName(_ segment: String) -> String? {
        let spaced = segment.replacingOccurrences(of: "+", with: " ")
        let decoded = spaced.removingPercentEncoding ?? spaced
        // `/place/@35.6,139.7` means there was no name.
        guard !decoded.hasPrefix("@"), !decoded.isEmpty else { return nil }
        return decoded
    }

    // MARK: - Apple

    /// `https://maps.apple.com/?q=Name&ll=35.6,139.7`
    static func parseAppleMapURL(_ url: URL) -> ResolvedPlace {
        var place = ResolvedPlace(mapURL: url.absoluteString)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        if let name = value("q") ?? value("name"), parseCoordinatePair(name) == nil {
            place.name = name.replacingOccurrences(of: "+", with: " ")
        }
        if let coordinate = value("ll") ?? value("sll") ?? value("q"),
           let (latitude, longitude) = parseCoordinatePair(coordinate) {
            place.latitude = latitude
            place.longitude = longitude
        }
        return place
    }

    // MARK: - Parsing helpers

    static func parseCoordinatePair(_ text: String) -> (Double, Double)? {
        let parts = text.split(separator: ",")
        guard parts.count == 2,
              let latitude = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let longitude = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return nil }
        return (latitude, longitude)
    }

    private static func firstPair(_ pattern: String, in text: String) -> (Double, Double)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 2,
              let first = Range(match.range(at: 1), in: text),
              let second = Range(match.range(at: 2), in: text),
              let latitude = Double(text[first]),
              let longitude = Double(text[second])
        else { return nil }
        return (latitude, longitude)
    }
}
