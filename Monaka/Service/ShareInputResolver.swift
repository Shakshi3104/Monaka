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
    ///
    /// A social post is different: its site name (“Instagram”) is no venue,
    /// and its description is the caption — the text that actually says
    /// where this is — so that goes to `notes`, where `SpotExtractor` can
    /// read it and the user can keep it.
    private func resolveWebPage(_ url: URL) async -> SpotDraft {
        var draft = SpotDraft()
        draft.urlString = url.absoluteString

        guard let metadata = try? await OGMetadataFetcher().fetch(url) else { return draft }
        draft.imageURL = metadata.imageURL
        if Self.isSocialPost(url) {
            draft.title = Self.socialTitle(metadata.title ?? "")
            draft.notes = Self.socialCaption(metadata.description ?? "")
        } else {
            draft.title = metadata.title ?? ""
            draft.venue = metadata.siteName ?? ""
        }
        return draft
    }

    /// `user on Instagram: "【銀座】実はここ超穴場…"` → `【銀座】実はここ超穴場…`,
    /// and the localized `あかね - Instagram: "📍タカセ"` → `タカセ`.
    /// The wrapper is the network's, the first line of the caption is the
    /// post's. Still not a place's name — `SpotExtractor` replaces this when
    /// it can — but it's what you'd type if you had to.
    static func socialTitle(_ ogTitle: String) -> String {
        var text = ogTitle
        // English "… on Instagram:" and the hyphenated form other locales use.
        let wrappers = [
            #"^.+? on (Instagram|Threads|X|Twitter|TikTok|Facebook):\s*"#,
            #"^.+? [-–—] (Instagram|Threads|X|Twitter|TikTok|Facebook):\s*"#
        ]
        for pattern in wrappers {
            if let range = text.range(of: pattern, options: .regularExpression) {
                text = String(text[range.upperBound...])
                break
            }
        }
        // Captions open with a line of "." or "・" to force a line break in
        // Instagram's layout — taking the first line literally made a spot
        // called ".".
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let firstReal = lines.first { Self.strippedOrnaments($0).count > 1 }
        return Self.strippedOrnaments(firstReal ?? lines.first ?? text)
    }

    /// Instagram's `og:description` is the caption wrapped in a byline —
    /// `December 15, 2024、user: "📍タカセ …"` — and captions end in a wall of
    /// hashtags naming every neighbourhood in Tokyo. Both mislead the model
    /// about what the text is even about, and neither is a note worth
    /// keeping. `SpotExtractor` drops hashtags too; this drops the byline.
    static func socialCaption(_ description: String) -> String {
        var text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: #"^[^"\n]{0,120}:\s*""#, options: .regularExpression) {
            text = String(text[range.upperBound...])
            if text.hasSuffix("\"") { text.removeLast() }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Leading pins and quote marks — `📍タカセ` is a shop called タカセ.
    /// Brackets are left alone: 【銀座】 opens a caption and closes again, and
    /// stripping the opener leaves the stray 】 behind.
    private static func strippedOrnaments(_ text: String) -> String {
        let quotes = CharacterSet(charactersIn: "\"“”·•-.。・…　 ")
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = trimmed.unicodeScalars.first,
              first.properties.isEmojiPresentation || quotes.contains(first) {
            trimmed.unicodeScalars.removeFirst()
            trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        }
        while let last = trimmed.unicodeScalars.last, CharacterSet(charactersIn: "\"“” ").contains(last) {
            trimmed.unicodeScalars.removeLast()
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A post on a social network, where the page is a wrapper around a
    /// caption and the site name says nothing about the place.
    static func isSocialPost(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return socialHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static let socialHosts: [String] = [
        "instagram.com", "threads.net", "threads.com", "x.com", "twitter.com",
        "facebook.com", "tiktok.com", "youtube.com", "youtu.be", "note.com"
    ]

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
