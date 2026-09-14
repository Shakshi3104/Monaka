//
//  TagVocabulary.swift
//  Monaka
//
//  Tags the user has named but hasn't put on a spot yet.
//
//  §3 keeps tags as plain strings on `Spot`, so a tag normally exists only for
//  as long as something carries it — which leaves nowhere to set a vocabulary
//  up in advance. This is that list and nothing more. `Spot.tags` stays the
//  source of truth for which spots have which tag; these names only widen the
//  suggestions in the Add form and fill out the Tags screen.
//

import Foundation

enum TagVocabulary {
    /// An `@AppStorage` key, not SwiftData — a named-but-unused tag is a
    /// preference about vocabulary, the same call as the Anytime section's
    /// expanded state (§7.3).
    static let storageKey = "reservedTags"

    /// Newline-joined.
    ///
    /// Every route that accepts a tag trims it with `String.nilIfBlank`, which
    /// strips newlines as well as spaces, so no tag can contain the separator
    /// and this needs no escaping.
    static func decode(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init)
    }

    static func encode(_ tags: [String]) -> String {
        var seen = Set<String>()
        return tags.filter { seen.insert($0).inserted }.joined(separator: "\n")
    }
}
