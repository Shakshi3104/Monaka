//
//  IconPickerView.swift
//  Monaka
//
//  A grid of SF Symbols for a tag, grouped the way the tags themselves tend to
//  go. Ported from yomy's IconPickerView; the symbol list is Monaka's, since a
//  tag here names an exhibition, a neighbourhood or a café rather than a
//  news feed.
//

import SwiftUI

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    private struct Group {
        let title: String
        let icons: [String]
    }

    private static let groups: [Group] = [
        Group(title: "Exhibitions", icons: [
            "building.columns", "photo.artframe", "paintpalette", "theatermasks", "ticket",
            "film", "music.note", "books.vertical", "sparkles", "eye"
        ]),
        Group(title: "Food & Drink", icons: [
            "cup.and.saucer", "fork.knife", "wineglass", "birthday.cake", "carrot",
            "takeoutbag.and.cup.and.straw", "mug", "waterbottle"
        ]),
        Group(title: "Places", icons: [
            "mappin.and.ellipse", "building.2", "storefront", "house", "tram",
            "leaf", "tree", "mountain.2", "water.waves", "tent"
        ]),
        Group(title: "Shopping", icons: [
            "bag", "cart", "gift", "tshirt", "camera",
            "book", "handbag", "shippingbox"
        ]),
        Group(title: "When", icons: [
            "calendar", "hourglass", "sun.max", "moon.stars", "snowflake",
            "cloud.sun", "clock", "flame"
        ]),
        Group(title: "Marks", icons: [
            "tag", "bookmark", "star", "heart", "flag",
            "pin", "checkmark.seal", "exclamationmark.triangle"
        ])
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12, pinnedViews: .sectionHeaders) {
                ForEach(Self.groups, id: \.title) { group in
                    Section {
                        ForEach(group.icons, id: \.self) { icon in
                            cell(icon)
                        }
                    } header: {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cell(_ icon: String) -> some View {
        let isSelected = icon == selection
        return Button {
            selection = icon
            dismiss()
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 56, height: 56)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.background),
                    in: .rect(cornerRadius: 12)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var icon = "building.columns"
    return NavigationStack {
        IconPickerView(selection: $icon)
    }
}
