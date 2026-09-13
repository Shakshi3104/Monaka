//
//  ContentView.swift
//  Monaka
//
//  Root. Two lenses on the same collection plus the list; each tab owns its own
//  NavigationStack. Add sits in the detached `.search` slot at the end of the
//  tab bar and opens a sheet instead of switching tabs.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    enum AppTab: Hashable {
        case today, all, map, add
    }

    @State private var selection: AppTab = .today
    @State private var isAddingSpot = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.horizon", value: AppTab.today) {
                TodayView()
            }
            Tab("All", systemImage: "list.bullet", value: AppTab.all) {
                SpotListView()
            }
            Tab("Map", systemImage: "map", value: AppTab.map) {
                SpotMapView()
            }
            Tab("Add", systemImage: "plus", value: AppTab.add, role: .search) {
                // Never shown: selecting this tab bounces straight back and
                // presents the sheet below.
                Color.clear
            }
        }
        .onChange(of: selection) { previous, current in
            guard current == .add else { return }
            selection = previous == .add ? .today : previous
            isAddingSpot = true
        }
        .sheet(isPresented: $isAddingSpot) {
            AddSpotView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(Spot.previewContainer)
}
