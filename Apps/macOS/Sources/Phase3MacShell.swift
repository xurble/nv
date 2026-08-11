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
    along with Spiral.  If not, see <http://www.gnu.org/licenses/>. */

import AppKit
import SpiralCore
import SpiralFeature
import SwiftUI

/// Shared SwiftUI shell. UI tests pass validated disposable paths; production
/// opens the one coordinated iCloud document store after the legacy controller
/// has finished its guarded copy/conversion handoff.
@objc(SpiralPhase3MacShellController)
final class Phase3MacShellController: NSWindowController {
    private let store: any NoteStore
    private let featureModel: SpiralFeatureModel
    private let reloadStore: @Sendable () async throws -> Void
    private var cloudObserver: CloudCollectionObserver?

    @objc init(documentsPath: String, reconciliationPath: String, indexPath: String) {
        let localStore = LocalNoteStore(
            documentsURL: URL(fileURLWithPath: documentsPath, isDirectory: true),
            reconciliationURL: URL(fileURLWithPath: reconciliationPath, isDirectory: true),
            indexURL: URL(fileURLWithPath: indexPath, isDirectory: false)
        )
        store = localStore
        featureModel = SpiralFeatureModel(store: localStore)
        reloadStore = { try await localStore.reloadFromDisk() }

        let rootView = SpiralCollectionView(
            model: featureModel,
            macEditorFactory: { NVSettingsBridge.newPhase3Editor() }
        )
        let host = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: host)
        window.title = "Spiral Notes"
        window.setContentSize(NSSize(width: 960, height: 640))
        window.minSize = NSSize(width: 640, height: 420)
        super.init(window: window)

        beginLoading()
    }

    private init(
        cloudStore: CloudNoteStore,
        documentsURL: URL
    ) {
        store = cloudStore
        featureModel = SpiralFeatureModel(store: cloudStore)
        reloadStore = { try await cloudStore.reloadFromCloud() }

        let rootView = SpiralCollectionView(
            model: featureModel,
            macEditorFactory: { NVSettingsBridge.newPhase3Editor() }
        )
        let host = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: host)
        window.title = "Spiral Notes"
        window.setContentSize(NSSize(width: 960, height: 640))
        window.minSize = NSSize(width: 640, height: 420)
        super.init(window: window)

        cloudObserver = CloudCollectionObserver(rootURL: documentsURL) { [weak self] in
            self?.refreshFromStore()
        }
        beginLoading()
    }

    /// Returns nil only when the legacy AppKit controller still needs one
    /// guarded launch to copy or convert a local/database-only collection.
    @objc(openSharedICloudStoreIfReadyWithCurrentCollectionPath:)
    @MainActor
    static func openSharedICloudStoreIfReady(
        currentCollectionPath: String?
    ) -> Phase3MacShellController? {
        let identifier = SharedICloudStoreConfiguration.containerIdentifier
        guard let containerURL = UbiquityContainerLocator().containerURL(identifier: identifier)
        else { return nil }

        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        let currentURL = currentCollectionPath.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
        let isCurrentICloudCollection = currentURL == documentsURL.standardizedFileURL
        if let currentURL, !isCurrentICloudCollection, containsCollectionData(at: currentURL) {
            return nil
        }

        do {
            let documents = try FoundationCloudDocumentAdapter(
                rootURL: documentsURL,
                identifier: identifier + "/Documents"
            )
            switch SharedCloudStorePolicy().readiness(for: try documents.listDocuments()) {
            case .ready:
                break
            case let .requiresLegacyMigration(_, canonicalNoteCount):
                guard isCurrentICloudCollection, canonicalNoteCount > 0 else { return nil }
                let backupRoot = try applicationSupportRoot()
                    .appendingPathComponent("Spiral/Retained Legacy Stores", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try LegacyCloudArtifactRetirementService().retire(
                    from: documents,
                    retainedBackupURL: backupRoot
                )
            case .containsUnsupportedData:
                return nil
            }

            let records = try FoundationCloudDocumentAdapter(
                rootURL: containerURL.appendingPathComponent("Data/Reconciliation", isDirectory: true),
                identifier: identifier + "/Data/Reconciliation"
            )
            let indexURL = try applicationSupportRoot()
                .appendingPathComponent("Spiral/SharedCloudStore/Index/notes.json")
            let cloudStore = CloudNoteStore(
                documents: documents,
                reconciliationRecords: records,
                indexURL: indexURL
            )
            return Phase3MacShellController(
                cloudStore: cloudStore,
                documentsURL: documentsURL
            )
        } catch {
            NSLog("Spiral shared iCloud store preflight failed: %@", String(describing: error))
            return nil
        }
    }

    @MainActor
    private func beginLoading() {
        featureModel.setAvailability(.downloading(progress: nil))
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await reloadStore()
                cloudObserver?.start()
                featureModel.setAvailability(.available)
                await featureModel.load()
            } catch {
                featureModel.setAvailability(.unavailable(message: String(describing: error)))
            }
        }
    }

    @MainActor
    private func refreshFromStore() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await reloadStore()
                featureModel.setAvailability(.available)
                await featureModel.load()
            } catch {
                featureModel.setAvailability(.unavailable(message: String(describing: error)))
            }
        }
    }

    private static func containsCollectionData(at url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        return contents.contains { item in
            guard (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return false
            }
            return item.lastPathComponent != ".DS_Store"
        }
    }

    private static func applicationSupportRoot() throws -> URL {
        guard let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
