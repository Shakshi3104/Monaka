//
//  TagsView.swift
//  Monaka
//
//  Rename or delete a tag across every spot carrying it. Tags are plain
//  strings on `Spot` (§3), so this is the only place the vocabulary can be
//  tidied up after the fact.
//

import SwiftUI
import SwiftData

struct TagsView: View {
    @Query private var spots: [Spot]

    @State private var renaming: String?
    @State private var newName = ""
    @State private var deleting: String?

    /// Every tag in use, alphabetical, with how many spots carry it.
    private var tags: [(name: String, count: Int)] {
        Dictionary(grouping: spots.flatMap(\.tags), by: { $0 })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if tags.isEmpty {
                ContentUnavailableView(
                    "No Tags Yet",
                    systemImage: "tag",
                    description: Text("Tags you add to a spot will show up here.")
                )
            } else {
                List {
                    Section {
                        ForEach(tags, id: \.name) { tag in
                            row(name: tag.name, count: tag.count)
                        }
                    } footer: {
                        Text("Tap a tag to rename it everywhere it's used.")
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename Tag", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Tag", text: $newName)
            Button("Rename") {
                if let renaming { rename(renaming, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
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
        HStack {
            Text(name)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .onTapGesture {
            newName = name
            renaming = name
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleting = name
            }
        }
    }

    private func rename(_ tag: String, to name: String) {
        guard let trimmed = name.nilIfBlank, trimmed != tag else { return }
        for spot in spots where spot.tags.contains(tag) {
            // Merging into an existing tag must not leave a duplicate behind.
            var tags = spot.tags.map { $0 == tag ? trimmed : $0 }
            var seen = Set<String>()
            tags = tags.filter { seen.insert($0).inserted }
            spot.tags = tags
        }
    }

    private func delete(_ tag: String) {
        for spot in spots where spot.tags.contains(tag) {
            spot.tags.removeAll { $0 == tag }
        }
    }
}

#Preview {
    NavigationStack {
        TagsView()
    }
    .modelContainer(Spot.previewContainer)
}
