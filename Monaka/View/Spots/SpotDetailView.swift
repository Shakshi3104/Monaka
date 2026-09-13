//
//  SpotDetailView.swift
//  Monaka
//
//  Header image, the run, the map, and the one button that matters: Visited.
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerImage
                header
                if !spot.tags.isEmpty { tags }
                if spot.hasCoordinate { location }
                if let urlString = spot.urlString, let url = URL(string: urlString) { link(url) }
                if let notes = spot.notes { self.notes(notes) }
                visitedButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .navigationTitle(spot.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
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

    @ViewBuilder
    private var headerImage: some View {
        if let imageURL = spot.imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(.tertiarySystemFill)
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(spot.title)
                .font(.title2.weight(.semibold))
                .strikethrough(spot.isVisited, color: .secondary)

            if let venue = spot.venue {
                Text(venue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                pill(spot.runText, tint: .secondary)
                if let text = countdown.text {
                    pill(text, tint: countdown.emphasis.color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: .capsule)
    }

    private var tags: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(spot.tags, id: \.self) { tag in
                    TagChip(tag)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Location

    @ViewBuilder
    private var location: some View {
        if let coordinate = spot.coordinate {
            VStack(alignment: .leading, spacing: 8) {
                SpotMapSnapshot(coordinate: coordinate, title: spot.title)
                    .frame(height: 160)

                if let address = spot.address {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    openInMaps(coordinate)
                } label: {
                    Label("Open in Maps", systemImage: "arrow.triangle.turn.up.right.circle")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    /// The stored `mapURL` wins when there is one — Google Maps claims it as a
    /// universal link when installed, Safari handles it when not (§8.2).
    private func openInMaps(_ coordinate: CLLocationCoordinate2D) {
        if let mapURL = spot.mapURL, let url = URL(string: mapURL) {
            openURL(url)
            return
        }
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "q", value: spot.venue ?? spot.title)
        ]
        if let url = components?.url { openURL(url) }
    }

    // MARK: - Link / notes

    private func link(_ url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Label(url.host() ?? url.absoluteString, systemImage: "link")
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
        }
    }

    private func notes(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(notes)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Visited

    private var visitedButton: some View {
        VStack(spacing: 6) {
            Button {
                spot.toggleVisited()
            } label: {
                Label(
                    spot.isVisited ? "Visited" : "Mark as Visited",
                    systemImage: spot.isVisited ? "checkmark.circle.fill" : "circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(spot.isVisited ? .green : .accentColor)
            .controlSize(.large)

            if let visitedAt = spot.visitedAt, spot.isVisited {
                Text("Visited on \(DateFormatter.monakaDate.string(from: visitedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
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
