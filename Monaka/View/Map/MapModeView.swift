//
//  MapModeView.swift
//  Monaka
//
//  The sheet off the map-mode button: Standard / Transit / Satellite as
//  tiles, the way Maps lays them out. Picking one changes the map behind the
//  sheet straight away; the sheet stays up until it's closed, as in Maps.
//

import SwiftUI
import MapKit

struct MapModeView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: MapAppearance

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 16) {
                ForEach(MapAppearance.allCases) { appearance in
                    tile(appearance)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            .navigationTitle("Map Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(250)])
    }

    private func tile(_ appearance: MapAppearance) -> some View {
        let isSelected = appearance == selection
        return Button {
            selection = appearance
        } label: {
            VStack(spacing: 8) {
                MapModeThumbnail(appearance: appearance)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isSelected ? Color.accentColor : Color(.separator),
                                          lineWidth: isSelected ? 3 : 0.5)
                    }

                Text(appearance.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A picture of what the mode looks like, as Maps' tiles are — not the place
/// you're looking at. It's always the same few blocks by Yurakucho station,
/// close in, so there's a station for Transit to show; anywhere further out,
/// or away from a station, Standard and Transit came out identical.
///
/// A still `MKMapSnapshotter` image rather than three live `Map`s: nothing
/// here pans, and a snapshot carries no Legal link in a 100-point tile.
/// The images come from `MapModeThumbnails`, which the map tab warms up
/// before the sheet is ever opened, so the tiles are there as it slides up.
private struct MapModeThumbnail: View {
    let appearance: MapAppearance

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: UIImage?

    private var key: MapModeThumbnails.Key {
        .init(appearance: appearance, isDark: colorScheme == .dark, scale: displayScale)
    }

    var body: some View {
        // Read straight from the cache, so a warm tile is drawn on the
        // sheet's first frame rather than one frame later from `.task`.
        let image = MapModeThumbnails.shared.image(for: key) ?? loaded
        Color(.tertiarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .task(id: key) {
                guard MapModeThumbnails.shared.image(for: key) == nil else { return }
                let image = await MapModeThumbnails.shared.load(key)
                withAnimation(.easeOut(duration: 0.2)) { loaded = image }
            }
    }
}

/// The three tiles, drawn once per appearance × light/dark × scale and kept
/// for the life of the process. They're always the same place, so there's
/// nothing to invalidate.
///
/// Rendered at one fixed size rather than the tile's measured one: the tile
/// is a few points different while the sheet is still presenting, and
/// following that restarted every snapshot just as it was about to land.
@MainActor
final class MapModeThumbnails {
    static let shared = MapModeThumbnails()

    struct Key: Hashable {
        var appearance: MapAppearance
        var isDark: Bool
        var scale: CGFloat
    }

    /// A touch over the ~107-point tile on a 6.1-inch phone; `scaledToFill`
    /// takes it down from there.
    private static let side: CGFloat = 120
    private static let center = CLLocationCoordinate2D(latitude: 35.6751, longitude: 139.7629)
    private static let meters: CLLocationDistance = 380

    private var images: [Key: UIImage] = [:]
    private var inFlight: [Key: Task<UIImage?, Never>] = [:]

    func image(for key: Key) -> UIImage? { images[key] }

    /// All three for this colour scheme, so opening the sheet costs nothing.
    func prefetch(isDark: Bool, scale: CGFloat) {
        for appearance in MapAppearance.allCases {
            let key = Key(appearance: appearance, isDark: isDark, scale: scale)
            Task { _ = await load(key) }
        }
    }

    /// Shares one snapshot between the prefetch and a sheet that opens
    /// before it lands. A failure isn't kept, so the next open tries again.
    func load(_ key: Key) async -> UIImage? {
        if let image = images[key] { return image }
        if let task = inFlight[key] { return await task.value }
        let task = Task { await Self.render(key) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { images[key] = image }
        return image
    }

    private static func render(_ key: Key) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, latitudinalMeters: meters, longitudinalMeters: meters)
        options.size = CGSize(width: side, height: side)
        options.scale = key.scale
        options.preferredConfiguration = configuration(for: key.appearance)
        options.traitCollection = UITraitCollection(userInterfaceStyle: key.isDark ? .dark : .light)
        // A failed snapshot leaves the grey fill — the label still says which.
        return try? await MKMapSnapshotter(options: options).start().image
    }

    private static func configuration(for appearance: MapAppearance) -> MKMapConfiguration {
        switch appearance {
        case .standard:
            let configuration = MKStandardMapConfiguration()
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        case .transit:
            let configuration = MKStandardMapConfiguration()
            configuration.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
            return configuration
        case .satellite:
            let configuration = MKHybridMapConfiguration()
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        }
    }
}

#Preview {
    @Previewable @State var selection = MapAppearance.transit
    MapModeView(selection: $selection)
}
