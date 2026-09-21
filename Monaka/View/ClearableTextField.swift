//
//  ClearableTextField.swift
//  Monaka
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10) — both forms use it.
//

import SwiftUI

/// A text field with the ⓧ that autofilled text needs: a title pulled from
/// a page is often nearly right, and retyping beats backspacing through it.
/// Same glyph as the image row's remove button, so the form reads as one.
struct ClearableTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    init(_ title: LocalizedStringKey, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(title, text: $text)
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
    }
}
