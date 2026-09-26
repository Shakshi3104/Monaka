//
//  TagFilterMenu.swift
//  Monaka
//
//  The tag filter the All and Map tabs share: one toolbar menu, "All Spots"
//  plus every tag in use with its icon. `nil` means no filter.
//

import SwiftUI

struct TagFilterMenu: View {
    let tags: [String]
    @Binding var selection: String?

    @AppStorage(TagVocabulary.storageKey, store: TagVocabulary.defaults) private var vocabularyRaw = ""

    var body: some View {
        Menu {
            Picker("Tag", selection: $selection) {
                Label("All Spots", systemImage: "circle.grid.2x2").tag(String?.none)
                ForEach(tags, id: \.self) { tag in
                    Label(tag, systemImage: TagVocabulary.icon(for: tag, in: vocabularyRaw))
                        .tag(String?.some(tag))
                }
            }
        } label: {
            Label("Filter", systemImage: selection == nil ? "tag" : "tag.fill")
        }
    }
}

extension Array where Element == Spot {
    /// Every tag in use, once, in locale order — the menu's rows.
    var tagsInUse: [String] {
        var seen = Set<String>()
        return flatMap(\.tags)
            .filter { seen.insert($0).inserted }
            .sorted { $0.localizedCompare($1) == .orderedAscending }
    }
}
