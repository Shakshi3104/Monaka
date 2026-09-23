//
//  LocationPickerView.swift
//  Monaka
//
//  Search a place with MKLocalSearch and pin it (§8.1). User-initiated only —
//  this is not the bulk geocoding §3 rules out.
//

import SwiftUI
import MapKit

struct LocationPickerView: View {
    /// Seeded from whatever the form already knows — usually the venue.
    let initialQuery: String
    let current: PickedLocation?
    let onPick: (PickedLocation) -> Void
    /// Closing is the presenter's job, not `@Environment(\.dismiss)`'s. In
    /// the share extension the form is hosted as a *child* view controller,
    /// so a dismiss from inside this sheet walks up and tears down the share
    /// sheet itself — the extension closes and nothing is saved.
    var onClose: () -> Void = {}

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var picked: PickedLocation?
    @State private var camera: MapCameraPosition = .automatic
    @State private var isSearching = false
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                    .frame(height: 220)
                results.isEmpty ? AnyView(placeholder) : AnyView(resultList)
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search for a place")
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        if let picked { onPick(picked) }
                        onClose()
                    }
                    .disabled(picked == nil)
                }
            }
            .task {
                picked = current
                if let current {
                    camera = .region(Self.region(around: current.coordinate))
                }
                query = initialQuery
                if !initialQuery.isEmpty, current == nil {
                    await search()
                }
            }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera) {
            ForEach(results, id: \.self) { item in
                Marker(item.name ?? "", coordinate: item.coordinate)
                    .tint(isPicked(item) ? Color.accentColor : .secondary)
            }
            if let picked, results.isEmpty {
                Marker(picked.name, coordinate: picked.coordinate)
                    .tint(Color.accentColor)
            }
        }
        .mapStyle(.standard)
    }

    // MARK: - Results

    private var resultList: some View {
        List(results, id: \.self) { item in
            Button {
                select(item)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Unnamed place")
                            .foregroundStyle(.primary)
                        if let address = item.formattedAddress {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if isPicked(item) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var placeholder: some View {
        if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if hasSearched {
            ContentUnavailableView.search
        } else {
            ContentUnavailableView(
                "Find the Place",
                systemImage: "mappin.and.ellipse",
                description: Text("Search for the venue or shop to pin it on the map.")
            )
        }
    }

    // MARK: - Search

    private func isPicked(_ item: MKMapItem) -> Bool {
        guard let picked else { return false }
        return item.coordinate.latitude == picked.latitude
            && item.coordinate.longitude == picked.longitude
    }

    private func select(_ item: MKMapItem) {
        let location = PickedLocation(item)
        picked = location
        camera = .region(Self.region(around: location.coordinate))
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            return
        }

        isSearching = true
        defer {
            isSearching = false
            hasSearched = true
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let picked {
            request.region = Self.region(around: picked.coordinate, meters: 20_000)
        }

        // A search that finds nothing is normal, not an error (§13-10).
        guard let response = try? await MKLocalSearch(request: request).start() else {
            results = []
            return
        }
        results = response.mapItems
        if let first = response.mapItems.first {
            camera = .region(Self.region(around: first.coordinate, meters: 2_000))
        }
    }

    private static func region(
        around coordinate: CLLocationCoordinate2D,
        meters: CLLocationDistance = 600
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters)
    }
}

// MARK: - MapKit bridging

extension PickedLocation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ item: MKMapItem) {
        self.init(
            name: item.name ?? "",
            address: item.formattedAddress,
            latitude: item.coordinate.latitude,
            longitude: item.coordinate.longitude
        )
    }
}

extension MKMapItem {
    /// `placemark` is deprecated as of iOS 26 — `location` / `address` replace it.
    var coordinate: CLLocationCoordinate2D { location.coordinate }

    var formattedAddress: String? { address?.fullAddress }
}

#Preview {
    LocationPickerView(initialQuery: "東京都美術館", current: nil) { _ in }
}
