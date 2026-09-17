//
//  TagEditView.swift
//  Monaka
//
//  One screen for both naming a new tag and renaming an existing one, and for
//  choosing the symbol it shows — the same shape as yomy's CategoryEditView.
//

import SwiftUI
import SwiftData

struct TagEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var spots: [Spot]
    @AppStorage(TagVocabulary.storageKey) private var vocabularyRaw = ""

    /// `nil` when creating.
    let tag: String?

    @State private var name: String
    @State private var icon: String
    @State private var isPickingIcon = false
    @FocusState private var isNameFocused: Bool

    init(tag: String? = nil) {
        self.tag = tag
        _name = State(initialValue: tag ?? "")
        // The stored icon can't be read before the view has its AppStorage, so
        // this starts at the default and `task` corrects it.
        _icon = State(initialValue: TagVocabulary.defaultIcon)
    }

    private var isRenaming: Bool { tag != nil }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Every name already spoken for, whether it's on a spot or only named.
    private var existing: Set<String> {
        Set(spots.flatMap(\.tags))
            .union(TagVocabulary.decode(vocabularyRaw).map(\.name))
    }

    private var isTaken: Bool {
        !trimmed.isEmpty && trimmed != tag && existing.contains(trimmed)
    }

    private var isSaveable: Bool { !trimmed.isEmpty && !isTaken }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Image(systemName: icon)
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 88, height: 88)
                        .background(Color(.tertiarySystemFill), in: .circle)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                TextField("Tag", text: $name)
                    .autocorrectionDisabled()
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { if isSaveable { save() } }

                // Presented by state rather than by a NavigationLink so §4's
                // launch argument can open it — the picker takes a Binding,
                // which a `Hashable` route can't carry.
                Button {
                    isPickingIcon = true
                } label: {
                    LabeledContent {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    } label: {
                        Label("Icon", systemImage: icon)
                    }
                }
                .buttonStyle(.plain)
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
        .navigationDestination(isPresented: $isPickingIcon) {
            IconPickerView(selection: $icon)
        }
        .task {
            if let tag { icon = TagVocabulary.icon(for: tag, in: vocabularyRaw) }
            #if DEBUG
            if DebugLaunchArgument.iconPicker.isSet {
                isPickingIcon = true
                return
            }
            #endif
            isNameFocused = !isRenaming
        }
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

        var entries = TagVocabulary.decode(vocabularyRaw)

        guard let tag else {
            entries.append(TagVocabulary.Entry(name: newName, icon: icon))
            vocabularyRaw = TagVocabulary.encode(entries)
            return
        }

        if newName != tag {
            for spot in spots where spot.tags.contains(tag) {
                // Renaming onto a tag the spot already has must not leave a
                // duplicate behind.
                var tags = spot.tags.map { $0 == tag ? newName : $0 }
                var seen = Set<String>()
                tags = tags.filter { seen.insert($0).inserted }
                spot.tags = tags
            }
        }

        // An in-use tag has no entry until something is chosen for it, so this
        // inserts as well as updates.
        if let index = entries.firstIndex(where: { $0.name == tag }) {
            entries[index] = TagVocabulary.Entry(name: newName, icon: icon)
        } else {
            entries.append(TagVocabulary.Entry(name: newName, icon: icon))
        }
        vocabularyRaw = TagVocabulary.encode(entries)
    }
}

#if DEBUG
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
#endif
