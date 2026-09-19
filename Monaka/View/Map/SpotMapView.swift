//
//  SpotMapView.swift
//  Monaka
//
//  Every pinned spot, tinted by how much of its run is left. This is the
//  "I'm around here, what did I want to go to" view.
//
//  It never asks for location — that only happens when distance sort is turned
//  on (§7.3, §13-14).
//

import SwiftUI
import SwiftData
import MapKit

struct SpotMapView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var spots: [Spot]

    @AppStorage("mapShowsVisited") private var showsVisited = false
    @AppStorage("mapShowsEnded") private var showsEnded = false
    @AppStorage(TagVocabulary.storageKey) private var vocabularyRaw = ""

    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedSpotID: UUID?
    @State private var isShowingUnpinned = false
    @State private var today: Date = .now

    /// Tokyo, for when there is nothing to frame yet.
    private static let fallbackRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
        latitudinalMeters: 8_000,
        longitudinalMeters: 8_000
    )

    /// Roughly 2 km. `.automatic` frames a single marker at street level,
    /// which tells you nothing about where the spot actually is.
    private static let minimumSpan = 0.02

    private var pinned: [Spot] {
        spots.filter { spot in
            guard spot.hasCoordinate else { return false }
            if spot.isVisited { return showsVisited }
            if spot.hasEnded(on: today) { return showsEnded }
            return true
        }
    }

    /// Shares arrive without coordinates (§8.1) — these are the spots waiting
    /// to be pinned.
    private var unpinned: [Spot] {
        spots.filter { !$0.hasCoordinate }
    }

    private var selected: Spot? {
        pinned.first { $0.id == selectedSpotID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if pinned.isEmpty && unpinned.isEmpty {
                    ContentUnavailableView(
                        "No Locations Yet",
                        systemImage: "map",
                        description: Text("Spots you pin on the map will show up here.")
                    )
                } else {
                    map
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Everything trailing, as on the All tab.
                ToolbarItemGroup(placement: .primaryAction) {
                    if !unpinned.isEmpty {
                        Button {
                            isShowingUnpinned = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.slash")
                                Text("\(unpinned.count)")
                            }
                        }
                        .accessibilityLabel("\(unpinned.count) spots not on the map")
                    }
                    Menu {
                        Toggle("Show Visited", isOn: $showsVisited)
                        Toggle("Show Ended", isOn: $showsEnded)
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .navigationDestination(for: Spot.self) { spot in
                SpotDetailView(spot: spot)
            }
            .sheet(isPresented: $isShowingUnpinned) {
                UnpinnedSpotsView(spots: unpinned, date: today)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = .now }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera, selection: $selectedSpotID) {
            ForEach(pinned) { spot in
                if let coordinate = spot.coordinate {
                    Marker(spot.title, systemImage: icon(for: spot), coordinate: coordinate)
                        .tint(tint(for: spot))
                        .tag(spot.id)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .safeAreaInset(edge: .bottom) {
            if let selected {
                selectionCard(selected)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: selectedSpotID)
        .onAppear {
            camera = .region(Self.region(framing: pinned.compactMap(\.coordinate)))
        }
    }

    /// A tag's own symbol says more than "has a run / doesn't" — a `Ramen` pin
    /// and a `Museum` pin are the whole reason to look at this tab. Visited
    /// keeps its checkmark: there, "been" outranks what kind of place it is.
    private func icon(for spot: Spot) -> String {
        if spot.isVisited { return "checkmark" }
        if let tagged = TagVocabulary.chosenIcon(forLastOf: spot.tags, in: vocabularyRaw) {
            return tagged
        }
        return spot.hasRun ? "ticket.fill" : "cup.and.saucer.fill"
    }

    /// Not quite the row's countdown tint: an Anytime spot has no countdown, so
    /// it would come out `.secondary` — but on a map it's a perfectly good
    /// destination and deserves the accent colour. Only Ended is greyed.
    private func tint(for spot: Spot) -> Color {
        if spot.isVisited { return .green }
        if spot.hasEnded(on: today) { return .secondary }
        return spot.countdown(on: today).emphasis == .soon ? .orange : .accentColor
    }

    /// A region holding every pin, never tighter than `minimumSpan`.
    private static func region(framing coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max()
        else { return fallbackRegion }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.4, minimumSpan),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.4, minimumSpan)
            )
        )
    }

    // MARK: - Selection

    private func selectionCard(_ spot: Spot) -> some View {
        NavigationLink(value: spot) {
            HStack(spacing: 12) {
                SpotThumbnail(spot: spot, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text([spot.venue, spot.hasRun ? spot.runText : nil]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let text = spot.countdown(on: today).text {
                    Text(text)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tint(for: spot))
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            // Without this the `Spacer` in the middle isn't hit-testable, the
            // tap falls through to the Map, and the Map clears its selection —
            // so the card appears to dismiss itself instead of navigating.
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .navigationLinkIndicatorVisibility(.hidden)
        // A floating control over content — the one place glass belongs (§6.2).
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

// MARK: - Unpinned

/// Spots with no coordinate, usually captured through the share sheet. Opening
/// one leads to the detail view, where Edit sets the location.
private struct UnpinnedSpotsView: View {
    @Environment(\.dismiss) private var dismiss

    let spots: [Spot]
    let date: Date

    var body: some View {
        NavigationStack {
            List(spots) { spot in
                NavigationLink(value: spot) {
                    SpotRowView(spot: spot, date: date)
                }
            }
            .navigationTitle("Not on the Map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Spot.self) { spot in
                SpotDetailView(spot: spot)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    SpotMapView()
        .modelContainer(Spot.previewContainer)
}
#endif
