//
//  SpotMapView.swift
//  Monaka
//
//  Every pinned spot, tinted by how much of its run is left. This is the
//  "I'm around here, what did I want to go to" view.
//
//  It never asks for location — that only happens when distance sort is turned
//  on (§7.3, §13-14). Once that's been granted, though, the map shows where
//  you are and can centre on it; reading the authorization status prompts
//  nothing.
//

import SwiftUI
import SwiftData
import MapKit

struct SpotMapView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var spots: [Spot]

    /// Both live in Settings → Map; the toolbar is for the tag filter.
    @AppStorage("mapShowsVisited") private var showsVisited = false
    @AppStorage("mapShowsEnded") private var showsEnded = false
    @AppStorage(TagVocabulary.storageKey) private var vocabularyRaw = ""

    @State private var selectedTag: String?

    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedSpotID: UUID?
    @State private var isShowingUnpinned = false
    @State private var isShowingSettings = false
    @State private var today: Date = .now
    /// Read, never requested. `MapUserLocationButton` asks for permission
    /// when tapped, so it only exists once permission is already there.
    @State private var isLocationAuthorized = false

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
            if let selectedTag, !spot.tags.contains(selectedTag) { return false }
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
            .navigationSubtitle(selectedTag.map { "Tagged \($0)" } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Trailing is the same pair as the All tab — filter, then
                // this tab's own settings. The unpinned count is a status,
                // not a control over the map, so it sits on its own, leading.
                if !unpinned.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
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
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if !spots.tagsInUse.isEmpty {
                        TagFilterMenu(tags: spots.tagsInUse, selection: $selectedTag)
                    }
                    Button("Map Settings", systemImage: "gear") {
                        isShowingSettings = true
                    }
                }
            }
            .navigationDestination(for: Spot.self) { spot in
                SpotDetailView(spot: spot)
            }
            .sheet(isPresented: $isShowingUnpinned) {
                UnpinnedSpotsView(spots: unpinned, date: today)
            }
            .sheet(isPresented: $isShowingSettings) {
                MapSettingsView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                today = .now
                refreshLocationAccess()
            }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera, selection: $selectedSpotID) {
            if isLocationAuthorized {
                UserAnnotation()
            }
            ForEach(pinned) { spot in
                if let coordinate = spot.coordinate {
                    Marker(spot.title, systemImage: icon(for: spot), coordinate: coordinate)
                        .tint(tint(for: spot))
                        .tag(spot.id)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            if isLocationAuthorized {
                MapUserLocationButton()
            }
        }
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
            refreshLocationAccess()
            frameAllPins()
        }
        // A filter can leave only pins that are off screen, which reads as
        // "nothing matched". Only the filters reframe — an edit or a check-off
        // shouldn't throw away wherever the user has panned to.
        .onChange(of: selectedTag) { frameAllPins(animated: true) }
        .onChange(of: showsVisited) { frameAllPins(animated: true) }
        .onChange(of: showsEnded) { frameAllPins(animated: true) }
    }

    private func frameAllPins(animated: Bool = false) {
        let region = MapCameraPosition.region(Self.region(framing: pinned.compactMap(\.coordinate)))
        if animated {
            withAnimation { camera = region }
        } else {
            camera = region
        }
    }

    /// Permission can change in Settings while the app is away, or by turning
    /// distance sort on — re-read whenever the tab comes back.
    private func refreshLocationAccess() {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: isLocationAuthorized = true
        default: isLocationAuthorized = false
        }
    }

    /// A tag's own symbol says more than "has a run / doesn't" — a `Ramen` pin
    /// and a `Museum` pin are the whole reason to look at this tab. Visited
    /// keeps its checkmark: there, "been" outranks what kind of place it is.
    private func icon(for spot: Spot) -> String {
        spot.isVisited ? "checkmark" : spot.symbolName(vocabulary: vocabularyRaw)
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
                    Text([spot.venue, spot.hasRun ? spot.compactRunText(on: today) : nil]
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
                    Button("Done", systemImage: "checkmark") { dismiss() }
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
