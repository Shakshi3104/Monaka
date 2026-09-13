//
//  ShareInputResolver.swift
//  Monaka
//
//  Branches a shared item to the right resolver (§8.1) and returns a draft.
//  A resolver that fails fills nothing and is not an error — the form opens
//  either way.
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10).
//

import Foundation

struct ShareInputResolver: Sendable {
    enum Input: Equatable, Sendable {
        case url(URL)
        case text(String)
    }

    func resolve(_ input: Input) async -> SpotDraft {
        switch input {
        case let .text(text):
            if let url = Self.firstURL(in: text) {
                return await resolve(.url(url))
            }
            var draft = SpotDraft()
            draft.title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return draft

        case let .url(url):
            if MapLinkResolver.isMapLink(url) {
                return await resolveMapLink(url)
            }
            return await resolveWebPage(url)
        }
    }

    /// `title`, `latitude`, `longitude`, `mapURL`.
    private func resolveMapLink(_ url: URL) async -> SpotDraft {
        var draft = SpotDraft()
        // Keep the raw link even when parsing gets us nothing (§13-11).
        draft.mapURL = url.absoluteString

        guard let place = await MapLinkResolver().resolve(url) else { return draft }
        draft.mapURL = place.mapURL
        if let name = place.name {
            draft.title = name
            draft.venue = name
        }
        if let latitude = place.latitude, let longitude = place.longitude {
            draft.location = PickedLocation(
                name: place.name ?? "",
                address: nil,
                latitude: latitude,
                longitude: longitude
            )
        }
        return draft
    }

    /// `title`, `imageURL`, `venue` (`og:site_name`), `urlString`.
    private func resolveWebPage(_ url: URL) async -> SpotDraft {
        var draft = SpotDraft()
        draft.urlString = url.absoluteString

        guard let metadata = try? await OGMetadataFetcher().fetch(url) else { return draft }
        draft.title = metadata.title ?? ""
        draft.venue = metadata.siteName ?? ""
        draft.imageURL = metadata.imageURL
        return draft
    }

    /// Shares often arrive as "some text https://…" in one string.
    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, range: range)?.url
    }
}

extension SpotDraft {
    /// Merge a resolved draft in without clobbering anything already typed.
    mutating func fillEmptyFields(from other: SpotDraft) {
        if title.isEmpty { title = other.title }
        if venue.isEmpty { venue = other.venue }
        if urlString.isEmpty { urlString = other.urlString }
        if mapURL == nil { mapURL = other.mapURL }
        if notes.isEmpty { notes = other.notes }
        if imageURL == nil { imageURL = other.imageURL }
        if startDate == nil { startDate = other.startDate }
        if endDate == nil { endDate = other.endDate }
        if location == nil { location = other.location }
        if tags.isEmpty { tags = other.tags }
    }
}
