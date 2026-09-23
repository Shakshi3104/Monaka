//
//  EditSpotView.swift
//  Monaka
//
//  Same form as Add, writing back into an existing spot. Cancel throws the
//  draft away — nothing is written until Save.
//

import SwiftUI
import SwiftData

struct EditSpotView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let spot: Spot

    /// The form is reading a page; Save waits for it.
    @State private var isFormBusy = false
    @State private var form: SpotDraft
    @State private var isConfirmingDiscard = false

    /// What the spot looked like when the sheet opened, so an edited form can
    /// be told from an untouched one.
    private let original: SpotDraft

    init(spot: Spot) {
        self.spot = spot
        let draft = SpotDraft(spot)
        self.original = draft
        _form = State(initialValue: draft)
    }

    private var hasChanges: Bool { form != original }

    var body: some View {
        NavigationStack {
            SpotFormView(draft: $form, isBusy: $isFormBusy)
                .navigationTitle("Edit Spot")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") {
                            if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", systemImage: "checkmark") { save() }
                            .disabled(!form.isSaveable || isFormBusy)
                    }
                }
                .discardChangesGuard(hasChanges: hasChanges, isPresented: $isConfirmingDiscard)
        }
    }

    private func save() {
        form.apply(to: spot)
        // Autosave would get there eventually; this makes the write happen
        // before the sheet goes away.
        try? modelContext.save()
        dismiss()
    }
}

#if DEBUG
#Preview {
    EditSpotView(spot: Spot.samples[0])
        .modelContainer(Spot.previewContainer)
}
#endif
