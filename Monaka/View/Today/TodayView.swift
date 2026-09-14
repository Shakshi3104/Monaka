//
//  TodayView.swift
//  Monaka
//
//  Where to go today: one pick at the top, then everything else in §7.2 order.
//

import SwiftUI
import SwiftData

// MARK: - Digest

/// Today's read of the whole collection: the one spot worth leading with,
/// and every spot bucketed into its section.
struct TodayDigest {
    struct Featured {
        enum Kind {
            case goToday      // open right now
            case comingUp     // starts later
            case anytimePick  // no run at all

            var eyebrow: String {
                switch self {
                case .goToday: "Go Today"
                case .comingUp: "Coming Up"
                case .anytimePick: "Anytime Pick"
                }
            }
        }

        let spot: Spot
        let kind: Kind
    }

    /// Today only carries what you could actually go to today. Upcoming,
    /// Anytime, Visited and Ended live in SpotListView.
    static let sections: [SpotSection] = [.thisWeekend, .endingSoon, .openNow]

    let date: Date
    let featured: Featured?
    let sections: [(section: SpotSection, spots: [Spot])]

    /// How many spots are open today. Anytime spots aren't counted — they're
    /// always available, so they say nothing about *today*.
    let openCount: Int

    init(spots: [Spot], on date: Date = .now, calendar: Calendar = .monaka) {
        self.date = date
        // `.intersecting`: anything whose run covers the coming weekend belongs
        // on this screen, even if it runs for another two months.
        self.sections = SpotSection.grouped(
            spots,
            on: date,
            weekend: .intersecting,
            only: Self.sections,
            calendar: calendar
        )

        let candidates = spots.filter { !$0.isVisited }
        let open = candidates.filter { $0.isOpen(on: date, calendar: calendar) }
        self.openCount = open.count

        // Whatever ends first is the thing most likely to be missed.
        if let pick = open.min(by: {
            ($0.daysUntilEnd(on: date, calendar: calendar) ?? .max)
                < ($1.daysUntilEnd(on: date, calendar: calendar) ?? .max)
        }) {
            self.featured = Featured(spot: pick, kind: .goToday)
        } else if let pick = candidates
            .filter({ $0.isUpcoming(on: date, calendar: calendar) })
            .min(by: { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }) {
            self.featured = Featured(spot: pick, kind: .comingUp)
        } else if let pick = candidates.filter({ !$0.hasRun }).max(by: { $0.addedAt < $1.addedAt }) {
            self.featured = Featured(spot: pick, kind: .anytimePick)
        } else {
            self.featured = nil
        }
    }
}

// MARK: - View

struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var spots: [Spot]

    /// Re-read on foreground so the countdowns don't go stale over midnight.
    @State private var today: Date = .now
    @State private var path: [Spot] = []

    private var digest: TodayDigest { TodayDigest(spots: spots, on: today) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if spots.isEmpty {
                    ContentUnavailableView(
                        "No Spots Yet",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Places you want to go will show up here.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Today")
            .navigationSubtitle(subtitle)
            .navigationDestination(for: Spot.self) { spot in
                SpotDetailView(spot: spot)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = .now }
        }
        #if DEBUG
        // §4 — the detail screen can't be reached from the launch state, so a
        // launch argument pushes the featured spot for screenshots.
        .onAppear {
            guard DebugLaunchArgument.detail.isSet || DebugLaunchArgument.editSheet.isSet,
                  path.isEmpty,
                  let spot = digest.featured?.spot
            else { return }
            path = [spot]
        }
        #endif
    }

    private var subtitle: String {
        let day = DateFormatter.monakaDate.string(from: today)
        let weekday = DateFormatter.monakaWeekday.string(from: today)
        return "\(day) \(weekday)"
    }

    private var content: some View {
        List {
            if let featured = digest.featured {
                Section {
                    NavigationLink(value: featured.spot) {
                        FeaturedSpotCard(featured: featured, date: today)
                    }
                    .buttonStyle(.plain)
                    // Zero insets so the card lines up with the section cards
                    // below it, and no chevron eating the trailing edge.
                    .navigationLinkIndicatorVisibility(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    Text(openCountText)
                }
            }

            ForEach(digest.sections, id: \.section) { section, spots in
                Section(section.title) {
                    rows(spots)
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ spots: [Spot]) -> some View {
        ForEach(spots) { spot in
            NavigationLink(value: spot) {
                SpotRowView(spot: spot, date: today)
            }
            .spotSwipeActions(spot, in: modelContext)
        }
    }

    private var openCountText: String {
        switch digest.openCount {
        case 0: "Nothing running today"
        case 1: "1 spot open today"
        case let count: "\(count) spots open today"
        }
    }
}

// MARK: - Featured card

private struct FeaturedSpotCard: View {
    let featured: TodayDigest.Featured
    let date: Date

    private var spot: Spot { featured.spot }
    private var countdown: Spot.Countdown { spot.countdown(on: date) }

    private var imageURL: URL? {
        guard let imageURL = spot.imageURL else { return nil }
        return URL(string: imageURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color(.tertiarySystemFill)
                }
                .frame(height: 150)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(featured.kind.eyebrow)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.accentColor)

                Text(spot.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let venue = spot.venue {
                    Text(venue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if spot.hasRun {
                        Text(spot.runText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let text = countdown.text {
                        Text(text)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(countdown.emphasis.color)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    TodayView()
        .modelContainer(Spot.previewContainer)
}

#Preview("Empty") {
    TodayView()
        .modelContainer(for: Spot.self, inMemory: true)
}
