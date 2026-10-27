//
//  IconRow.swift
//  Monaka
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10) — both forms use it.
//

import SwiftUI

/// A form row led by a secondary glyph, the way Calendar's event form marks
/// each field — so a row reads at a glance without its placeholder.
/// The separator starts after the glyph, under the text, as it does there.
struct IconRow<Content: View>: View {
    let systemImage: String
    @ViewBuilder var content: Content

    init(_ systemImage: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                content
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
    }
}
