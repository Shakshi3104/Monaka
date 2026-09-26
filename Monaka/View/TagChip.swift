//
//  TagChip.swift
//  Monaka
//
//  One tag as a capsule — filled when it's on the spot, outlined when it's one
//  you could add. Every form and the detail view draw tags with it.
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10).
//

import SwiftUI

struct TagChip: View {
    /// Read here rather than passed in, so every caller picks the tag's icon up
    /// without knowing the vocabulary exists.
    @AppStorage(TagVocabulary.storageKey, store: TagVocabulary.defaults) private var vocabularyRaw = ""

    let tag: String
    /// Overrides the tag's own icon — the `plus` on the New Tag chip, which
    /// names no tag yet.
    var icon: String?
    /// Filled when the tag is on the spot, outlined when it's one you could
    /// add. A chip that reads the same either way is a chip you have to tap
    /// to interrogate.
    var isSelected = true

    init(_ tag: String, icon: String? = nil, isSelected: Bool = true) {
        self.tag = tag
        self.icon = icon
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon ?? TagVocabulary.icon(for: tag, in: vocabularyRaw))
                .font(.caption2)
            Text(tag)
        }
        .font(.caption)
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if isSelected {
                Capsule().fill(Color.accentColor.opacity(0.15))
            } else {
                Capsule().strokeBorder(Color.secondary.opacity(0.35))
            }
        }
    }
}
