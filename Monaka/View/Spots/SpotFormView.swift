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
    /// True while a page is being read — OGP and then the model. The owner
    /// disables Save on it: saving halfway through means saving a title
    /// the next second would have replaced.
    var isBusy: Binding<Bool> = .constant(false)

    /// Every tag already in use, for the suggestion row.
    @Query private var spots: [Spot]
    @AppStorage(TagVocabulary.storageKey) private var vocabularyRaw = ""

    @State private var tagInput = ""
    @State private var isNamingTag = false
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

            SpotLocationSection(draft: $draft, isRequired: requiresLocation)
            runSection
            tagSection

            Section("Notes") {
                TextField("Closed Mondays, book ahead…", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        // Dates are entered and read as Asia/Tokyo wall-clock days (§6.1).
        .environment(\.timeZone, Calendar.monaka.timeZone)
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
                    // Text, not URL: a copied link is text too, and so is
                    // a post's caption, which has no link in it.
                    PasteButton(payloadType: String.self) { strings in
                        guard let pasted = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !pasted.isEmpty
                        else { return }
                        if let url = ShareInputResolver.firstURL(in: pasted) {
                            draft.urlString = url.absoluteString
                            Task { await autofill() }
                        } else {
                            Task { await adoptCaption(pasted) }
                        }
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
            if SpotExtractor.isAvailable {
                Text("Paste a link, or a post's caption. Fills in the title, image, venue and — read from the text — the dates, marked so you can check them.")
            } else {
                Text("Fills in the title, image and venue from the page. Dates are always typed by hand.")
            }
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
        isBusy.wrappedValue = true
        lastFetchedURL = draft.urlString
        defer { isFetchingMetadata = false; isBusy.wrappedValue = false }

        // Through the dispatcher, so a pasted Google Maps link fills the
        // coordinates instead of being fetched as a web page (§8.1).
        let resolved = await ShareInputResolver().resolve(.url(url))
        draft.fillEmptyFields(from: resolved)

        // Then the on-device model, for what OGP can't give: a venue named
        // in the body and the run. It only ever fills what is still empty,
        // and the run it proposes is flagged as such.
        guard !MapLinkResolver.isMapLink(url), SpotExtractor.isAvailable else { return }
        if ShareInputResolver.isSocialPost(url) {
            // The caption is the page. The og:title (“user on Instagram: …”)
            // is no title, so this path replaces it.
            guard let caption = resolved.notes.nilIfBlank,
                  let extraction = await SpotExtractor().extract(fromText: caption)
            else { return }
            draft.adopt(extraction, caption: caption)
        } else if let extraction = await SpotExtractor().extract(from: url, subject: resolved.title.nilIfBlank) {
            draft.fillEmptyFields(from: extraction)
        }
    }

    /// A pasted caption with no link in it — an Instagram post about a café.
    /// The model finds the name; the caption itself goes to Notes.
    private func adoptCaption(_ caption: String) async {
        guard SpotExtractor.isAvailable else { return }
        isFetchingMetadata = true
        isBusy.wrappedValue = true
        defer { isFetchingMetadata = false; isBusy.wrappedValue = false }
        if let extraction = await SpotExtractor().extract(fromText: caption) {
            draft.adopt(extraction, caption: caption)
        }
    }

    // MARK: - Location

    @ViewBuilder
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
    /// Every tag there is: the vocabulary in the order Settings shows it,
    /// then names only in use on other spots, then anything typed straight
    /// into this form. Selected or not, they all stay on screen — a tag you
    /// can't see is a tag you retype.
    private var allTags: [String] {
        var seen = Set<String>()
        return (TagVocabulary.decode(vocabularyRaw).map(\.name) + spots.flatMap(\.tags) + draft.tags)
            .filter { seen.insert($0).inserted }
    }

    private var tagSection: some View {
        Section {
            FlowLayout {
                ForEach(allTags, id: \.self) { tag in
                    Button {
                        toggleTag(tag)
                    } label: {
                        TagChip(tag, isSelected: draft.tags.contains(tag))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    isNamingTag = true
                } label: {
                    TagChip("New Tag", icon: "plus", isSelected: false)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Tags")
        } footer: {
            Text("Tap to put a tag on this spot. Tags are plain labels — renaming one later doesn't update spots already saved.")
        }
        .alert("New Tag", isPresented: $isNamingTag) {
            TextField("Tag", text: $tagInput)
                .autocorrectionDisabled()
            Button("Add") { addTag(tagInput) }
            Button("Cancel", role: .cancel) { tagInput = "" }
        } message: {
            Text("Give it an icon later in Settings → Tags.")
        }
    }

    private func toggleTag(_ tag: String) {
        if let index = draft.tags.firstIndex(of: tag) {
            draft.tags.remove(at: index)
        } else {
            draft.tags.append(tag)
        }
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

struct TagChip: View {
    /// Read here rather than passed in, so every caller picks the tag's icon up
    /// without knowing the vocabulary exists.
    @AppStorage(TagVocabulary.storageKey) private var vocabularyRaw = ""

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
