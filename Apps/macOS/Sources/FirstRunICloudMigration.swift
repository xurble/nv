import AppKit
import SwiftUI

@objc(SpiralFirstRunMigrationController)
@MainActor
final class SpiralFirstRunMigrationController: NSObject {
    private static let offerVersion = 1
    private static let offerVersionKey = "SpiralICloudMigrationOfferVersion"
    private static let legacyImportOfferVersionKey = "SpiralLegacyNotesImportOfferVersion"
    private static let containerIdentifierKey = "SpiralICloudContainerIdentifier"
    private static let containerResolutionTimeout: TimeInterval = 15

    @objc(prepareNotesDirectoryAtURL:preferencesStartupState:)
    static func prepareNotesDirectory(
        at currentURL: URL,
        preferencesStartupState: SpiralPreferencesStartupState
    ) -> SpiralPreparedNotesDirectory {
        // A build without an iCloud container (notably Debug) must remain on
        // its configuration-specific local notes directory.
        guard configuredContainerIdentifier != nil else {
            return SpiralPreparedNotesDirectory(directoryURL: currentURL)
        }

        let decision = NotesStartupLocationPolicy.decision(
            preferencesStartupState: preferencesStartupState
        )

        switch decision {
        case .useCurrentLocation:
            return SpiralPreparedNotesDirectory(directoryURL: currentURL)

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
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL)
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
                return SpiralPreparedNotesDirectory(directoryURL: fallbackURL)
            }
        } catch {
            showError(title: "The iCloud folder can’t be inspected", message: error.localizedDescription)
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL)
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
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL)
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
                message: "Spiral will store notes locally until its shared iCloud container is configured."
            )
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL)
        }

        guard let containerURL = resolveContainer(
            identifier: containerIdentifier,
            progressMessage: "Spiral is preparing your notes folder in iCloud Drive."
        ) else {
            showError(
                title: "iCloud Drive isn’t available",
                message: "Check that you are signed in to iCloud Drive. Spiral will store notes locally for now."
            )
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL)
        }

        let destinationURL: URL
        do {
            destinationURL = try NotesDefaultLocationService()
                .prepareDocumentsDirectory(in: containerURL)
        } catch NotesDefaultLocationError.destinationContainsUnrelatedData {
            showError(
                title: "The iCloud folder can’t be used",
                message: "Spiral Notes in iCloud Drive contains unrelated files and does not look like a Notational Velocity or Spiral collection. Spiral will store notes locally for now."
            )
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL)
        } catch {
            showError(title: "The iCloud folder can’t be prepared", message: error.localizedDescription)
            return SpiralPreparedNotesDirectory(directoryURL: fallbackURL)
        }

        return SpiralPreparedNotesDirectory(
            directoryURL: destinationURL,
            marksMigrationOfferHandled: true
        )
    }

    static var configuredContainerIdentifier: String? {
        guard let identifier = Bundle.main.object(
            forInfoDictionaryKey: containerIdentifierKey
        ) as? String, !identifier.isEmpty else {
            return nil
        }
        return identifier
    }

    @objc(prepareICloudSwitchFromURL:)
    static func prepareICloudSwitch(from currentURL: URL) -> SpiralPreparedNotesDirectory {
        let choice = MigrationChoiceWindow.run(currentLocation: currentURL)
        return prepareICloudSwitch(from: currentURL, choice: choice)
    }

    @objc(prepareICloudSwitchFromURL:forWindow:completion:)
    static func prepareICloudSwitch(
        from currentURL: URL,
        for parentWindow: NSWindow,
        completion: @escaping (SpiralPreparedNotesDirectory) -> Void
    ) {
        MigrationChoiceWindow.beginSheet(
            currentLocation: currentURL,
            for: parentWindow
        ) { choice in
            // Let AppKit finish the sheet-ending event before presenting any
            // progress or merge UI required by the selected operation.
            DispatchQueue.main.async {
                completion(prepareICloudSwitch(from: currentURL, choice: choice))
            }
        }
    }

    private static func prepareICloudSwitch(
        from currentURL: URL,
        choice: NotesMigrationChoice
    ) -> SpiralPreparedNotesDirectory {
        let defaults = UserDefaults.standard
        let migration = NotesMigrationService()

        guard choice != .keepCurrentLocation else {
            defaults.set(offerVersion, forKey: offerVersionKey)
            return SpiralPreparedNotesDirectory(directoryURL: currentURL)
        }

        guard let containerIdentifier = configuredContainerIdentifier else {
            showError(
                title: "iCloud Drive isn’t configured",
                message: "Spiral’s shared iCloud container has not been configured for this build. Your notes remain in their current location."
            )
            return SpiralPreparedNotesDirectory(directoryURL: currentURL)
        }

        guard let containerURL = resolveContainer(identifier: containerIdentifier) else {
            showError(
                title: "iCloud Drive isn’t available",
                message: "Check that you are signed in to iCloud Drive and try again. Your notes remain in their current location."
            )
            return SpiralPreparedNotesDirectory(directoryURL: currentURL)
        }

        let destinationURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        if migration.sameDirectory(currentURL, destinationURL) {
            defaults.set(offerVersion, forKey: offerVersionKey)
            return SpiralPreparedNotesDirectory(directoryURL: currentURL)
        }

        do {
            switch try migration.classifyFolder(at: destinationURL) {
            case .regularFolder:
                showError(
                    title: "The iCloud folder can’t be used",
                    message: "Spiral Notes in iCloud Drive contains unrelated files and does not look like a Notational Velocity or Spiral collection. No files were changed."
                )
                return SpiralPreparedNotesDirectory(directoryURL: currentURL)
            case .noteCollection:
                guard SpiralStorageLocationController.confirmMerge(targetURL: destinationURL) else {
                    return SpiralPreparedNotesDirectory(directoryURL: currentURL)
                }
                return SpiralPreparedNotesDirectory(
                    directoryURL: destinationURL,
                    originalURL: currentURL,
                    choice: choice,
                    requiresMerge: true
                )
            case .empty:
                break
            }
        } catch {
            showError(title: "The iCloud folder can’t be inspected", message: error.localizedDescription)
            return SpiralPreparedNotesDirectory(directoryURL: currentURL)
        }

        let result: Result<Void, Error> = performWithProgress(
            title: "Copying notes to iCloud Drive…",
            informativeText: NotesMigrationProgressText.copyingNotes(for: choice)
        ) {
            try NotesMigrationService().copyAndVerifyCollection(from: currentURL, to: destinationURL)
        }

        switch result {
        case .failure(let error):
            NSLog("Spiral iCloud notes copy failed: %@", error.localizedDescription)
            showError(
                title: "The notes weren’t copied",
                message: "\(error.localizedDescription)\n\nSpiral will continue using the current notes folder."
            )
            return SpiralPreparedNotesDirectory(directoryURL: currentURL)

        case .success:
            return SpiralPreparedNotesDirectory(
                directoryURL: destinationURL,
                originalURL: currentURL,
                choice: choice,
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

        guard prepared.originalURL != nil,
              prepared.choice != nil else {
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
    fileprivate let originalURL: URL?
    fileprivate let choice: NotesMigrationChoice?
    fileprivate let createdDestination: Bool
    fileprivate let marksMigrationOfferHandled: Bool

    init(
        directoryURL: URL,
        originalURL: URL? = nil,
        choice: NotesMigrationChoice? = nil,
        requiresMerge: Bool = false,
        createdDestination: Bool = false,
        marksMigrationOfferHandled: Bool = false
    ) {
        self.directoryURL = directoryURL
        self.originalURL = originalURL
        self.choice = choice
        self.requiresMerge = requiresMerge
        self.createdDestination = createdDestination
        self.marksMigrationOfferHandled = marksMigrationOfferHandled
    }
}

@objc(SpiralFolderChangeDecision)
enum SpiralFolderChangeDecision: Int {
    case cancel
    case useEmptyFolder
    case mergeCollection
    case refusedRegularFolder
}

@objc(SpiralStorageLocationController)
@MainActor
final class SpiralStorageLocationController: NSObject {
    @objc(decisionForTargetFolderAtURL:)
    static func decision(forTargetFolderAt targetURL: URL) -> SpiralFolderChangeDecision {
        do {
            switch try NotesMigrationService().classifyFolder(at: targetURL) {
            case .empty:
                return .useEmptyFolder
            case .noteCollection:
                return confirmMerge(targetURL: targetURL) ? .mergeCollection : .cancel
            case .regularFolder:
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "That folder can’t be used"
                alert.informativeText = "The selected folder contains files but does not look like a Notational Velocity or Spiral notes folder. Choose an empty folder or an existing notes collection. No files were changed."
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return .refusedRegularFolder
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "The selected folder can’t be inspected"
            alert.runModal()
            return .cancel
        }
    }

    static func confirmMerge(targetURL: URL) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Merge with the existing notes collection?"
        alert.informativeText = "This folder already looks like a Notational Velocity or Spiral collection:\n\n\(targetURL.path)\n\nMerge keeps notes from both collections. Divergent versions of the same note are preserved as separate merged copies. The original notes folder is retained until the merged collection is saved successfully."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc(isURLInICloud:)
    static func isInICloud(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
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

@MainActor
private enum MigrationChoiceWindow {
    static func run(currentLocation: URL) -> NotesMigrationChoice {
        let window = makeWindow(currentLocation: currentLocation) { choice in
            NSApp.stopModal(withCode: MigrationChoiceModalResponse.response(for: choice))
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = ApplicationModalWindowRunner.run(window)
        return MigrationChoiceModalResponse.choice(for: response)
    }

    static func beginSheet(
        currentLocation: URL,
        for parentWindow: NSWindow,
        completion: @escaping (NotesMigrationChoice) -> Void
    ) {
        let sheetWindow = makeWindow(currentLocation: currentLocation) { selectedChoice in
            guard let attachedSheet = parentWindow.attachedSheet else { return }
            parentWindow.endSheet(
                attachedSheet,
                returnCode: MigrationChoiceModalResponse.response(for: selectedChoice)
            )
        }

        ApplicationSheetWindowPresenter.begin(sheetWindow, for: parentWindow) { response in
            completion(MigrationChoiceModalResponse.choice(for: response))
        }
    }

    private static func makeWindow(
        currentLocation: URL,
        choose: @escaping (NotesMigrationChoice) -> Void
    ) -> NSWindow {
        let rootView = FirstRunICloudMigrationView(
            currentLocation: currentLocation,
            choose: choose
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Copy Notes to iCloud Drive"
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 390))
        return window
    }
}

private struct FirstRunICloudMigrationView: View {
    let currentLocation: URL
    let choose: (NotesMigrationChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 42))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Use Spiral Notes in iCloud Drive?")
                        .font(.title2.weight(.semibold))
                    Text("Spiral found an existing note collection. Using iCloud Drive will make the same collection available to the future iPhone and iPad apps.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupBox("Current notes folder") {
                NotesFolderPathControl(
                    url: currentLocation,
                    accessibilityIdentifier: "icloudMigration.currentFolder"
                )
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Spiral will make and verify a copy in iCloud Drive, then use that copy from then on. The original notes folder will be kept as a backup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Choose Keep Current Location to leave the collection exactly where it is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Keep Current Location") {
                    choose(.keepCurrentLocation)
                }
                Spacer()
                Button("Copy to iCloud") {
                    choose(.copyToICloud)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 390)
    }
}
