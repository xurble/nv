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

import AppKit
import SpiralCore

@objc(SpiralFirstRunMigrationController)
@MainActor
final class SpiralFirstRunMigrationController: NSObject {
    private static let offerVersion = 1
    private static let offerVersionKey = "SpiralICloudMigrationOfferVersion"
    private static let legacyImportOfferVersionKey = "SpiralLegacyNotesImportOfferVersion"
    private static let containerResolutionTimeout: TimeInterval = 15

    @objc(prepareNotesDirectoryAtURL:preferencesStartupState:)
    static func prepareNotesDirectory(
        at currentURL: URL,
        preferencesStartupState: SpiralPreferencesStartupState
    ) -> SpiralPreparedNotesDirectory {
        guard configuredContainerIdentifier != nil else {
            showError(
                title: "iCloud Drive isn’t configured",
                message: "Spiral requires its shared iCloud container and can’t open this build."
            )
            return SpiralPreparedNotesDirectory(directoryURL: currentURL, isUsable: false)
        }

        let decision = NotesStartupLocationPolicy.decision(
            preferencesStartupState: preferencesStartupState
        )

        switch decision {
        case .migrateCurrentLocationToICloud:
            return prepareICloudSwitch(from: currentURL)

        case .useICloudByDefault:
            return prepareNewInstallICloudDefault(fallbackURL: currentURL)

        case .offerLegacyNotesImport:
            return prepareLegacyNotesImport(fallbackURL: currentURL)
        }
    }

    private static func prepareLegacyNotesImport(
        fallbackURL: URL
    ) -> SpiralPreparedNotesDirectory {
        guard let source = SpiralPreferencesMigrationController.detectedLegacySource else {
            return prepareNewInstallICloudDefault(fallbackURL: fallbackURL)
        }

        guard confirmLegacyNotesImport(from: source) else {
            UserDefaults.standard.set(offerVersion, forKey: legacyImportOfferVersionKey)
            return prepareNewInstallICloudDefault(fallbackURL: fallbackURL)
        }

        guard let selectedFolder = selectLegacyNotesFolder(for: source) else {
            return prepareNewInstallICloudDefault(fallbackURL: fallbackURL)
        }

        guard let containerIdentifier = configuredContainerIdentifier,
              let containerURL = resolveContainer(
                identifier: containerIdentifier,
                progressMessage: "Spiral is preparing iCloud Drive for the imported notes."
              ) else {
            showError(
                title: "The notes weren’t imported",
                message: "Spiral couldn’t access its iCloud Drive container. The selected \(source.displayName) folder was not changed."
            )
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL, isUsable: false)
        }

