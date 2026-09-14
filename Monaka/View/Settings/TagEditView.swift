//
//  TagEditView.swift
//  Monaka
//
//  One screen for both naming a new tag and renaming an existing one — the
//  same shape as yomy's CategoryEditView, minus the icon, since a Monaka tag
//  is just a string (§3).
//

import SwiftUI
import SwiftData

struct TagEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var spots: [Spot]
    @AppStorage(TagVocabulary.storageKey) private var reservedTagsRaw = ""

    /// `nil` when creating.
    let tag: String?

    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(tag: String? = nil) {
        self.tag = tag
        _name = State(initialValue: tag ?? "")
    }

    private var isRenaming: Bool { tag != nil }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Every name already spoken for, whether it's on a spot or just reserved.
    private var existing: Set<String> {
        Set(spots.flatMap(\.tags)).union(TagVocabulary.decode(reservedTagsRaw))
    }

    private var isTaken: Bool {
        !trimmed.isEmpty && trimmed != tag && existing.contains(trimmed)
    }

    private var isSaveable: Bool { !trimmed.isEmpty && !isTaken }

    var body: some View {
        Form {
            Section {
                TextField("Tag", text: $name)
                    .autocorrectionDisabled()
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { if isSaveable { save() } }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle(isRenaming ? "Rename Tag" : "New Tag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { save() }
                    .disabled(!isSaveable)
            }
        }
        .onAppear { isNameFocused = true }
    }

    private var footer: String {
        if isTaken {
            "“\(trimmed)” already exists."
        } else if isRenaming {
            "Renames it on every spot carrying it."
        } else {
            "Adds the name to the suggestions. Put it on a spot from that spot's own form."
        }
    }

    private func save() {
        let newName = trimmed
        guard !newName.isEmpty else { return }
        defer { dismiss() }

        var reserved = TagVocabulary.decode(reservedTagsRaw)

        guard let tag else {
            reserved.append(newName)
            reservedTagsRaw = TagVocabulary.encode(reserved)
            return
        }

        guard newName != tag else { return }

        for spot in spots where spot.tags.contains(tag) {
            // Renaming onto a tag the spot already has must not leave a
            // duplicate behind.
            var tags = spot.tags.map { $0 == tag ? newName : $0 }
            var seen = Set<String>()
            tags = tags.filter { seen.insert($0).inserted }
            spot.tags = tags
        }

        reservedTagsRaw = TagVocabulary.encode(reserved.map { $0 == tag ? newName : $0 })
    }
}

#Preview("New") {
    NavigationStack {
        TagEditView()
    }
    .modelContainer(Spot.previewContainer)
}

#Preview("Rename") {
    NavigationStack {
        TagEditView(tag: "Exhibition")
    }
    .modelContainer(Spot.previewContainer)
}
