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

    let spot: Spot

    @State private var form: SpotDraft

    init(spot: Spot) {
        self.spot = spot
        _form = State(initialValue: SpotDraft(spot))
    }

    var body: some View {
        NavigationStack {
            SpotFormView(draft: $form)
                .navigationTitle("Edit Spot")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            form.apply(to: spot)
                            dismiss()
                        }
                        .disabled(!form.isSaveable)
                    }
                }
        }
    }
}

#Preview {
    EditSpotView(spot: Spot.samples[0])
        .modelContainer(Spot.previewContainer)
}