        let destinationURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        let migration = NotesMigrationService()
        do {
            switch try migration.classifyFolder(at: destinationURL) {
            case .empty:
                break
            case .noteCollection:
                showError(
                    title: "Spiral Notes already exist in iCloud Drive",
                    message: "Spiral did not import the selected legacy collection because its iCloud folder already contains notes. The legacy folder was not changed. Spiral will use the existing iCloud collection."
                )
                UserDefaults.standard.set(offerVersion, forKey: legacyImportOfferVersionKey)
                return SpiralPreparedNotesDirectory(
                    directoryURL: destinationURL,
                    marksMigrationOfferHandled: true
                )
            case .regularFolder:
                showError(
                    title: "The notes weren’t imported",
                    message: "Spiral’s iCloud Documents folder contains unrelated files. Nothing was copied and the selected legacy folder was not changed."
                )
                return SpiralPreparedNotesDirectory(directoryURL: fallbackURL, isUsable: false)
            }
        } catch {
            showError(title: "The iCloud folder can’t be inspected", message: error.localizedDescription)
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL, isUsable: false)
        }

        let workingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpiralLegacyImport-\(UUID().uuidString)", isDirectory: true)
        let workingCollection = workingRoot.appendingPathComponent("Collection", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: workingRoot, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: workingRoot) }

            let stageResult: Result<Void, Error> = performWithProgress(
                title: "Preparing \(source.displayName) notes…",
                informativeText: "Spiral is making and verifying a temporary working copy. The original notes will not be changed."
            ) {
                try migration.copyAndVerifyCollection(from: selectedFolder, to: workingCollection)
            }
            try stageResult.get()

            let preparation = try NVLegacyCollectionImporter.prepareWorkingCopy(
                at: workingCollection
            )

            let copyResult: Result<Void, Error> = performWithProgress(
                title: "Copying notes to iCloud Drive…",
                informativeText: "Spiral is copying and verifying \(preparation.noteCount) converted notes. The original legacy folder will be kept."
            ) {
                try migration.copyAndVerifyCollection(from: workingCollection, to: destinationURL)
            }
            try copyResult.get()

            UserDefaults.standard.set(offerVersion, forKey: legacyImportOfferVersionKey)
            NSLog(
                "Spiral imported %lu legacy notes to iCloud using storage format %ld (encrypted source: %@).",
                preparation.noteCount,
                preparation.storageFormat,
                preparation.sourceWasEncrypted ? "yes" : "no"
            )
            return SpiralPreparedNotesDirectory(
                directoryURL: destinationURL,
                marksMigrationOfferHandled: true
            )
        } catch {
            showError(
                title: "The notes weren’t imported",
                message: "\(error.localizedDescription)\n\nThe selected \(source.displayName) folder was not changed."
            )
            return prepareNewInstallICloudDefault(fallbackURL: fallbackURL)
        }
    }

    private static func confirmLegacyNotesImport(from source: LegacyPreferencesSource) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Import your \(source.displayName) notes?"
        alert.informativeText = "Spiral found \(source.displayName) preferences. If you continue, choose its notes folder and Spiral will copy the notes into Spiral Notes in iCloud Drive. The original folder will be kept. Encrypted database notes are decrypted into ordinary TXT, RTF, or HTML files."
        alert.addButton(withTitle: "Import Notes…")
        let defaultsButton = alert.addButton(withTitle: "Don’t Import")
        defaultsButton.keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func selectLegacyNotesFolder(for source: LegacyPreferencesSource) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.title = "Select \(source.displayName) Notes Folder"
        panel.prompt = "Import"
        panel.message = "Choose the folder containing “Notes & Settings” or the separate TXT, RTF, or HTML note files."
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func prepareNewInstallICloudDefault(
        fallbackURL: URL
    ) -> SpiralPreparedNotesDirectory {
        guard let containerIdentifier = configuredContainerIdentifier else {
            showError(
                title: "iCloud Drive isn’t configured",
                message: "Spiral requires its shared iCloud container and can’t open this build."
            )
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL, isUsable: false)
        }

        guard let containerURL = resolveContainer(
            identifier: containerIdentifier,
            progressMessage: "Spiral is preparing your notes folder in iCloud Drive."
        ) else {
            showError(
                title: "iCloud Drive isn’t available",
                message: "Check that you are signed in to iCloud Drive, then reopen Spiral."
            )
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL, isUsable: false)
        }

        let destinationURL: URL
        do {
            destinationURL = try NotesDefaultLocationService()
                .prepareDocumentsDirectory(in: containerURL)
        } catch NotesDefaultLocationError.destinationContainsUnrelatedData {
            showError(
                title: "The iCloud folder can’t be used",
                message: "Spiral Notes in iCloud Drive contains unrelated files and does not look like a Notational Velocity or Spiral collection. Spiral can’t open until the iCloud folder is usable."
            )
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL, isUsable: false)
        } catch {
            showError(title: "The iCloud folder can’t be prepared", message: error.localizedDescription)
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL, isUsable: false)
        }

        return SpiralPreparedNotesDirectory(
            directoryURL: destinationURL,
            marksMigrationOfferHandled: true
        )
    }

    static var configuredContainerIdentifier: String? {
        SharedICloudStoreConfiguration.containerIdentifier
    }

    private static func prepareICloudSwitch(
        from currentURL: URL
    ) -> SpiralPreparedNotesDirectory {
        let migration = NotesMigrationService()

        guard let containerIdentifier = configuredContainerIdentifier else {
            showError(
                title: "iCloud Drive isn’t configured",
                message: "Spiral’s shared iCloud container has not been configured for this build. Spiral can’t open."
            )
            return SpiralPreparedNotesDirectory(directoryURL: currentURL, isUsable: false)
        }

        guard let containerURL = resolveContainer(identifier: containerIdentifier) else {
            showError(
                title: "iCloud Drive isn’t available",
                message: "Check that you are signed in to iCloud Drive, then reopen Spiral."
            )
            return SpiralPreparedNotesDirectory(directoryURL: currentURL, isUsable: false)
        }

        let destinationURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        if migration.sameDirectory(currentURL, destinationURL) {
            UserDefaults.standard.set(offerVersion, forKey: offerVersionKey)
            return SpiralPreparedNotesDirectory(directoryURL: currentURL)
        }

        do {
            switch try migration.classifyFolder(at: destinationURL) {
            case .regularFolder:
                showError(
                    title: "The iCloud folder can’t be used",
                    message: "Spiral Notes in iCloud Drive contains unrelated files and does not look like a Notational Velocity or Spiral collection. No files were changed."
                )
                return SpiralPreparedNotesDirectory(directoryURL: currentURL, isUsable: false)
            case .noteCollection:
                guard SpiralStorageLocationController.confirmMerge(targetURL: destinationURL) else {
                    return SpiralPreparedNotesDirectory(directoryURL: currentURL, isUsable: false)
                }
                return SpiralPreparedNotesDirectory(
                    directoryURL: destinationURL,
                    originalURL: currentURL,
                    requiresMerge: true
                )
            case .empty:
                break
            }
        } catch {
            showError(title: "The iCloud folder can’t be inspected", message: error.localizedDescription)
            return SpiralPreparedNotesDirectory(directoryURL: currentURL, isUsable: false)
        }

        let result: Result<Void, Error> = performWithProgress(
            title: "Copying notes to iCloud Drive…",
            informativeText: NotesMigrationProgressText.copyingNotes
        ) {
            try NotesMigrationService().copyAndVerifyCollection(from: currentURL, to: destinationURL)
        }

        switch result {
        case .failure(let error):
            NSLog("Spiral iCloud notes copy failed: %@", error.localizedDescription)
            showError(
                title: "The notes weren’t copied",
                message: "\(error.localizedDescription)\n\nThe original folder was retained. Reopen Spiral to retry the iCloud copy."
            )
            return SpiralPreparedNotesDirectory(directoryURL: currentURL, isUsable: false)

        case .success:
            return SpiralPreparedNotesDirectory(
                directoryURL: destinationURL,
                originalURL: currentURL,
                createdDestination: true
            )
        }
    }

    /// Commits the migration only after AppController has persisted a usable
    /// alias for the new directory. Until this point the original is untouched.
    @objc(finalizePreparedNotesDirectory:)
    static func finalize(_ prepared: SpiralPreparedNotesDirectory) {
        if prepared.marksMigrationOfferHandled {
            UserDefaults.standard.set(offerVersion, forKey: offerVersionKey)
        }

        guard prepared.originalURL != nil else {
            return
        }

        UserDefaults.standard.set(offerVersion, forKey: offerVersionKey)
    }

    /// Rolls back a prepared copy if the legacy controller cannot represent
    /// its directory. The verified source is still present and unchanged.
    @objc(cancelPreparedNotesDirectory:)
    static func cancel(_ prepared: SpiralPreparedNotesDirectory) {
        guard prepared.originalURL != nil, prepared.createdDestination else { return }
        try? FileManager.default.removeItem(at: prepared.directoryURL)
    }

    private static func resolveContainer(
        identifier: String,
        progressMessage: String = NotesMigrationProgressText.connectingToICloud
    ) -> URL? {
        let result: Result<URL?, Error> = performWithProgress(
            title: "Connecting to iCloud Drive…",
            informativeText: progressMessage,
            timeout: containerResolutionTimeout
        ) {
            FileManager.default.url(forUbiquityContainerIdentifier: identifier)
        }
        switch result {
        case .success(let url):
            if url == nil {
                NSLog("Spiral iCloud container lookup returned no URL for %@", identifier)
            }
            return url
        case .failure(let error):
            NSLog("Spiral iCloud container lookup failed for %@: %@", identifier, error.localizedDescription)
            return nil
        }
    }

    private static func performWithProgress<Value>(
        title: String,
        informativeText: String,
        timeout: TimeInterval? = nil,
        operation: @escaping @Sendable () throws -> Value
    ) -> Result<Value, Error> {
        let gate = NotesMigrationOperationGate<Value>()
        let progressWindow = MigrationProgressWindow.make(
            title: title,
            informativeText: informativeText
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let operationResult = Result { try operation() }
            guard gate.finish(with: operationResult) else { return }
            DispatchQueue.main.async {
                stopModalIfShowing(progressWindow)
            }
        }

        if let timeout {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard gate.finish(with: .failure(NotesMigrationInternalError.iCloudTimedOut)) else {
                    return
                }
                stopModalIfShowing(progressWindow)
            }
        }

        _ = ApplicationModalWindowRunner.run(progressWindow)
        return gate.result ?? .failure(NotesMigrationInternalError.missingResult)
    }

    private static func stopModalIfShowing(_ window: NSWindow) {
        guard NSApp.modalWindow === window else { return }
        NSApp.stopModal(withCode: .OK)
    }

    private static func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@objc(SpiralPreparedNotesDirectory)
