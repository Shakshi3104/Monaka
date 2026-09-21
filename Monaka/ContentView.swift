//
//  ContentView.swift
//  Monaka
//
//  Root. Two lenses on the same collection plus the list; each tab owns its own
//  NavigationStack. Add sits in the detached capsule at the end of the tab bar
//  and opens a sheet instead of switching tabs.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    enum AppTab: Hashable {
        case today, all, map, add
    }

    /// DEBUG only: nothing outside the app can tap the tab bar, so a launch
    /// argument opens straight into a tab for screenshots (§4).
    @State private var selection: AppTab = {
        #if DEBUG
        if DebugLaunchArgument.tabMap.isSet { return .map }
        // Settings hangs off the All tab, so -settings-first and deeper imply it.
        if DebugLaunchArgument.tabAll.isSet
            || DebugLaunchArgument.settingsSheet.isSet
            || DebugLaunchArgument.tagsScreen.isSet
            || DebugLaunchArgument.newTagScreen.isSet
            || DebugLaunchArgument.iconPicker.isSet { return .all }
        #endif
        return .today
    }()
    @State private var isAddingSpot = {
        #if DEBUG
        DebugLaunchArgument.addSheet.isSet
        #else
        false
        #endif
    }()

    @Environment(AppRouter.self) private var router

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
            // Two roles for one capsule. `.search` was the only trailing-
            // separated slot on iOS 26, so Add borrowed it; iOS 27 gave the
            // separation its own role and draws a borrowed `.search` inline
            // with the rest, which is Add reading as a fourth destination.
            // `.prominent` is what `.search` was being used for all along.
            if #available(iOS 27.0, *) {
                Tab("Add", systemImage: "plus", value: AppTab.add, role: .prominent) {
                    // Never shown: selecting this tab bounces straight back and
                    // presents the sheet below.
                    Color.clear
                }
            } else {
                Tab("Add", systemImage: "plus", value: AppTab.add, role: .search) {
                    Color.clear
                }
            }
        }
        .onChange(of: selection) { previous, current in
            guard current == .add else { return }
            selection = previous == .add ? .today : previous
            isAddingSpot = true
        }
        // A tapped reminder lands on the All tab, which pushes the spot.
        .onChange(of: router.pendingSpotID, initial: true) { _, id in
            if id != nil { selection = .all }
        }
        .sheet(isPresented: $isAddingSpot) {
            AddSpotView()
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
        .modelContainer(Spot.previewContainer)
}
#endif
