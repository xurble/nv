import Foundation

public enum LegacyMigrationError: Error, Equatable, Sendable {
    case plaintextConfirmationRequired
    case backupAlreadyExists
    case backupVerificationFailed
    case sourceChangedDuringMigration
    case destinationContainsData
    case unsafeDestination
}

public struct LegacyMigrationResult: Sendable {
    public let store: LocalNoteStore
    public let importedNoteCount: Int
    public let sourceFingerprint: LegacyCollectionFingerprint
    public let retainedBackupURL: URL
    public let recoveredWAL: Bool
}

public struct LegacyMigrationDestination: Sendable {
    public let documentsURL: URL
    public let reconciliationURL: URL
    public let indexURL: URL
    public let retainedBackupURL: URL

    public init(
        documentsURL: URL,
        reconciliationURL: URL,
        indexURL: URL,
        retainedBackupURL: URL
    ) {
        self.documentsURL = documentsURL
        self.reconciliationURL = reconciliationURL
        self.indexURL = indexURL
        self.retainedBackupURL = retainedBackupURL
    }
}

public struct LegacyMigrationService: Sendable {
    public init() {}

    /// Imports from an untouched source and retains a byte-verified backup.
    /// The legacy store is never made an active writer after this returns.
    public func migrate(
        source: some LegacyCompatibilitySource,
        to destination: LegacyMigrationDestination,
        confirmsPlaintextDestination: Bool
    ) async throws -> LegacyMigrationResult {
        if source.protection == .legacyApplicationEncryption, !confirmsPlaintextDestination {
            throw LegacyMigrationError.plaintextConfirmationRequired
        }
        try validate(source: source.collectionURL, destination: destination)
        try requireEmpty(destination.documentsURL)
        try requireEmpty(destination.reconciliationURL)
        if FileManager.default.fileExists(atPath: destination.indexURL.path) {
            throw LegacyMigrationError.destinationContainsData
        }

        let before = try LegacyCollectionVerifier.fingerprint(at: source.collectionURL)
        try LegacyCollectionVerifier.copyAndVerify(
            from: source.collectionURL,
            to: destination.retainedBackupURL
        )

        let workingCopyURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SpiralLegacyMigration-\(UUID().uuidString)",
            isDirectory: true
        )
        try LegacyCollectionVerifier.copyAndVerify(
            from: destination.retainedBackupURL,
            to: workingCopyURL
        )
        defer { try? FileManager.default.removeItem(at: workingCopyURL) }

        let snapshot: LegacyCollectionSnapshot
        do {
            snapshot = try source.loadSnapshot(from: workingCopyURL)
        } catch {
            throw error
        }
        guard !snapshot.notes.isEmpty else { throw LegacyCompatibilityError.noNotes }

        let store = try await LocalNoteStore.open(
            documentsURL: destination.documentsURL,
            reconciliationURL: destination.reconciliationURL,
            indexURL: destination.indexURL
        )
        do {
            for legacy in snapshot.notes {
                let note = Note(
                    title: legacy.title,
                    content: legacy.content,
                    tags: legacy.tags,
                    legacyMetadata: legacy.legacyMetadata,
                    folder: legacy.folder,
                    createdAt: legacy.createdAt,
                    modifiedAt: legacy.modifiedAt,
                    isPinned: legacy.isPinned,
                    isPrivate: legacy.isPrivate
                )
                _ = try await store.create(note)
            }
            let after = try LegacyCollectionVerifier.fingerprint(at: source.collectionURL)
            guard before == after else {
                try rollbackCreatedDestination(destination)
                throw LegacyMigrationError.sourceChangedDuringMigration
            }
            return LegacyMigrationResult(
                store: store,
                importedNoteCount: snapshot.notes.count,
                sourceFingerprint: before,
                retainedBackupURL: destination.retainedBackupURL,
                recoveredWAL: snapshot.recoveredWAL
            )
        } catch {
            try rollbackCreatedDestination(destination)
            throw error
        }
    }

    private func requireEmpty(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty else {
            throw LegacyMigrationError.destinationContainsData
        }
    }

    private func validate(source: URL, destination: LegacyMigrationDestination) throws {
        let source = source.standardizedFileURL
        let targets = [
            destination.documentsURL,
            destination.reconciliationURL,
            destination.indexURL,
            destination.retainedBackupURL
        ].map(\.standardizedFileURL)
        guard source.path != "/",
              targets.allSatisfy({ $0.path != "/" && $0 != source && !$0.path.hasPrefix(source.path + "/") }),
              Set(targets.map(\.path)).count == targets.count else {
            throw LegacyMigrationError.unsafeDestination
        }
    }

    private func rollbackCreatedDestination(_ destination: LegacyMigrationDestination) throws {
        for url in [destination.documentsURL, destination.reconciliationURL, destination.indexURL] {
            let path = url.standardizedFileURL.path
            guard path != "/", !path.isEmpty else { throw LegacyMigrationError.unsafeDestination }
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}
