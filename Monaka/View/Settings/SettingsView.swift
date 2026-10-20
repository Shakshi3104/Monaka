//
//  SettingsView.swift
//  Monaka
//
//  A sheet off the gear in the All tab (§6.1): the list's own options, and
//  the app-wide ones (tags, reminders, location) that have no better home,
//  and About.
//  The Map tab's gear opens `MapSettingsView` instead.
//

import SwiftUI
import SwiftData

/// Every screen inside the Settings sheet, addressed by value so a launch
/// argument can open one directly (§4) — and so a widget or notification can
/// later do the same without reaching into view state.
enum SettingsRoute: Hashable {
    case tags
    case newTag
    case renameTag(String)
    case about
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    /// `Ended` is the "missed it" bucket — hideable (§7.2). `Visited` is the
    /// "been there" bucket, and once the list is long it is the same kind of
    /// noise: neither is somewhere you can still go.
    @AppStorage("hidesEndedSection") private var hidesEndedSection = false
    @AppStorage("hidesVisitedSection") private var hidesVisitedSection = false
    @AppStorage("sortsByDistance") private var sortsByDistance = false
    @AppStorage(RunReminder.storageKey) private var remindsBeforeEnd = false
    @AppStorage(RunReminder.leadDaysKey) private var reminderLeadDays = RunReminder.defaultLeadDays
    @AppStorage(RunReminder.minuteOfDayKey) private var reminderMinuteOfDay = RunReminder.defaultMinuteOfDay
    @State private var reminderAccess: RunReminder.Access = .notDetermined

    let locationProvider: LocationProvider

    @State private var path: [SettingsRoute] = {
        #if DEBUG
        if DebugLaunchArgument.newTagScreen.isSet || DebugLaunchArgument.iconPicker.isSet {
            return [.tags, .newTag]
        }
        if DebugLaunchArgument.tagsScreen.isSet { return [.tags] }
        if DebugLaunchArgument.aboutScreen.isSet { return [.about] }
        #endif
        return []
    }()

    /// Off, the footer says what the toggle does; on, what's been set — a
    /// time and a day count only mean something once the rows are there.
    private var reminderSummary: String {
        guard remindsBeforeEnd else {
            return "A notification before a run ends, for spots you haven't visited. You choose how many days before, and when."
        }
        return "A notification at \(RunReminder.timeText(reminderMinuteOfDay)), \(RunReminder.leadText(reminderLeadDays)) before a run ends, for spots you haven't visited."
    }

    /// `reminderMinuteOfDay` as a `Date` for the picker — today at that time
    /// in Asia/Tokyo. Only the hour and minute are read back.
    private var reminderTime: Binding<Date> {
        let calendar = Calendar.monaka
        return Binding {
            calendar.date(
                bySettingHour: reminderMinuteOfDay / 60,
                minute: reminderMinuteOfDay % 60,
                second: 0,
                of: .now
            ) ?? .now
        } set: { date in
            let components = calendar.dateComponents([.hour, .minute], from: date)
            reminderMinuteOfDay = (components.hour ?? 9) * 60 + (components.minute ?? 0)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    NavigationLink(value: SettingsRoute.tags) {
                        Label("Tags", systemImage: "tag")
                    }
                }

                Section {
                    Toggle("Hide Ended Spots", isOn: $hidesEndedSection)
                    Toggle("Hide Visited Spots", isOn: $hidesVisitedSection)
                } header: {
                    Text("All")
                } footer: {
                    Text("Ended holds the runs you missed, Visited the spots you've checked off. Hiding them keeps the All tab to places you can still go.")
                }

                Section {
                    Toggle("Remind Me Before a Run Ends", isOn: $remindsBeforeEnd.animation())
                    // Only while there's a reminder to set — with
                    // notifications denied there is nothing they'd change.
                    if remindsBeforeEnd, reminderAccess != .denied {
                        Picker("Days Before", selection: $reminderLeadDays) {
                            ForEach(RunReminder.leadDayOptions, id: \.self) { days in
                                Text(RunReminder.leadText(days)).tag(days)
                            }
                        }
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                            // The stored minutes are Asia/Tokyo wall-clock
                            // time, so the wheel must be too (§6.1).
                            .environment(\.timeZone, Calendar.monaka.timeZone)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    // Phase 3 — this toggle is the only thing that asks for
                    // notification permission.
                    switch reminderAccess {
                    case .denied:
                        Text("Notifications are off for Monaka in Settings, so no reminder can be sent.")
                    case .notDetermined where !remindsBeforeEnd:
                        Text("\(reminderSummary) Turning this on asks for permission once.")
                    case .notDetermined, .authorized:
                        Text(reminderSummary)
                    }
                }

                Section {
                    Toggle("Sort by Distance", isOn: $sortsByDistance)
                } header: {
                    Text("Location")
                } footer: {
                    // §7.3 — this toggle is the only thing that asks for location.
                    switch locationProvider.access {
                    case .denied:
                        Text("Location is denied in Settings, so the list keeps its usual order.")
                    case .notDetermined:
                        Text("Orders each section nearest first. Turning this on asks for your location once. It's used only for this and to show where you are on the Map.")
                    // Like Reminders: off, say what the toggle would do;
                    // on, say what it's doing.
                    case .authorized where !sortsByDistance:
                        Text("Orders each section nearest first. Sections themselves still go by how much of the run is left.")
                    case .authorized:
                        Text("Each section is ordered nearest first. Sections themselves still go by how much of the run is left.")
                    }
                }

                Section {
                    NavigationLink(value: SettingsRoute.about) {
                        Text("About")
                    }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .tags: TagsView()
                case .newTag: TagEditView()
                case let .renameTag(tag): TagEditView(tag: tag)
                case .about: AboutView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .onChange(of: sortsByDistance) { _, isOn in
                if isOn { locationProvider.start() } else { locationProvider.stop() }
            }
            .task { reminderAccess = await RunReminder.access() }
            .onChange(of: remindsBeforeEnd) { _, isOn in
                guard isOn else { return }
                Task {
                    if reminderAccess == .notDetermined { _ = await RunReminder.requestAccess() }
                    reminderAccess = await RunReminder.access()
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    SettingsView(locationProvider: LocationProvider())
        .modelContainer(Spot.previewContainer)
}
#endif
