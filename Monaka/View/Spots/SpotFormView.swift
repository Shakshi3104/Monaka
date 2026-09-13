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

    /// Every tag already in use, for the suggestion row.
    @Query private var spots: [Spot]

    @State private var tagInput = ""
    @State private var isPickingLocation = false
    @State private var isFetchingMetadata = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $draft.title)
                TextField("Venue", text: $draft.venue)
            }

            locationSection
            runSection
            tagSection

            linkSection

            Section("Notes") {
                TextField("Notes", text: $draft.notes, axis: .vertical)
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

    private var linkSection: some View {
        Section {
            HStack {
                TextField("https://", text: $draft.urlString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit { Task { await autofill() } }
                if isFetchingMetadata {
                    ProgressView()
                }
            }

            HStack {
                PasteButton(payloadType: URL.self) { urls in
                    guard let url = urls.first else { return }
                    draft.urlString = url.absoluteString
                    Task { await autofill() }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)

                Spacer()

                if !draft.urlString.isEmpty {
                    Button("Fetch Info") { Task { await autofill() } }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .font(.caption)
                        .disabled(isFetchingMetadata)
                }
            }

            if let imageURL = draft.imageURL, let url = URL(string: imageURL) {
                HStack(spacing: 12) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color(.tertiarySystemFill)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("Image from the page")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Remove", systemImage: "xmark.circle.fill") {
                        draft.imageURL = nil
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Link")
        } footer: {
            Text("Fills in the title, image and venue from the page. Dates are always typed by hand.")
        }
    }

    /// Silent on failure — a page with no OG tags is normal (§13-10). Only
    /// fills fields the user hasn't already written in.
    private func autofill() async {
        guard let url = URL(string: draft.urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, scheme == "http" || scheme == "https"
        else { return }

        isFetchingMetadata = true
        defer { isFetchingMetadata = false }

        guard let metadata = try? await OGMetadataFetcher().fetch(url) else { return }

        if draft.title.isEmpty, let title = metadata.title { draft.title = title }
        if draft.venue.isEmpty, let siteName = metadata.siteName { draft.venue = siteName }
        if draft.imageURL == nil { draft.imageURL = metadata.imageURL }
    }

    // MARK: - Location

    @ViewBuilder
    private var locationSection: some View {
        Section {
            if let location = draft.location {
                Button {
                    isPickingLocation = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(location.name)
                                    .foregroundStyle(.primary)
                                if let address = location.address {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        SpotMapSnapshot(
                            coordinate: location.coordinate,
                            title: location.name
                        )
                        .frame(height: 120)
                    }
                }
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
            if draft.location == nil {
                Text("Pin the spot so it shows up on the Map tab.")
            }
        }
    }

    // MARK: - Run

    private var hasStartDate: Binding<Bool> {
        Binding(
            get: { draft.startDate != nil },
            set: { draft.startDate = $0 ? (draft.startDate ?? .now) : nil }
        )
    }

    private var hasEndDate: Binding<Bool> {
        Binding(
            get: { draft.endDate != nil },
            set: { draft.endDate = $0 ? (draft.endDate ?? .now) : nil }
        )
    }

    private var runSection: some View {
        Section {
            Toggle("Start date", isOn: hasStartDate)
            if draft.startDate != nil {
                DatePicker(
                    "Starts",
                    selection: Binding(
                        get: { draft.startDate ?? .now },
                        set: { draft.startDate = $0 }
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
                        set: { draft.endDate = $0 }
                    ),
                    displayedComponents: .date
                )
            }
        } header: {
            Text("Run")
        } footer: {
            Text(runFooter)
        }
    }

    /// Spells out the §7.1 interpretation of whichever dates are set.
    private var runFooter: String {
        switch (draft.startDate != nil, draft.endDate != nil) {
        case (true, true): "Open during this period."
        case (false, true): "Open until the end date."
        case (true, false): "Open from the start date, no end announced."
        case (false, false): "No dates — the spot lands in Anytime and is always available."
        }
    }

    // MARK: - Tags

    /// Tags already in use elsewhere, minus the ones on this draft.
    private var suggestions: [String] {
        let used = Set(draft.tags)
        var seen = Set<String>()
        return spots.flatMap(\.tags).filter { seen.insert($0).inserted && !used.contains($0) }
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
                        Button(tag) { addTag(tag) }
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

// MARK: - Shared pieces

/// A non-interactive map showing one pin.
struct SpotMapSnapshot: View {
    let coordinate: CLLocationCoordinate2D
    let title: String
    var meters: CLLocationDistance = 500

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
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(false)
    }
}

struct TagChip: View {
    let tag: String
    var systemImage: String?

    init(_ tag: String, systemImage: String? = nil) {
        self.tag = tag
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
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
