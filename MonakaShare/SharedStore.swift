//
//  SharedStore.swift
//  Monaka
//
//  The one SwiftData store, living in the App Group container so the share
//  extension writes into the same file the app reads.
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10) — a synchronized folder can
//  only belong to one target. Edit both copies together; a drift between them
//  is a schema mismatch at runtime, not a compile error.
//

import Foundation
import SwiftData

enum SharedStore {
    enum StoreError: Error, LocalizedError {
        case appGroupUnavailable(String)

        var errorDescription: String? {
            switch self {
            case let .appGroupUnavailable(identifier):
                "The App Group \(identifier) is not available. Check Signing & Capabilities."
            }
        }
    }

    static let appGroupID = "group.com.shakshi.Monaka"
    static let storeName = "Monaka.store"

    /// The shared SQLite file. Both targets open this exact URL.
    static func storeURL() throws -> URL {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            throw StoreError.appGroupUnavailable(appGroupID)
        }
        return container.appending(path: storeName)
    }

    static func makeModelContainer() throws -> ModelContainer {
        let url = try storeURL()
        migrateLegacyStoreIfNeeded(to: url)
        return try ModelContainer(
            for: Spot.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    /// Spots saved before the App Group existed live in the app's own
    /// `default.store`. Move them across once, best effort — a failure here
    /// just means starting empty, never a crash.
    private static func migrateLegacyStoreIfNeeded(to target: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: target.path(percentEncoded: false)) else { return }

        guard let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        let legacy = support.appending(path: "default.store")
        guard fileManager.fileExists(atPath: legacy.path(percentEncoded: false)) else { return }

        // The write-ahead log and shared memory files have to travel with it.
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(filePath: legacy.path(percentEncoded: false) + suffix)
            let to = URL(filePath: target.path(percentEncoded: false) + suffix)
            guard fileManager.fileExists(atPath: from.path(percentEncoded: false)) else { continue }
            try? fileManager.moveItem(at: from, to: to)
        }
    }
}
