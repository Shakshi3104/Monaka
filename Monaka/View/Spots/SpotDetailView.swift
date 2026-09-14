//
//  SpotDetailView.swift
//  Monaka
//
//  A grouped detail screen in the Contacts / Calendar-event shape: a floating
//  header, then real list sections, then the one action that matters — Visited —
//  pinned to the bottom so it never scrolls out of reach.
//

import SwiftUI
import SwiftData
import MapKit

struct SpotDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let spot: Spot

    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    private var countdown: Spot.Countdown { spot.countdown() }

    /// The official page, if it parses.
    private var pageURL: URL? {
        guard let urlString = spot.urlString else { return nil }
        return URL(string: urlString)
    }

    /// A map link on its own is enough to show the Location section — a spot
    /// shared from Google Maps can have one before it has coordinates (§8.1).
    private var hasLocation: Bool {
        spot.hasCoordinate || spot.mapURL != nil
    }

    /// A place saved from Google Maps often has the venue equal to the title;
    /// repeating it under the nav title says nothing.
    private var subtitle: String {
        guard let venue = spot.venue?.nilIfBlank, venue != spot.title else { return "" }
        return venue
    }

    var body: some View {
        List {
            header
            runSection
            if hasLocation { locationSection }
            if pageURL != nil { linkSection }
            if let notes = spot.notes?.nilIfBlank { notesSection(notes) }
            if !spot.tags.isEmpty { tagSection }
            addedFooter
        }
        .listStyle(.insetGrouped)
        // The title is the large nav title, not a second heading in the body —
        // it collapses to inline on scroll the way every system detail does.
        .navigationTitle(spot.title)
        .navigationSubtitle(subtitle)
        // A bar, not a plain inset: the list fades out under it instead of
        // colliding with the map snapshot halfway through a scroll.
        .safeAreaBar(edge: .bottom) { visitedBar }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    if let pageURL {
                        ShareLink(item: pageURL) {
                            Label("Share Link", systemImage: "square.and.arrow.up")
                        }
                    }
                    Section {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditSpotView(spot: spot)
        }
        // §6.1 — destructive actions in the detail view confirm via .alert.
        .alert("Delete Spot?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                modelContext.delete(spot)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(spot.title)” will be removed from Monaka.")
        }
    }

    // MARK: - Header

    /// Floats above the grouped sections rather than sitting in a card of its
    /// own — the Contacts pattern. Title and venue live in the nav bar, so this
    /// carries only the image and how much run is left.
    @ViewBuilder
    private var header: some View {
        if spot.imageURL != nil || countdown.text != nil {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    headerImage
                    if let text = countdown.text {
                        statusPill(text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var headerImage: some View {
        if let imageURL = spot.imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(.tertiarySystemFill)
                    .overlay { ProgressView() }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.separator.opacity(0.5))
            }
        }
    }

    private func statusPill(_ text: String) -> some View {
        let tint = countdown.emphasis.color
        return Label(text, systemImage: countdown.symbolName)
            .font(.footnote.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: .capsule)
    }

    // MARK: - Run

    private var runSection: some View {
        Section {
            if let start = spot.startDate {
                LabeledContent("Starts", value: DateFormatter.monakaDateWithWeekday.string(from: start))
            }
            if let end = spot.endDate {
                LabeledContent("Ends", value: DateFormatter.monakaDateWithWeekday.string(from: end))
            }
            if !spot.hasRun {
                LabeledContent("Run", value: "Anytime")
            }
            if spot.isVisited, let visitedAt = spot.visitedAt {
                LabeledContent("Visited") {
                    Text(DateFormatter.monakaDate.string(from: visitedAt))
                        .foregroundStyle(.green)
                }
            }
        } header: {
            Text("Run")
        } footer: {
            if let runFooter { Text(runFooter) }
        }
    }

    /// Spells out the §7.1 reading only where the rows don't already say it —
    /// a start and an end date need no gloss, a half-open run does.
    private var runFooter: String? {
        switch spot.run {
        case .period, .anytime: nil
        case .until: "Open until the end date. No opening date recorded."
        case .from: "Open from the start date, no end announced."
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        Section("Location") {
            if let coordinate = spot.coordinate {
                Button {
                    openInMaps(coordinate)
                } label: {
                    SpotMapSnapshot(coordinate: coordinate, title: spot.title, cornerRadius: 0)
                        .frame(height: 160)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
            }

            if let address = spot.address?.nilIfBlank {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button {
                openInMaps(spot.coordinate)
            } label: {
                actionRow("Open in Maps", systemImage: "map")
            }
        }
    }

    /// The stored `mapURL` wins when there is one — Google Maps claims it as a
    /// universal link when installed, Safari handles it when not (§8.2).
    private func openInMaps(_ coordinate: CLLocationCoordinate2D?) {
        if let mapURL = spot.mapURL, let url = URL(string: mapURL) {
            openURL(url)
            return
        }
        guard let coordinate else { return }
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "q", value: spot.venue ?? spot.title)
        ]
        if let url = components?.url { openURL(url) }
    }

    // MARK: - Link / notes / tags

    @ViewBuilder
    private var linkSection: some View {
        if let pageURL {
            Section("Link") {
                Link(destination: pageURL) {
                    actionRow(pageURL.host() ?? pageURL.absoluteString, systemImage: "safari")
                }
            }
        }
    }

    /// A tinted label plus the trailing glyph iOS uses for "this leaves the app".
    private func actionRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private func notesSection(_ notes: String) -> some View {
        Section("Notes") {
            Text(notes)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private var tagSection: some View {
        Section("Tags") {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(spot.tags, id: \.self) { tag in
                        TagChip(tag)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var addedFooter: some View {
        Section {
            EmptyView()
        } footer: {
            Text("Added \(DateFormatter.monakaDate.string(from: spot.addedAt))")
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Visited

    /// Floats over the list instead of scrolling away at the bottom of it —
    /// checking a spot off is the one thing this screen is for.
    private var visitedBar: some View {
        Button {
            withAnimation(.snappy) { spot.toggleVisited() }
        } label: {
            Label(
                spot.isVisited ? "Visited" : "Mark as Visited",
                systemImage: spot.isVisited ? "checkmark.circle.fill" : "circle"
            )
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .tint(spot.isVisited ? .green : .accentColor)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .sensoryFeedback(.success, trigger: spot.isVisited) { _, visited in visited }
    }
}

// MARK: - Countdown glyph

extension Spot.Countdown {
    /// The symbol that leads the status pill.
    var symbolName: String {
        switch self {
        case .visited: "checkmark.circle.fill"
        case .endsToday, .daysLeft: "hourglass"
        case .startsToday, .startsIn: "calendar"
        case .ended: "xmark.circle"
        case .none: "mappin.and.ellipse"
        }
    }
}

extension Spot {
    /// Checking a spot off stamps the visit; unchecking clears it.
    func toggleVisited(on date: Date = .now) {
        isVisited.toggle()
        visitedAt = isVisited ? date : nil
    }
}

#Preview {
    NavigationStack {
        SpotDetailView(spot: Spot.samples[0])
    }
    .modelContainer(Spot.previewContainer)
}

#Preview("Anytime") {
    NavigationStack {
        SpotDetailView(spot: Spot.samples.first { !$0.hasRun } ?? Spot.samples[0])
    }
    .modelContainer(Spot.previewContainer)
}
