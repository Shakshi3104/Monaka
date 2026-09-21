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
    @AppStorage("hidesVisitedSection") private var hidesVisitedSection = false
    @AppStorage("sortsByDistance") private var sortsByDistance = false
    @AppStorage(TagVocabulary.storageKey) private var vocabularyRaw = ""

    @State private var locationProvider = LocationProvider()
    @State private var today: Date = .now
    @State private var selectedTag: String?
    @State private var searchText = ""
    /// §4 — Settings is a sheet off a gear nothing outside the app can tap.
    @State private var isShowingSettings = {
        #if DEBUG
        DebugLaunchArgument.settingsSheet.isSet
            || DebugLaunchArgument.tagsScreen.isSet
            || DebugLaunchArgument.newTagScreen.isSet
            || DebugLaunchArgument.iconPicker.isSet
        #else
        false
        #endif
    }()

    private static let anytimeCollapseThreshold = 8

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !query.isEmpty }

    private var visibleSpots: [Spot] {
        var visible = spots
        if let selectedTag {
            visible = visible.filter { $0.tags.contains(selectedTag) }
        }
        if isSearching {
            visible = visible.filter { $0.matches(query) }
        }
        return visible
    }

    private var allTags: [String] {
        var seen = Set<String>()
        return spots.flatMap(\.tags)
            .filter { seen.insert($0).inserted }
            .sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    private var sections: [(section: SpotSection, spots: [Spot])] {
        // A search is explicit, so it looks past the Hide Ended / Hide
        // Visited toggles — the spot you're typing the name of may well be
        // one you've already been to.
        SpotSection.grouped(visibleSpots, on: today, weekend: .lastChance)
            .filter { isSearching || !(hidesEndedSection && $0.section == .ended) }
            .filter { isSearching || !(hidesVisitedSection && $0.section == .visited) }
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
                // Both on the trailing side, filter first: the Map tab keeps
                // its filter there too, and the leading slot stays free for
                // whatever the nav stack needs.
                ToolbarItemGroup(placement: .primaryAction) {
                    if !allTags.isEmpty {
                        tagFilterMenu
                    }
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
            // A field in the list rather than `.searchable`: with a tab in
            // the bar's search/prominent slot, the system search never
            // appears on this tab in any placement.
            Section {
                searchField
            }
            if isSearching, sections.isEmpty {
                Section {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(sections, id: \.section) { section, spots in
                // A search result hidden behind a disclosure is no result at
                // all, so Anytime stays open while searching.
                if section == .anytime, !isSearching, spots.count > Self.anytimeCollapseThreshold {
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Title, venue or tag", text: $searchText)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
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
