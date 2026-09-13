//
//  SpotListView.swift
//  Monaka
//
//  Everything, in §7.2 order. `This Weekend` here means "last chance" so the
//  three open sections stay distinct — see Spot.WeekendRule.
//

import SwiftUI
import SwiftData

struct SpotListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var spots: [Spot]

    /// Collapsed above this many rows so the Anytime backlog can't bury the
    /// dated spots (§7.3).
    @AppStorage("isAnytimeExpanded") private var isAnytimeExpanded = false

    @State private var today: Date = .now

    private static let anytimeCollapseThreshold = 8

    private var sections: [(section: SpotSection, spots: [Spot])] {
        SpotSection.grouped(spots, on: today, weekend: .lastChance)
    }

    var body: some View {
        NavigationStack {
            Group {
                if spots.isEmpty {
                    ContentUnavailableView(
                        "No Spots Yet",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Places you want to go will show up here.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("All")
            .navigationDestination(for: Spot.self) { spot in
                SpotDetailView(spot: spot)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = .now }
        }
    }

    private var list: some View {
        List {
            ForEach(sections, id: \.section) { section, spots in
                if section == .anytime, spots.count > Self.anytimeCollapseThreshold {
                    Section {
                        DisclosureGroup(isExpanded: $isAnytimeExpanded) {
                            rows(spots)
                        } label: {
                            HStack {
                                Text(section.title)
                                Spacer()
                                Text("\(spots.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Section(section.title) {
                        rows(spots)
                    }
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
}

#Preview {
    SpotListView()
        .modelContainer(Spot.previewContainer)
}
