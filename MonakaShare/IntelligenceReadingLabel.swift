//
//  IntelligenceReadingLabel.swift
//  Monaka
//
//  What a form shows while the on-device model reads a page or a caption
//  (§8.1). Duplicated in MonakaShare/ — the share sheet and the Add form wait
//  on the same model and say so the same way.
//

import SwiftUI

/// Apple Intelligence's own mark, breathing, beside text that shimmers. The
/// mark only ever stands for Apple Intelligence here — `SpotExtractor` is
/// Foundation Models — and its shape and colours are left as they are.
struct IntelligenceReadingLabel: View {
    var text = "Reading it for the name, place and dates…"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "apple.intelligence")
                .symbolRenderingMode(.multicolor)
                .symbolEffect(.breathe)
            Text(text)
                .modifier(Shimmer())
        }
    }
}

/// A band of the label colour sweeping across the text, the way a
/// notification summary shimmers while Apple Intelligence writes it. There is
/// no public API for that one; this is a gradient masked by the text — cheap
/// enough for the extension's memory limit (§13-17b).
private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    let band = geometry.size.width * 0.4
                    LinearGradient(
                        colors: [.clear, Color(.label), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: band)
                    .offset(x: -band + phase * (geometry.size.width + band))
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

#Preview {
    Form {
        Section {
            Text("https://example.jp/exhibition")
        } footer: {
            IntelligenceReadingLabel()
        }
    }
}
