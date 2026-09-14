//
//  TagsView.swift
//  Monaka
//
//  The tag vocabulary: what's in use, what's only been named, and the one
//  place either can be renamed or dropped. Tags are plain strings on `Spot`
//  (§3), so a rename here rewrites every spot carrying it.
//

import SwiftUI
import SwiftData

struct TagsView: View {
    @Query private var spots: [Spot]
    @AppStorage(TagVocabulary.storageKey) private var reservedTagsRaw = ""

    @State private var deleting: String?

    /// In-use tags with how many spots carry them, plus the reserved names at
    /// zero. Alphabetical, so a tag doesn't move when its count changes.
    private var tags: [(name: String, count: Int)] {
        let counts = Dictionary(grouping: spots.flatMap(\.tags), by: { $0 })
            .mapValues(\.count)
        let names = Set(counts.keys).union(TagVocabulary.decode(reservedTagsRaw))
        return names
            .map { (name: $0, count: counts[$0] ?? 0) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if tags.isEmpty {
                ContentUnavailableView(
                    "No Tags Yet",
                    systemImage: "tag",
                    description: Text("Add one here, or type one straight into a spot's form.")
                )
            } else {
                List {
                    Section {
                        ForEach(tags, id: \.name) { tag in
                            row(name: tag.name, count: tag.count)
                        }
                    } footer: {
                        Text("The number is how many spots carry the tag. Tap one to rename it everywhere it's used.")
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: SettingsRoute.newTag) {
                    Label("New Tag", systemImage: "plus")
                }
            }
        }
        // Deleting a tag touches every spot carrying it, so it confirms (§6.1).
        .alert("Delete Tag?", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let deleting { delete(deleting) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            if let deleting {
                Text("“\(deleting)” will be removed from every spot. The spots themselves stay.")
            }
        }
    }

    private func row(name: String, count: Int) -> some View {
        NavigationLink {
            TagEditView(tag: name)
        } label: {
            HStack {
                Text(name)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(count == 0 ? .tertiary : .secondary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleting = name
            }
        }
    }

    /// Off every spot *and* out of the reserved list — a tag deleted here
    /// should not come back as a suggestion.
    private func delete(_ tag: String) {
        for spot in spots where spot.tags.contains(tag) {
            spot.tags.removeAll { $0 == tag }
        }
        reservedTagsRaw = TagVocabulary.encode(
            TagVocabulary.decode(reservedTagsRaw).filter { $0 != tag }
        )
    }
}

#Preview {
    NavigationStack {
        TagsView()
    }
    .modelContainer(Spot.previewContainer)
}
