//
//  TagVocabulary.swift
//  Monaka
//
//  What the app knows about a tag beyond the spots carrying it: names the user
//  has set up in advance, and the symbol each one shows.
//
//  §3 keeps tags as plain strings on `Spot`, so there is no tag entity to hang
//  either on. `Spot.tags` stays the only answer to *which* spots carry a tag;
//  this is the vocabulary beside it.
//

import Foundation

enum TagVocabulary {
    /// An `@AppStorage` key, not SwiftData — a tag's name and symbol are
    /// vocabulary, the same call as the Anytime section's expanded state (§7.3).
    ///
    /// The literal is historical: this held only the reserved names before
    /// icons existed, and keeping it means those names survive the change.
    static let storageKey = "reservedTags"

    /// What a tag shows when nothing has been chosen for it — which is every
    /// tag typed straight into a spot's form, never having passed through
    /// Settings.
    static let defaultIcon = "tag"

    struct Entry: Codable, Hashable, Identifiable {
        var name: String
        var icon: String

        var id: String { name }

        init(name: String, icon: String = TagVocabulary.defaultIcon) {
            self.name = name
            self.icon = icon
        }
    }

    /// JSON, and an array rather than a dictionary so the order the user added
    /// things in survives — the Add form's suggestion chips are drawn in this
    /// order, and chips that reshuffle between launches are unusable.
    static func decode(_ raw: String) -> [Entry] {
        guard !raw.isEmpty else { return [] }
        if let data = raw.data(using: .utf8),
           let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            return entries
        }
        // The newline-joined list of bare names this key used to hold.
        return raw.split(separator: "\n").map { Entry(name: String($0)) }
    }

    static func encode(_ entries: [Entry]) -> String {
        var seen = Set<String>()
        let unique = entries.filter { seen.insert($0.name).inserted }
        guard let data = try? JSONEncoder().encode(unique),
              let raw = String(data: data, encoding: .utf8)
        else { return "" }
        return raw
    }

    static func icon(for name: String, in raw: String) -> String {
        decode(raw).first { $0.name == name }?.icon ?? defaultIcon
    }

    /// The symbol a spot's tags ask for, or `nil` when none of them has one.
    ///
    /// Later tags win: the most recently added tag is the one saying what the
    /// spot has just become. A tag with no entry, or one whose entry never got
    /// past `defaultIcon`, is skipped — it has nothing to say, and letting it
    /// through would flatten a whole map to identical `tag` pins.
    static func chosenIcon(forLastOf names: [String], in raw: String) -> String? {
        let entries = decode(raw)
        for name in names.reversed() {
            if let icon = entries.first(where: { $0.name == name })?.icon, icon != defaultIcon {
                return icon
            }
        }
        return nil
    }
}
