//
//  ShareViewController.swift
//  MonakaShare
//
//  Pulls the shared URL or text out of the extension context and hands it to
//  ShareFormView. Nothing is written until the user taps Save.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let root = ShareFormView(
            load: { [weak self] in await self?.loadSharedInput() ?? nil },
            onFinish: { [weak self] in self?.complete() },
            onCancel: { [weak self] in self?.cancel() }
        )

        let hosting = UIHostingController(rootView: root)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    // MARK: - Input

    /// The share sheet hands over a URL, a plain string, or both — Google Maps
    /// sends the short link and the place name as separate items (§8.2).
    private func loadSharedInput() async -> ShareInputResolver.Input? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return .url(url)
            }
        }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return .text(text)
            }
        }

        return nil
    }

    // MARK: - Completion

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }
}
