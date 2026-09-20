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

    // Every name here ships in iOS 26 — check `name_availability.plist` in
    // CoreGlyphs before adding one; a symbol from a newer year renders blank.
    private static let groups: [Group] = [
        Group(title: "Exhibitions", icons: [
            "building.columns", "photo.artframe", "paintpalette", "theatermask.and.paintbrush", "ticket",
            "film", "movieclapper", "music.note", "pianokeys", "guitars",
            "books.vertical", "scroll", "fossil.shell", "binoculars", "eye"
        ]),
        Group(title: "Events & Pop-ups", icons: [
            "party.popper", "balloon.2", "fireworks", "sparkles", "megaphone",
            "storefront", "giftcard", "flag.checkered", "trophy", "rosette",
            "gamecontroller", "puzzlepiece", "dice", "crown", "wand.and.stars"
        ]),
        Group(title: "Characters", icons: [
            "teddybear", "pawprint", "cat", "dog", "bird",
            "hare", "tortoise", "fish", "ladybug", "face.smiling",
            "figure.wave", "hands.clap", "star", "heart", "sparkle"
        ]),
        Group(title: "Food & Drink", icons: [
            "cup.and.saucer", "mug", "cup.and.heat.waves", "takeoutbag.and.cup.and.straw", "birthday.cake",
            "popcorn", "fork.knife", "wineglass", "carrot", "waterbottle"
        ]),
        Group(title: "Places", icons: [
            "mappin.and.ellipse", "building.2", "house", "tram", "tent",
            "leaf", "tree", "mountain.2", "water.waves", "beach.umbrella"
        ]),
        Group(title: "Shopping", icons: [
            "bag", "handbag", "cart", "basket", "gift",
            "tshirt", "shoe", "hat.cap", "sunglasses", "eyeglasses",
            "camera", "book", "magazine", "comb", "shippingbox"
        ]),
        Group(title: "When", icons: [
            "calendar", "hourglass", "clock", "sun.max", "moon.stars",
            "sunrise", "sunset", "cloud.sun", "snowflake", "flame"
        ]),
        Group(title: "Marks", icons: [
            "tag", "bookmark", "flag", "pin", "checkmark.seal",
            "exclamationmark.triangle", "infinity", "target"
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
