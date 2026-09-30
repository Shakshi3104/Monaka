//
//  SpotMapSnapshot.swift
//  Monaka
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10) — the share sheet shows the
//  place it pinned with the same map the form does.
//

import SwiftUI
import MapKit

/// A still image of the map around one pin.
///
/// An image from `MKMapSnapshotter`, not a live `Map`: this never pans or
/// zooms, and a live map costs ~80 MB. The share extension's limit is around
/// 120 MB, so a spot that got pinned — every café shared from Instagram —
/// killed the extension the moment its map appeared.
///
/// `cornerRadius: 0` lets it sit full-bleed in a grouped list row, where the
/// section already does the clipping.
struct SpotMapSnapshot: View {
    let coordinate: CLLocationCoordinate2D
    let title: String
    var meters: CLLocationDistance = 500
    var cornerRadius: CGFloat = 10

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
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .transition(.opacity)
                }
                pin
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            // Re-rendered when the size, the pin or the appearance changes —
            // a snapshot is a picture of one colour scheme.
            .task(id: SnapshotKey(
                width: geometry.size.width,
                height: geometry.size.height,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                isDark: colorScheme == .dark
            )) {
                await render(size: geometry.size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // Still takes a tap, so a Button wrapping it — the form's "change
        // the pin", the detail view's "open in Maps" — fires.
        .contentShape(.rect)
    }

    /// Drawn over the image at its centre, which is where the snapshot's
    /// region puts the coordinate.
    private var pin: some View {
        VStack(spacing: 2) {
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
                .shadow(radius: 2, y: 1)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
                .frame(maxWidth: 200)
        }
        // Lift it so the circle, not the label, sits on the coordinate.
        .offset(y: 10)
    }

    private func render(size: CGSize) async {
        guard size.width > 0, size.height > 0 else { return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )
        options.size = size
        options.scale = displayScale
        options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        // A failed snapshot leaves the grey fill and the pin — never an error.
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return }
        withAnimation(.easeOut(duration: 0.2)) { image = snapshot.image }
    }

    private struct SnapshotKey: Equatable {
        var width: CGFloat
        var height: CGFloat
        var latitude: Double
        var longitude: Double
        var isDark: Bool
    }
}
