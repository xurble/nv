/*Copyright (c) 2026 Gareth Simpson and Zachary Schneirov. All rights reserved.
    This file is part of Spiral, a fork of Notational Velocity.

    Spiral is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Spiral is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */

import SpiralCore
import SpiralFeature
import SwiftUI

@main
struct SpiralMobileApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let store: any NoteStore
    private let documentsURL: URL
    private let reloadStore: @Sendable () async throws -> Void
    private let cloudObserver: CloudCollectionObserver?
    @StateObject private var model: SpiralFeatureModel
    @State private var prepared = false

    @MainActor
    init() {
        if ProcessInfo.processInfo.environment["SPIRAL_UI_TEST_MODE"] == "1" {
            let root = Self.uiTestCollectionRoot()
            let documentsURL = root.appendingPathComponent("Documents", isDirectory: true)
            let localStore = LocalNoteStore(
                documentsURL: documentsURL,
                reconciliationURL: root.appendingPathComponent("Reconciliation", isDirectory: true),
                indexURL: root.appendingPathComponent("Index/notes.json", isDirectory: false)
            )
            store = localStore
            self.documentsURL = documentsURL
            reloadStore = { try await localStore.reloadFromDisk() }
            cloudObserver = nil
            _model = StateObject(wrappedValue: SpiralFeatureModel(store: localStore))
            return
        }

        do {
            let identifier = SharedICloudStoreConfiguration.containerIdentifier
            guard let containerURL = UbiquityContainerLocator().containerURL(identifier: identifier) else {
                throw MobileSharedStoreError.containerUnavailable
            }
            let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
            let documents = try FoundationCloudDocumentAdapter(
                rootURL: documentsURL,
                identifier: identifier + "/Documents"
            )
            switch SharedCloudStorePolicy().readiness(for: try documents.listDocuments()) {
            case .ready:
                break
            case .requiresLegacyMigration:
                throw MobileSharedStoreError.finishMigrationOnMac
            case let .containsUnsupportedData(paths):
                throw MobileSharedStoreError.unsupportedPublicData(paths)
            }
            let records = try FoundationCloudDocumentAdapter(
                rootURL: containerURL.appendingPathComponent("Data/Reconciliation", isDirectory: true),
                identifier: identifier + "/Data/Reconciliation"
            )
            let indexURL = Self.applicationSupportRoot()
                .appendingPathComponent("Spiral/SharedCloudStore/Index/notes.json")
            let cloudStore = CloudNoteStore(
                documents: documents,
                reconciliationRecords: records,
                indexURL: indexURL
            )
            let featureModel = SpiralFeatureModel(store: cloudStore)
            store = cloudStore
            self.documentsURL = documentsURL
            reloadStore = { try await cloudStore.reloadFromCloud() }
            cloudObserver = CloudCollectionObserver(rootURL: documentsURL) { [weak featureModel] in
                guard let featureModel else { return }
                Task { @MainActor in
                    do {
                        try await cloudStore.reloadFromCloud()
                        featureModel.setAvailability(.available)
                        await featureModel.load()
                    } catch {
                        featureModel.setAvailability(
                            .unavailable(message: MobileSharedStoreError.message(for: error))
                        )
                    }
                }
            }
            _model = StateObject(wrappedValue: featureModel)
        } catch {
            let unavailable = UnavailableMobileNoteStore(error: error)
            store = unavailable
            documentsURL = Self.applicationSupportRoot()
                .appendingPathComponent("Spiral/Unavailable", isDirectory: true)
            reloadStore = { throw error }
            cloudObserver = nil
            _model = StateObject(wrappedValue: SpiralFeatureModel(store: unavailable))
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if prepared {
                    SpiralCollectionView(model: model)
                } else {
                    ProgressView("Opening collection…")
                        .accessibilityIdentifier("app.preparing")
                }
            }
            .task { await prepare() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, prepared else { return }
                Task { await refreshFromCloud() }
            }
        }
    }

    @MainActor
    private func prepare() async {
        guard !prepared else { return }
        do {
            if ProcessInfo.processInfo.environment["SPIRAL_UI_TEST_MODE"] == "1" {
                try seedUITestFilesIfNeeded()
            }
            try await reloadStore()
            cloudObserver?.start()
            model.setAvailability(.available)
            await model.load()
            prepared = true
        } catch {
            prepared = true
            model.setAvailability(
                .unavailable(message: MobileSharedStoreError.message(for: error))
            )
        }
    }

    @MainActor
    private func refreshFromCloud() async {
        do {
            try await reloadStore()
            model.setAvailability(.available)
            await model.load()
        } catch {
            model.setAvailability(
                .unavailable(message: MobileSharedStoreError.message(for: error))
            )
        }
    }

    private func seedUITestFilesIfNeeded() throws {
        try FileManager.default.createDirectory(
            at: documentsURL,
            withIntermediateDirectories: true
        )
        let welcomeURL = documentsURL.appendingPathComponent("Welcome.txt")
        guard !FileManager.default.fileExists(atPath: welcomeURL.path) else { return }
        try Data("Spiral mobile fixture collection".utf8).write(to: welcomeURL)
        for index in 1...120 {
            try Data("Body for fixture note \(index)".utf8).write(
                to: documentsURL.appendingPathComponent("Fixture Note \(index).txt")
            )
        }
    }

    private static func uiTestCollectionRoot() -> URL {
        let environment = ProcessInfo.processInfo.environment
        let applicationSupport = applicationSupportRoot()
        if environment["SPIRAL_UI_TEST_MODE"] == "1",
           let collectionID = environment["SPIRAL_UI_TEST_COLLECTION_ID"],
           UUID(uuidString: collectionID) != nil {
            return applicationSupport
                .appendingPathComponent("Spiral/Phase3UITests", isDirectory: true)
                .appendingPathComponent(collectionID, isDirectory: true)
        }
        return applicationSupport.appendingPathComponent("Spiral/Phase3Local", isDirectory: true)
    }

    private static func applicationSupportRoot() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
    }
}

private enum MobileSharedStoreError: LocalizedError, Sendable {
    case containerUnavailable
    case finishMigrationOnMac
    case unsupportedPublicData([String])

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "Spiral Notes in iCloud Drive is unavailable. Check iCloud Drive and try again."
        case .finishMigrationOnMac:
            return "Open Spiral on your Mac once to finish converting the legacy collection before using it on iPhone or iPad."
        case let .unsupportedPublicData(paths):
            return "Spiral Notes contains unsupported public data: \(paths.joined(separator: ", "))."
        }
    }

    static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

private struct UnavailableMobileNoteStore: NoteStore, Sendable {
    let error: Error

    func allNotes() async throws -> [Note] { throw error }
    func note(id: NoteID) async throws -> Note? { throw error }
    func create(_ note: Note) async throws -> Note { throw error }
    func update(_ note: Note) async throws { throw error }
    func delete(id: NoteID) async throws { throw error }
    func conflicts() async -> [NoteConflict] { [] }
    func rebuildIndex() async throws { throw error }
}
