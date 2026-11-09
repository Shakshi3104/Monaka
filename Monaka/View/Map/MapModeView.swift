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
private struct MapModeThumbnail: View {
    let appearance: MapAppearance

    private static let center = CLLocationCoordinate2D(latitude: 35.6751, longitude: 139.7629)
    private static let meters: CLLocationDistance = 380

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.tertiarySystemFill)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task(id: Key(size: geometry.size, isDark: colorScheme == .dark)) {
                await render(size: geometry.size)
            }
        }
    }

    private var configuration: MKMapConfiguration {
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

    private func render(size: CGSize) async {
        guard size.width > 0, size.height > 0 else { return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: Self.center, latitudinalMeters: Self.meters, longitudinalMeters: Self.meters)
        options.size = size
        options.scale = displayScale
        options.preferredConfiguration = configuration
        options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        // A failed snapshot leaves the grey fill — the label still says which.
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return }
        withAnimation(.easeOut(duration: 0.2)) { image = snapshot.image }
    }

    private struct Key: Equatable {
        var size: CGSize
        var isDark: Bool
    }
}

#Preview {
    @Previewable @State var selection = MapAppearance.transit
    MapModeView(selection: $selection)
}