final class SpiralPreparedNotesDirectory: NSObject {
    @objc let directoryURL: URL
    @objc let requiresMerge: Bool
    @objc let isUsable: Bool
    fileprivate let originalURL: URL?
    fileprivate let createdDestination: Bool
    fileprivate let marksMigrationOfferHandled: Bool

    init(
        directoryURL: URL,
        originalURL: URL? = nil,
        requiresMerge: Bool = false,
        createdDestination: Bool = false,
        marksMigrationOfferHandled: Bool = false,
        isUsable: Bool = true
    ) {
        self.directoryURL = directoryURL
        self.originalURL = originalURL
        self.requiresMerge = requiresMerge
        self.createdDestination = createdDestination
        self.marksMigrationOfferHandled = marksMigrationOfferHandled
        self.isUsable = isUsable
    }
}

@MainActor
private enum SpiralStorageLocationController {
    static func confirmMerge(targetURL: URL) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Merge with the existing notes collection?"
        alert.informativeText = "This folder already looks like a Notational Velocity or Spiral collection:\n\n\(targetURL.path)\n\nMerge keeps notes from both collections. Divergent versions of the same note are preserved as separate merged copies. The original notes folder is retained until the merged collection is saved successfully."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private enum NotesMigrationInternalError: LocalizedError {
    case missingResult
    case iCloudTimedOut

    var errorDescription: String? {
        switch self {
        case .missingResult:
            return "The migration did not finish."
        case .iCloudTimedOut:
            return "iCloud Drive did not respond within 15 seconds."
        }
    }
}
