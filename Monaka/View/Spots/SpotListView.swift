//
//  SpotListView.swift
//  Monaka
//
//  Everything, in §7.2 order. `This Weekend` here means "last chance" so the
//  three open sections stay distinct — see Spot.WeekendRule.
//

import SwiftUI
import SwiftData
import CoreLocation

struct SpotListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var spots: [Spot]

    /// Collapsed above this many rows so the Anytime backlog can't bury the
    /// dated spots (§7.3).
    @AppStorage("isAnytimeExpanded") private var isAnytimeExpanded = false
    @AppStorage("hidesEndedSection") private var hidesEndedSection = false
    @AppStorage("sortsByDistance") private var sortsByDistance = false
    @AppStorage(TagVocabulary.storageKey) private var vocabularyRaw = ""

    @State private var locationProvider = LocationProvider()
    @State private var today: Date = .now
    @State private var selectedTag: String?
    /// §4 — Settings is a sheet off a gear nothing outside the app can tap.
    @State private var isShowingSettings = {
        #if DEBUG
        DebugLaunchArgument.tagsScreen.isSet
            || DebugLaunchArgument.newTagScreen.isSet
            || DebugLaunchArgument.iconPicker.isSet
        #else
        false
        #endif
    }()

    private static let anytimeCollapseThreshold = 8

    private var visibleSpots: [Spot] {
        guard let selectedTag else { return spots }
        return spots.filter { $0.tags.contains(selectedTag) }
    }

    private var allTags: [String] {
        var seen = Set<String>()
        return spots.flatMap(\.tags)
            .filter { seen.insert($0).inserted }
            .sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    private var sections: [(section: SpotSection, spots: [Spot])] {
        SpotSection.grouped(visibleSpots, on: today, weekend: .lastChance)
            .filter { !(hidesEndedSection && $0.section == .ended) }
            .map { section, spots in (section, sortedByDistanceIfAsked(spots)) }
    }

    /// Distance reorders **within** each section, not across them — the
    /// sections are about how much run is left, which distance can't replace.
    /// Falls back to the §7.2 order when the toggle is off or there's no fix.
    private func sortedByDistanceIfAsked(_ spots: [Spot]) -> [Spot] {
        guard let location = currentLocation else { return spots }
        return spots.sortedByDistance(from: location)
    }

    private var currentLocation: CLLocation? {
        sortsByDistance ? locationProvider.location : nil
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
            .navigationSubtitle(selectedTag.map { "Tagged \($0)" } ?? "")
            .toolbar {
                if !allTags.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        tagFilterMenu
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gear") {
                        isShowingSettings = true
                    }
                }
            }
            .navigationDestination(for: Spot.self) { spot in
                SpotDetailView(spot: spot)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(locationProvider: locationProvider)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                today = .now
                // Only resumes what the user already opted into.
                if sortsByDistance { locationProvider.start() }
            }
        }
    }

    private var tagFilterMenu: some View {
        Menu {
            Picker("Tag", selection: $selectedTag) {
                Label("All Spots", systemImage: "circle.grid.2x2").tag(String?.none)
                ForEach(allTags, id: \.self) { tag in
                    Label(tag, systemImage: TagVocabulary.icon(for: tag, in: vocabularyRaw))
                        .tag(String?.some(tag))
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: selectedTag == nil ? "tag" : "tag.fill"
            )
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
                SpotRowView(spot: spot, date: today, from: currentLocation)
            }
            .spotSwipeActions(spot, in: modelContext)
        }
    }
}

#if DEBUG
#Preview {
    SpotListView()
        .modelContainer(Spot.previewContainer)
}
#endif
