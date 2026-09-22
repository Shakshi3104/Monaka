//
//  AddSpotView.swift
//  Monaka
//
//  The Add form. Every spot gets a location here (§8.1); OGP autofill and the
//  share-sheet routes land on the same SpotDraft in Phase 2.
//

import SwiftUI
import SwiftData

struct AddSpotView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Prefilled by a capture route; empty when typed by hand.
    var draft: SpotDraft = SpotDraft()

    /// The form is reading a page; Save waits for it.
    @State private var isFormBusy = false
    @State private var form = SpotDraft()
    @State private var hasLoadedDraft = false
    @State private var isConfirmingDiscard = false

    /// Anything beyond what the capture route already filled in is the user's
    /// own typing, and worth asking about before it's thrown away.
    private var hasChanges: Bool { form != draft }

    var body: some View {
        NavigationStack {
            SpotFormView(draft: $form, requiresLocation: true, isBusy: $isFormBusy)
                .navigationTitle("New Spot")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!form.isAddable || isFormBusy)
                    }
                }
                .discardChangesGuard(hasChanges: hasChanges, isPresented: $isConfirmingDiscard)
                .onAppear {
                    guard !hasLoadedDraft else { return }
                    hasLoadedDraft = true
                    form = draft
                }
        }
    }

    private func save() {
        modelContext.insert(form.makeSpot())
        dismiss()
    }
}

#if DEBUG
#Preview {
    AddSpotView()
        .modelContainer(Spot.previewContainer)
}
#endif
