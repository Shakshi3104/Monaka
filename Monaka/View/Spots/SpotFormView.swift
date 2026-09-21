//
//  SpotFormView.swift
//  Monaka
//
//  The form body shared by AddSpotView and EditSpotView. Everything it edits
//  lives in the bound SpotDraft — no local mirror state to keep in sync.
//

import SwiftUI
import SwiftData
import MapKit

struct SpotFormView: View {
    @Binding var draft: SpotDraft

    /// Adding pins the spot; editing must not insist on it, or a spot that
    /// arrived through the share sheet could never be corrected (§8.1).
    var requiresLocation = false

    /// Every tag already in use, for the suggestion row.
    @Query private var spots: [Spot]
    @AppStorage(TagVocabulary.storageKey) private var vocabularyRaw = ""

    @State private var tagInput = ""
    @State private var isPickingLocation = false
    @State private var isFetchingMetadata = false

    @FocusState private var isURLFocused: Bool
    /// The URL the last fetch ran against, so tapping into the field and back
    /// out doesn't re-request a page nothing has changed about.
    @State private var lastFetchedURL = ""

    var body: some View {
        Form {
            Section("Spot") {
                ClearableTextField("Title", text: $draft.title)
                ClearableTextField("Venue", text: $draft.venue)
            }

            // Directly under the fields it fills. It used to sit below Tags,
            // which put the paste-a-URL route — the one §8 calls the main path —
            // at the bottom of the form, under everything it was meant to save
            // you from typing.
            linkSection

            locationSection
            runSection
            tagSection

            Section("Notes") {
                TextField("Closed Mondays, book ahead…", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        // Dates are entered and read as Asia/Tokyo wall-clock days (§6.1).
        .environment(\.timeZone, Calendar.monaka.timeZone)
        .sheet(isPresented: $isPickingLocation) {
            LocationPickerView(
                initialQuery: draft.location?.name ?? draft.venue,
                current: draft.location
            ) { location in
                draft.location = location
                if draft.venue.isEmpty { draft.venue = location.name }
            }
        }
    }

    // MARK: - Link + OGP autofill

    /// One field with one control at its trailing edge, the way iOS puts a
    /// clear or reload button in a text field — rather than a row of floating
    /// capsules, which a grouped form has no vocabulary for.
    ///
    /// The control is whatever the field needs next: paste into it while it's
    /// empty, re-read the page once there's a URL in it.
    private var linkSection: some View {
        Section {
            HStack(spacing: 8) {
                ClearableTextField("https://", text: $draft.urlString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .focused($isURLFocused)
                    .onSubmit { Task { await autofill() } }

                if isFetchingMetadata {
                    ProgressView()
                } else if draft.urlString.isEmpty {
                    PasteButton(payloadType: URL.self) { urls in
                        guard let url = urls.first else { return }
                        draft.urlString = url.absoluteString
                        Task { await autofill() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                } else {
                    Button("Read the Page Again", systemImage: "arrow.clockwise") {
                        Task { await autofill() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }

            if let imageURL = draft.imageURL, let url = URL(string: imageURL) {
                SpotImagePreview(url: url) { draft.imageURL = nil }
            }
        } header: {
            Text("Link")
        } footer: {
            Text("Fills in the title, image and venue from the page. Dates are always typed by hand.")
        }
        // Leaving the field is as clear a "that's the URL" as hitting Return,
        // and it's what a paste-then-tap-away actually does.
        .onChange(of: isURLFocused) { _, focused in
            guard !focused, !draft.urlString.isEmpty,
                  draft.urlString != lastFetchedURL
            else { return }
            Task { await autofill() }
        }
    }

    /// Silent on failure — a page with no OG tags is normal (§13-10). Only
    /// fills fields the user hasn't already written in.
    private func autofill() async {
        guard let url = URL(string: draft.urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, scheme == "http" || scheme == "https"
        else { return }

        isFetchingMetadata = true
        lastFetchedURL = draft.urlString
        defer { isFetchingMetadata = false }

        // Through the dispatcher, so a pasted Google Maps link fills the
        // coordinates instead of being fetched as a web page (§8.1).
        let resolved = await ShareInputResolver().resolve(.url(url))
        draft.fillEmptyFields(from: resolved)
    }

    // MARK: - Location

    @ViewBuilder
    private var locationSection: some View {
        Section {
            if let location = draft.location {
                // Just the map. The marker already carries the name, and on
                // Edit that name is rebuilt from `venue` — so a row above it
                // repeated the Venue field two rows up, word for word.
                Button {
                    isPickingLocation = true
                } label: {
                    SpotMapSnapshot(
                        coordinate: location.coordinate,
                        title: location.name,
                        cornerRadius: 0
                    )
                    .frame(height: 150)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
            } else {
                Button {
                    isPickingLocation = true
                } label: {
                    Label("Choose on Map", systemImage: "mappin.and.ellipse")
                }
            }
        } header: {
            Text("Location")
        } footer: {
            if let location = draft.location {
                // The address stays, but as a footer rather than a row: it is
                // the only thing that tells two branches of the same shop
                // apart, and the map can't.
                VStack(alignment: .leading, spacing: 2) {
                    if let address = location.address {
                        Text(address)
                    }
                    Text("Tap the map to change it.")
                }
            } else {
                Text(requiresLocation
                     ? "Required. Pin the spot so it shows up on the Map tab."
                     : "Not pinned yet, so it won't show up on the Map tab.")
            }
        }
    }

    // MARK: - Run

    private var hasStartDate: Binding<Bool> {
        Binding(
            get: { draft.startDate != nil },
            set: { draft.runStart = $0 ? (draft.startDate ?? draft.defaultRunStart) : nil }
        )
    }

    private var hasEndDate: Binding<Bool> {
        Binding(
            get: { draft.endDate != nil },
            set: { draft.runEnd = $0 ? (draft.endDate ?? draft.defaultRunEnd) : nil }
        )
    }

    private var runSection: some View {
        Section {
            Toggle("Start date", isOn: hasStartDate)
            if draft.startDate != nil {
                // Through `runStart`, so pushing the start past the end drags
                // the end along instead of leaving a backwards run.
                DatePicker(
                    "Starts",
                    selection: Binding(
                        get: { draft.startDate ?? .now },
                        set: { draft.runStart = $0 }
                    ),
                    displayedComponents: .date
                )
            }
            Toggle("End date", isOn: hasEndDate)
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

    /// Tags already in use elsewhere plus the ones named in Settings but not
    /// yet put on anything, minus the ones already on this draft.
    private var suggestions: [String] {
        let used = Set(draft.tags)
        var seen = Set<String>()
        return (spots.flatMap(\.tags) + TagVocabulary.decode(vocabularyRaw).map(\.name))
            .filter { seen.insert($0).inserted && !used.contains($0) }
    }

    private var tagSection: some View {
        Section {
            if !draft.tags.isEmpty {
                chipRow {
                    ForEach(draft.tags, id: \.self) { tag in
                        Button {
                            draft.tags.removeAll { $0 == tag }
                        } label: {
                            TagChip(tag, systemImage: "xmark")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField("Add a tag", text: $tagInput)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { addTag(tagInput) }

            if !suggestions.isEmpty {
                chipRow {
                    ForEach(suggestions, id: \.self) { tag in
                        Button {
                            addTag(tag)
                        } label: {
                            Label(tag, systemImage: TagVocabulary.icon(for: tag, in: vocabularyRaw))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .font(.caption)
                    }
                }
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Tags are plain labels — renaming one later doesn't update spots already saved.")
        }
    }

    private func chipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                content()
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func addTag(_ tag: String) {
        defer { tagInput = "" }
        guard let trimmed = tag.nilIfBlank, !draft.tags.contains(trimmed) else { return }
        draft.tags.append(trimmed)
    }
}

// MARK: - Discard guard

extension View {
    /// The system behaviour for an edited form sheet: swipe-to-dismiss is
    /// blocked while there is something to lose, and Cancel asks first.
    ///
    /// SwiftUI gives no hook to *intercept* the swipe and ask, so it is
    /// disabled outright rather than silently throwing the edits away.
    func discardChangesGuard(hasChanges: Bool, isPresented: Binding<Bool>) -> some View {
        interactiveDismissDisabled(hasChanges)
            .confirmationDialog(
                "Discard Changes?",
                isPresented: isPresented,
                titleVisibility: .visible
            ) {
                DiscardChangesButtons()
            } message: {
                Text("What you typed here won't be saved.")
            }
    }
}

/// Its own view so `dismiss` resolves against the sheet the dialog was
/// attached to rather than whatever presented it.
/// A text field with the ⓧ that autofilled text needs: a title pulled from
/// a page is often nearly right, and retyping beats backspacing through it.
/// Same glyph as the image row's remove button, so the form reads as one.
struct ClearableTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    init(_ title: LocalizedStringKey, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(title, text: $text)
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
    }
}

struct DiscardChangesButtons: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Discard Changes", role: .destructive) { dismiss() }
        Button("Keep Editing", role: .cancel) {}
    }
}

// MARK: - Shared pieces

/// The image the OGP fetch found, so you can see which page was read before
/// saving — and drop it if it grabbed the site's logo instead of the poster.
struct SpotImagePreview: View {
    let url: URL
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(.tertiarySystemFill)
                    .overlay { ProgressView() }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Image from the page")
                    .font(.subheadline)
                Text(url.host() ?? url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Remove Image", systemImage: "xmark.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
    }
}

/// A non-interactive map showing one pin.
///
/// `cornerRadius: 0` lets it sit full-bleed in a grouped list row, where the
/// section already does the clipping.
struct SpotMapSnapshot: View {
    let coordinate: CLLocationCoordinate2D
    let title: String
    var meters: CLLocationDistance = 500
    var cornerRadius: CGFloat = 10

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                )
            )
        ) {
            Marker(title, coordinate: coordinate)
                .tint(Color.accentColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .allowsHitTesting(false)
    }
}

struct TagChip: View {
    /// Read here rather than passed in, so every caller picks the tag's icon up
    /// without knowing the vocabulary exists.
    @AppStorage(TagVocabulary.storageKey) private var vocabularyRaw = ""

    let tag: String
    /// A trailing glyph for what the chip *does* — the `xmark` on a removable
    /// one. Separate from the tag's own icon, which always leads.
    var systemImage: String?

    init(_ tag: String, systemImage: String? = nil) {
        self.tag = tag
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: TagVocabulary.icon(for: tag, in: vocabularyRaw))
                .font(.caption2)
            Text(tag)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.15), in: .capsule)
    }
}
