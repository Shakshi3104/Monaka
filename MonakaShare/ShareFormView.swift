//
//  ShareFormView.swift
//  MonakaShare
//
//  The share sheet's form. Deliberately smaller than the app's: a share should
//  be two taps. No map picker here — a spot captured this way may arrive
//  without a location, and the app lets you pin it later.
//

import SwiftUI
import SwiftData

struct ShareFormView: View {
    let load: () async -> ShareInputResolver.Input?
    let onFinish: () -> Void
    let onCancel: () -> Void

    @State private var draft = SpotDraft()
    @State private var isResolving = true
    @State private var saveFailed = false

    private var isSaveable: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                    TextField("Venue", text: $draft.venue)
                } footer: {
                    if isResolving {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("Reading the page…")
                        }
                    }
                }

                runSection

                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if draft.location == nil {
                    Section {
                        Label("No location yet — pin it in Monaka later.", systemImage: "mappin.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .environment(\.timeZone, Calendar.monaka.timeZone)
            .navigationTitle("Save to Monaka")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isSaveable || isResolving)
                }
            }
            .alert("Couldn't Save", isPresented: $saveFailed) {
                Button("OK") { onCancel() }
            } message: {
                Text("Monaka's shared store is unavailable.")
            }
            .task {
                defer { isResolving = false }
                guard let input = await load() else { return }
                draft.fillEmptyFields(from: await ShareInputResolver().resolve(input))
            }
        }
    }

    // MARK: - Run

    private var runSection: some View {
        Section {
            Toggle("Start date", isOn: Binding(
                get: { draft.startDate != nil },
                set: { draft.startDate = $0 ? (draft.startDate ?? .now) : nil }
            ))
            if draft.startDate != nil {
                DatePicker(
                    "Starts",
                    selection: Binding(
                        get: { draft.startDate ?? .now },
                        set: { draft.startDate = $0 }
                    ),
                    displayedComponents: .date
                )
            }
            Toggle("End date", isOn: Binding(
                get: { draft.endDate != nil },
                set: { draft.endDate = $0 ? (draft.endDate ?? .now) : nil }
            ))
            if draft.endDate != nil {
                DatePicker(
                    "Ends",
                    selection: Binding(
                        get: { draft.endDate ?? .now },
                        set: { draft.endDate = $0 }
                    ),
                    displayedComponents: .date
                )
            }
        } header: {
            Text("Run")
        } footer: {
            Text("No dates means the spot is always available.")
        }
    }

    // MARK: - Save

    private func save() {
        do {
            let container = try SharedStore.makeModelContainer()
            let context = ModelContext(container)
            context.insert(draft.makeSpot())
            try context.save()
            onFinish()
        } catch {
            saveFailed = true
        }
    }
}

/// `Calendar.monaka` lives in Spot+Period.swift, which is app-only — the
/// extension keeps its own copy of just the pinned calendar (§6.1).
extension Calendar {
    static let monaka: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()
}
