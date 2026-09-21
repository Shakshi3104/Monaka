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
    @State private var saveFailed = false

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
                runSection

                Section {
                    TextField("Closed Mondays, book ahead…", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Notes")
                } footer: {
                    if draft.location == nil {
                        Label(
                            "No location yet — pin it in Monaka to put it on the Map tab.",
                            systemImage: "mappin.slash"
                        )
                    }
                }
            }
            .environment(\.timeZone, Calendar.monaka.timeZone)
            .navigationTitle("Save to Monaka")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isSaveable || isResolving)
                }
            }
            .alert("Couldn't Save", isPresented: $saveFailed) {
                Button("OK") { onCancel() }
            } message: {
                Text("Monaka's shared store is unavailable.")
            }
            .task {
                guard let input = await load() else { isResolving = false; return }
                let resolved = await ShareInputResolver().resolve(input)
                draft.fillEmptyFields(from: resolved)
                isResolving = false

                // The on-device model reads the body for the venue and the
                // run. Save is live throughout — a share is two taps, and this
                // is a few seconds; saving first just means typing the dates.
                guard SpotExtractor.isAvailable else { return }
                isExtracting = true
                defer { isExtracting = false }
                switch input {
                case let .text(text) where ShareInputResolver.firstURL(in: text) == nil:
                    // A caption. The resolver made the whole thing the title;
                    // the model finds the name in it.
                    if let extraction = await SpotExtractor().extract(fromText: text) {
                        draft.adopt(extraction, caption: text)
                    }
                case let .text(text):
                    // "name https://…" — the URL is the page to read.
                    guard let url = ShareInputResolver.firstURL(in: text), !MapLinkResolver.isMapLink(url) else { return }
                    if let extraction = await SpotExtractor().extract(from: url, subject: resolved.title.nilIfBlank) {
                        draft.fillEmptyFields(from: extraction)
                    }
                case let .url(url):
                    guard !MapLinkResolver.isMapLink(url) else { return }
                    if ShareInputResolver.isSocialPost(url) {
                        // An Instagram post: the caption is in Notes now, and
                        // the og:title (“user on Instagram: …”) is no title.
                        guard let caption = resolved.notes.nilIfBlank,
                              let extraction = await SpotExtractor().extract(fromText: caption)
                        else { return }
                        draft.adopt(extraction, caption: caption)
                    } else if let extraction = await SpotExtractor().extract(from: url, subject: resolved.title.nilIfBlank) {
                        draft.fillEmptyFields(from: extraction)
                    }
                }
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
