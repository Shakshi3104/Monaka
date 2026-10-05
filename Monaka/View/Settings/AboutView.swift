//
//  AboutView.swift
//  Monaka
//
//  The landing page, the privacy policy and the version — the same screen
//  as yomy's About. The two URLs are the ones registered in App Store Connect.
//

import SwiftUI

struct AboutView: View {
    private static let websiteURL = URL(string: "https://shakshi3104.github.io/apps/monaka/")
    private static let privacyURL = URL(string: "https://shakshi3104.github.io/apps/monaka/privacy/")

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            linksSection

            Section {
                VStack(spacing: 4) {
                    Text("Monaka")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(versionText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var linksSection: some View {
        if Self.websiteURL != nil || Self.privacyURL != nil {
            Section {
                if let url = Self.websiteURL {
                    Link(destination: url) {
                        Label("Website", systemImage: "globe")
                    }
                }
                if let url = Self.privacyURL {
                    Link(destination: url) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
