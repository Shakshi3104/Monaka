//
//  ShareFormView.swift
//  MonakaShare
//
//  The share sheet's form. Deliberately smaller than the app's: a share should
//  be two taps. No map picker here — a spot captured this way may arrive
//  without a location, and the app lets you pin it later.
//

import SwiftUI
import SwiftData

struct ShareFormView: View {
    let load: () async -> ShareInputResolver.Input?
    let onFinish: () -> Void
    let onCancel: () -> Void

    @State private var draft = SpotDraft()
    @State private var isResolving = true
    @State private var isExtracting = false
    @State private var isPinning = false
    @State private var saveFailed = false
    /// Tags already on spots in the shared store, read once on open.
    @State private var tagsInUse: [String] = []
    @AppStorage(TagVocabulary.storageKey, store: TagVocabulary.defaults) private var vocabularyRaw = ""

    /// Same order as the app's form: the vocabulary as Settings lists it,
    /// then names only in use on spots, then whatever the draft carries.
    private var allTags: [String] {
        var seen = Set<String>()
        return (TagVocabulary.decode(vocabularyRaw).map(\.name) + tagsInUse + draft.tags)
            .filter { seen.insert($0).inserted }
    }

    private var isSaveable: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ClearableTextField("Title", text: $draft.title)
                    ClearableTextField("Venue", text: $draft.venue)
                } footer: {
                    if isResolving {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("Reading the page…")
                        }
                    } else if isExtracting {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("Reading it for the name, place and dates…")
                        }
                    }
                }

                sourceSection
                locationSection
                runSection
                tagSection

                Section {
                    TextField("Closed Mondays, book ahead…", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Notes")
                }
            }
            .environment(\.timeZone, Calendar.monaka.timeZone)
            .navigationTitle("Save to Monaka")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Saving mid-read would keep a title the next second
                    // replaces, so Save waits for the model too.
                    Button("Save", systemImage: "checkmark") { save() }
                        .disabled(!isSaveable || isResolving || isExtracting || isPinning)
                }
            }
            .alert("Couldn't Save", isPresented: $saveFailed) {
                Button("OK") { onCancel() }
            } message: {
                Text("Monaka's shared store is unavailable.")
            }
            .task {
                tagsInUse = Self.tagsInStore()
                guard let input = await load() else { isResolving = false; return }
                let resolved = await ShareInputResolver().resolve(input)
                draft.fillEmptyFields(from: resolved)
                isResolving = false

                await readWithModel(input: input, resolved: resolved)
                await pinAutomatically()
            }
        }
    }

    // MARK: - Filling it in

    /// The on-device model reads the body for the venue and the run. Save
    /// waits for it: a few seconds, and what it writes is what you'd
    /// otherwise type.
    private func readWithModel(input: ShareInputResolver.Input, resolved: SpotDraft) async {
        guard SpotExtractor.isAvailable else { return }
        isExtracting = true
        defer { isExtracting = false }

        switch input {
        case let .text(text) where ShareInputResolver.firstURL(in: text) == nil:
            // A caption. The resolver made the whole thing the title; the
            // model finds the name in it.
            if let extraction = await SpotExtractor().extract(fromText: text, isCaption: true, tags: allTags) {
                draft.adopt(extraction, caption: text)
            }
        case let .text(text):
            // "name https://…" — the URL is the page to read.
            guard let url = ShareInputResolver.firstURL(in: text), !MapLinkResolver.isMapLink(url) else { return }
            if let extraction = await SpotExtractor().extract(from: url, subject: resolved.title.nilIfBlank, tags: allTags) {
                draft.fillEmptyFields(from: extraction)
            }
        case let .url(url):
            guard !MapLinkResolver.isMapLink(url) else { return }
            if ShareInputResolver.isSocialPost(url) {
                // An Instagram post: the caption is in Notes now, and the
                // og:title (“user on Instagram: …”) is no title.
                if let caption = resolved.notes.nilIfBlank,
                   let extraction = await SpotExtractor().extract(fromText: caption, isCaption: true, tags: allTags) {
                    draft.adopt(extraction, caption: caption)
                }
            } else if let extraction = await SpotExtractor().extract(from: url, subject: resolved.title.nilIfBlank, tags: allTags) {
                draft.fillEmptyFields(from: extraction)
            }
        }
    }

    /// Pins whatever `MKLocalSearch` returns first for the place's name. The
    /// share sheet has no picker — the one it had dismissed the extension
    /// itself — so it guesses out loud instead: the form shows what it found
    /// and says it can be corrected in Monaka. A share that isn't pinned at
    /// all never reaches the Map tab, which is worse than a pin one tap from
    /// being right.
    private func pinAutomatically() async {
        guard draft.location == nil else { return }
        isPinning = true
        defer { isPinning = false }
        draft.location = await PickedLocation.firstMatch(
            forAnyOf: [draft.suggestedAddress, draft.venue.nilIfBlank, draft.title.nilIfBlank]
        )
    }

    // MARK: - Location

    @ViewBuilder
    private var locationSection: some View {
        Section {
            if let location = draft.location {
                SpotMapSnapshot(
                    coordinate: location.coordinate,
                    title: location.name,
                    cornerRadius: 0
                )
                .frame(height: 130)
                .listRowInsets(EdgeInsets())
            } else if isPinning {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("Looking the place up…")
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Not pinned", systemImage: "mappin.slash")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Location")
        } footer: {
            if let location = draft.location {
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.address ?? location.name)
                    Text("Found from the name. Open the spot in Monaka to move the pin.")
                }
            } else if !isPinning {
                Text("Nothing matched the name, so it won't show up on the Map tab. Pin it in Monaka.")
            }
        }
    }

    // MARK: - What was captured

    /// What the resolver actually read, so you can tell a page that gave up its
    /// poster from one that handed over a logo — the only check available here,
    /// since the extension has no map picker to fall back on.
    @ViewBuilder
    private var sourceSection: some View {
        if let imageURL = draft.imageURL, let url = URL(string: imageURL) {
            Section("From the Page") {
                HStack(spacing: 12) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color(.tertiarySystemFill)
                            .overlay { ProgressView() }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text(draft.urlString.isEmpty
                         ? "Image from the page"
                         : URL(string: draft.urlString)?.host() ?? draft.urlString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Button("Remove Image", systemImage: "xmark.circle.fill") {
                        draft.imageURL = nil
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Run

    private var runSection: some View {
        Section {
            Toggle("Start date", isOn: Binding(
                get: { draft.startDate != nil },
                set: { draft.runStart = $0 ? (draft.startDate ?? draft.defaultRunStart) : nil }
            ))
            if draft.startDate != nil {
                // Through `runStart` / `runEnd`, so the two ends can't end up
                // the wrong way round.
                DatePicker(
                    "Starts",
                    selection: Binding(
                        get: { draft.startDate ?? .now },
                        set: { draft.runStart = $0 }
                    ),
                    displayedComponents: .date
                )
            }
            Toggle("End date", isOn: Binding(
                get: { draft.endDate != nil },
                set: { draft.runEnd = $0 ? (draft.endDate ?? draft.defaultRunEnd) : nil }
            ))
            if draft.endDate != nil {
                DatePicker(
                    "Ends",
                    selection: Binding(
                        get: { draft.endDate ?? .now },
                        set: { draft.runEnd = $0 }
                    ),
                    displayedComponents: .date
                )
            }
        } header: {
            Text("Run")
        } footer: {
            Text(draft.runFooter)
        }
    }

    // MARK: - Tags

    /// Every tag there is, as chips — the ones the model picked already on.
    /// No New Tag chip: naming one needs an alert with a text field, and
    /// anything presented from here risks tearing the share sheet down (§8.1).
    @ViewBuilder
    private var tagSection: some View {
        if !allTags.isEmpty {
            Section {
                FlowLayout {
                    ForEach(allTags, id: \.self) { tag in
                        Button {
                            draft.areTagsSuggested = false
                            if let index = draft.tags.firstIndex(of: tag) {
                                draft.tags.remove(at: index)
                            } else {
                                draft.tags.append(tag)
                            }
                        } label: {
                            TagChip(tag, isSelected: draft.tags.contains(tag))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Tags")
            } footer: {
                if draft.areTagsSuggested {
                    Text("Picked from your tags by reading the page — tap one to take it off.")
                }
            }
        }
    }

    private static func tagsInStore() -> [String] {
        guard let container = try? SharedStore.makeModelContainer(),
              let spots = try? ModelContext(container).fetch(FetchDescriptor<Spot>())
        else { return [] }
        return spots.flatMap(\.tags)
    }

    // MARK: - Save

    private func save() {
        do {
            let container = try SharedStore.makeModelContainer()
            let context = ModelContext(container)
            context.insert(draft.makeSpot())
            try context.save()
            onFinish()
        } catch {
            saveFailed = true
        }
    }
}

/// `Calendar.monaka` lives in Spot+Period.swift, which is app-only — the
/// extension keeps its own copy of just the pinned calendar (§6.1).
extension Calendar {
    static let monaka: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()
}
