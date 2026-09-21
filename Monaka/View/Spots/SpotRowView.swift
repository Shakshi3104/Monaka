//
//  SpotRowView.swift
//  Monaka
//
//  [thumbnail] [title + venue · run] [countdown tag] — CLAUDE.md §6.3
//

import SwiftUI
import SwiftData
import CoreLocation

struct SpotRowView: View {
    let spot: Spot
    var date: Date = .now
    /// Set only while distance sort is on, so the trailing slot can show how
    /// far away an Anytime spot is instead of an empty countdown (§7.3).
    var from: CLLocation?

    private var countdown: Spot.Countdown { spot.countdown(on: date) }

    private var distanceText: String? {
        guard let from, let distance = spot.distance(from: from) else { return nil }
        return distance.formattedDistance
    }

    /// `venue · 04/11 – 06/21`. Falls back to the tags so a bare Anytime
    /// spot doesn't render an empty second line.
    private var subtitle: String? {
        var parts = [spot.venue, spot.hasRun ? spot.compactRunText(on: date) : nil].compactMap { $0 }
        if parts.isEmpty { parts = spot.tags }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            SpotThumbnail(spot: spot)

            VStack(alignment: .leading, spacing: 2) {
                Text(spot.title)
                    .lineLimit(1)
                    .strikethrough(spot.isVisited, color: .secondary)
                    .foregroundStyle(spot.isVisited ? .secondary : .primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Both can show: the countdown says how long you've got, the
            // distance how far it is. Neither replaces the other.
            VStack(alignment: .trailing, spacing: 2) {
                if let text = countdown.text {
                    Text(text)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(countdown.emphasis.color)
                }
                if let distanceText {
                    Text(distanceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Thumbnail

struct SpotThumbnail: View {
    let spot: Spot
    var size: CGFloat = 52

    private var url: URL? {
        guard let imageURL = spot.imageURL else { return nil }
        return URL(string: imageURL)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.tertiarySystemFill))
            .frame(width: size, height: size)
            .overlay {
                if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                } else {
                    Image(systemName: spot.hasRun ? "ticket" : "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Swipe actions

extension View {
    /// Leading: toggle Visited. Trailing: delete, immediately — the deliberate
    /// exception to the confirm-destructive-actions rule (§6.1).
    func spotSwipeActions(_ spot: Spot, in context: ModelContext) -> some View {
        swipeActions(edge: .leading) {
            Button {
                spot.toggleVisited()
            } label: {
                Label(
                    spot.isVisited ? "Not Visited" : "Visited",
                    systemImage: spot.isVisited ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .tint(spot.isVisited ? .gray : .green)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                context.delete(spot)
            }
        }
    }
}

// MARK: - Countdown tint

extension Spot.Countdown.Emphasis {
    /// §6.3 — accent while open, orange when ending soon, green once visited.
    var color: Color {
        switch self {
        case .normal: .accentColor
        case .soon: .orange
        case .done: .green
        case .muted: .secondary
        }
    }
}

#if DEBUG
#Preview {
    List {
        ForEach(Spot.samples) { spot in
            SpotRowView(spot: spot)
        }
    }
}
#endif
