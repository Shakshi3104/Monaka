//
//  DebugLaunchArguments.swift
//  Monaka
//
//  Nothing outside the app can tap a tab bar, a row or a toolbar, so the
//  screens past the launch state are unreachable for a `simctl` screenshot.
//  These arguments open them. DEBUG only — see CLAUDE.md §4 for the recipes.
//

#if DEBUG
import Foundation

enum DebugLaunchArgument: String, CaseIterable {
    /// Open straight into a tab.
    case tabMap = "-tab-map"
    case tabAll = "-tab-all"

    /// Present the Add sheet over the Today tab.
    case addSheet = "-add-first"

    /// Push the Today tab's featured spot.
    case detail = "-detail-first"

    /// …and open its Edit sheet. Implies `-detail-first` in practice, since
    /// that is what puts a detail view on screen to open the sheet from.
    case editSheet = "-edit-first"

    /// Open Settings on the All tab, already pushed to Tags.
    case tagsScreen = "-tags-first"
    /// …and one further, to the New Tag screen.
    case newTagScreen = "-new-tag-first"
    /// …and one further still, to its icon grid. Implies `-new-tag-first`.
    case iconPicker = "-icon-picker-first"

    /// Fill the store with `Spot.samples`, additively.
    case seedSamples = "-seed-samples"

    var isSet: Bool {
        ProcessInfo.processInfo.arguments.contains(rawValue)
    }
}
#endif
