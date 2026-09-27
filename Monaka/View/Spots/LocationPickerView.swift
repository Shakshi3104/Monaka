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
    /// The result's index, as the map reports a tapped marker. Kept in step
    /// with `picked` both ways, so a row tap selects its marker too.
    @State private var selectedIndex: Int?

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
                // Searched even when there's a pin already: a spot pinned
                // from its address (the share sheet does that) is exactly the
                // one you open this to correct, and an empty list gave you
                // nothing to correct it to. The camera stays on the pin.
                if !initialQuery.isEmpty {
                    await search(keepingCamera: current != nil)
                }
            }
        }
    }

    // MARK: - Map

    /// A result can be picked from its marker as well as from the list —
    /// the map is often where you recognise the right branch.
    private var map: some View {
        Map(position: $camera, selection: $selectedIndex) {
            ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                Marker(item.name ?? "", coordinate: item.coordinate)
                    .tint(isPicked(item) ? Color.accentColor : .secondary)
                    .tag(index)
            }
            // The current pin, when no result is it — otherwise opening this
            // on a pinned spot hid where it actually is.
            if let picked, !results.contains(where: isPicked) {
                Marker(picked.name, coordinate: picked.coordinate)
                    .tint(Color.accentColor)
            }
        }
        .mapStyle(.standard)
        .onChange(of: selectedIndex) { _, index in
            // The camera stays put: the marker is already where the finger
            // is, and zooming in would hide the other results around it.
            guard let index, results.indices.contains(index), !isPicked(results[index]) else { return }
            picked = PickedLocation(results[index])
        }
    }

    // MARK: - Results

    private var resultList: some View {
        ScrollViewReader { proxy in
            List(Array(results.enumerated()), id: \.offset) { index, item in
                resultRow(item, at: index)
            }
            .listStyle(.plain)
            // A marker tapped on the map brings its row into view, checkmark
            // and address, so you can see what you picked.
            .onChange(of: selectedIndex) { _, index in
                guard let index else { return }
                withAnimation { proxy.scrollTo(index) }
            }
        }
    }

    private func resultRow(_ item: MKMapItem, at index: Int) -> some View {
        Button {
            select(item, at: index)
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
        .id(index)
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

    /// Within a few tens of metres, not equal: a pin saved earlier and the
    /// same place found again come back a hair apart, and exact equality
    /// drew them as two markers with neither one checked.
    private func isPicked(_ item: MKMapItem) -> Bool {
        guard let picked else { return false }
        let pin = CLLocation(latitude: picked.latitude, longitude: picked.longitude)
        return item.location.distance(from: pin) < Self.samePlaceMeters
    }

    /// 国立新美術館 by name lands 32 m from the address-level pin; a building
    /// is easily that wide.
    private static let samePlaceMeters: CLLocationDistance = 60

    private func select(_ item: MKMapItem, at index: Int) {
        let location = PickedLocation(item)
        picked = location
        selectedIndex = index
        camera = .region(Self.region(around: location.coordinate))
    }

    private func search(keepingCamera: Bool = false) async {
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
        // Indices of the old results mean nothing now.
        selectedIndex = results.firstIndex(where: isPicked)
        if !keepingCamera, let first = response.mapItems.first {
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

#Preview {
    LocationPickerView(initialQuery: "東京都美術館", current: nil) { _ in }
}
