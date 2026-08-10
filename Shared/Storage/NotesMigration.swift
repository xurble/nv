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

import Foundation

enum NotesMigrationProgressText {
    static let connectingToICloud =
        "Spiral is waiting for iCloud Drive. Your current notes folder will not be changed."

    static let copyingNotes =
        "Spiral is copying and verifying your notes. The original folder will be kept."
}

/// Arbitrates completion between a background operation and a deadline. Only
/// the first result is accepted so a late callback cannot affect later UI.
final class NotesMigrationOperationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<Value, Error>?

    @discardableResult
    func finish(with result: Result<Value, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storedResult == nil else { return false }
        storedResult = result
        return true
    }

    var result: Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }
}

enum NotesFolderClassification: Equatable {
    case empty
    case noteCollection
    case regularFolder
}

enum NotesStartupLocationDecision: Equatable {
    case migrateCurrentLocationToICloud
    case useICloudByDefault
    case offerLegacyNotesImport
}

struct NotesStartupLocationPolicy {
    static func decision(
        preferencesStartupState: SpiralPreferencesStartupState
    ) -> NotesStartupLocationDecision {
        switch preferencesStartupState {
        case .existingSpiralPreferences:
            return .migrateCurrentLocationToICloud
        case .legacyPreferencesFound:
            return .offerLegacyNotesImport
        case .freshInstall:
            return .useICloudByDefault
        }
    }
}

enum NotesDefaultLocationError: LocalizedError, Equatable {
    case destinationContainsUnrelatedData

    var errorDescription: String? {
        switch self {
        case .destinationContainsUnrelatedData:
            return "Spiral Notes in iCloud Drive contains unrelated files and cannot be used as the default notes folder."
        }
    }
}

struct NotesDefaultLocationService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepareDocumentsDirectory(in containerURL: URL) throws -> URL {
        let destinationURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        switch try NotesMigrationService(fileManager: fileManager).classifyFolder(at: destinationURL) {
        case .regularFolder:
            throw NotesDefaultLocationError.destinationContainsUnrelatedData
        case .empty:
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        case .noteCollection:
            break
        }
        return destinationURL
    }
}

enum NotesMigrationError: LocalizedError {
    case sourceDoesNotExist
    case sourceIsNotDirectory
    case destinationContainsData
    case unsupportedItem(String)
    case verificationFailed(String)
    case pendingDifferentMigration

    var errorDescription: String? {
        switch self {
        case .sourceDoesNotExist:
            return "The current notes folder no longer exists."
        case .sourceIsNotDirectory:
            return "The current notes location is not a folder."
        case .destinationContainsData:
            return "Spiral Notes in iCloud Drive already contains files. No files were changed."
        case let .unsupportedItem(path):
            return "The notes folder contains an unsupported item at \(path)."
        case let .verificationFailed(path):
            return "The copy could not be verified at \(path). The original notes were not removed."
        case .pendingDifferentMigration:
            return "Another interrupted notes migration must be resolved before this collection can be copied."
        }
    }
}

enum NotesMigrationCheckpoint: Equatable {
    case stagedAndVerified
    case published
}

enum NotesICloudItemState: Equatable {
    case available
    case unavailable
    case downloadPending
    case concurrentEdit
    case conflict
    case confirmedDeletion
}

enum NotesICloudItemAction: Equatable {
    case read
    case requestDownload
    case waitForDownload
    case preserveBothVersions
    case surfaceConflict
    case recordDeletion
}

/// A characterization boundary for the file states that the future iCloud
/// adapter must report. In particular, absence on disk is never enough to
/// infer deletion.
struct NotesICloudItemPolicy {
    static func action(for state: NotesICloudItemState) -> NotesICloudItemAction {
        switch state {
        case .available:
            return .read
        case .unavailable:
            return .requestDownload
        case .downloadPending:
            return .waitForDownload
        case .concurrentEdit:
            return .preserveBothVersions
        case .conflict:
            return .surfaceConflict
        case .confirmedDeletion:
            return .recordDeletion
        }
    }
}

struct NotesMigrationService {
    private static let ignorableNames: Set<String> = [".DS_Store"]
    private static let collectionMarkerNames: Set<String> = [
        "Notes & Settings",
        "Interim Note-Changes",
        ".spiral-notes"
    ]
    private static let stagingPrefix = ".SpiralNotesMigration-"
    private static let transactionFileName = ".SpiralNotesMigration.transaction.json"

    private let fileManager: FileManager
    private let checkpointHandler: ((NotesMigrationCheckpoint) throws -> Void)?

    init(
        fileManager: FileManager = .default,
        checkpointHandler: ((NotesMigrationCheckpoint) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.checkpointHandler = checkpointHandler
    }

    func containsNotes(at directoryURL: URL) -> Bool {
        guard let contents = try? significantContents(of: directoryURL) else {
            return false
        }
        return !contents.isEmpty
    }

    func classifyFolder(at directoryURL: URL) throws -> NotesFolderClassification {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            return .empty
        }
        guard isDirectory.boolValue else {
            throw NotesMigrationError.sourceIsNotDirectory
        }
        let contents = try significantContents(of: directoryURL)
        guard !contents.isEmpty else { return .empty }

        let names = Set(contents.map(\.lastPathComponent))
        if !names.isDisjoint(with: Self.collectionMarkerNames)
            || names.contains(where: { $0.hasPrefix("Notes & Settings (") }) {
            return .noteCollection
        }

        return .regularFolder
    }

    func sameDirectory(_ firstURL: URL, _ secondURL: URL) -> Bool {
        let first = firstURL.resolvingSymlinksInPath().standardizedFileURL
        let second = secondURL.resolvingSymlinksInPath().standardizedFileURL
        return first == second
    }

    /// Copies a complete note collection through a private staging directory,
    /// verifies every copied item, then publishes it as the container's
    /// Documents directory. The source is never modified by this operation.
    func copyAndVerifyCollection(from sourceURL: URL, to destinationURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw NotesMigrationError.sourceDoesNotExist
        }
        guard isDirectory.boolValue else {
            throw NotesMigrationError.sourceIsNotDirectory
        }
        guard !sameDirectory(sourceURL, destinationURL) else {
            return
        }

        let destinationParent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var migrationError: Error?

        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: .withoutChanges,
            writingItemAt: destinationParent,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedSource, coordinatedParent in
            do {
                let coordinatedDestination = coordinatedParent
                    .appendingPathComponent(destinationURL.lastPathComponent, isDirectory: true)
                try copyAndVerifyWithoutCoordination(
                    from: coordinatedSource,
                    to: coordinatedDestination,
                    stagingParent: coordinatedParent
                )
            } catch {
                migrationError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let migrationError {
            throw migrationError
        }
    }

    private func copyAndVerifyWithoutCoordination(
        from sourceURL: URL,
        to destinationURL: URL,
        stagingParent: URL
    ) throws {
        if try recoverInterruptedMigration(
            from: sourceURL,
            to: destinationURL,
            stagingParent: stagingParent
        ) {
            return
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            guard try significantContents(of: destinationURL).isEmpty else {
                throw NotesMigrationError.destinationContainsData
            }
        } else {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)
        }

        let stagingURL = stagingParent.appendingPathComponent(
            Self.stagingPrefix + UUID().uuidString,
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)

        var transaction = NotesMigrationTransaction(
            sourcePath: sourceURL.standardizedFileURL.path,
            destinationPath: destinationURL.standardizedFileURL.path,
            stagingPath: stagingURL.standardizedFileURL.path,
            phase: .copying
        )
        let transactionURL = stagingParent.appendingPathComponent(Self.transactionFileName)
        try writeTransaction(transaction, to: transactionURL)

        for itemURL in try significantContents(of: sourceURL) {
            try fileManager.copyItem(
                at: itemURL,
                to: stagingURL.appendingPathComponent(itemURL.lastPathComponent)
            )
        }

        try verifyCollection(at: stagingURL, matches: sourceURL)

        transaction.phase = .stagedAndVerified
        try writeTransaction(transaction, to: transactionURL)
        try checkpointHandler?(.stagedAndVerified)

        try fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: stagingURL, to: destinationURL)

        transaction.phase = .published
        try writeTransaction(transaction, to: transactionURL)
        try checkpointHandler?(.published)

        try verifyCollection(at: destinationURL, matches: sourceURL)
        try fileManager.removeItem(at: transactionURL)
    }

    /// Returns true when an interrupted transaction was already complete and
    /// was committed during recovery. Incomplete staging data is discarded and
    /// copied again from the untouched source.
    private func recoverInterruptedMigration(
        from sourceURL: URL,
        to destinationURL: URL,
        stagingParent: URL
    ) throws -> Bool {
        let transactionURL = stagingParent.appendingPathComponent(Self.transactionFileName)
        guard fileManager.fileExists(atPath: transactionURL.path) else { return false }

        let transaction = try JSONDecoder().decode(
            NotesMigrationTransaction.self,
            from: Data(contentsOf: transactionURL)
        )
        guard transaction.sourcePath == sourceURL.standardizedFileURL.path,
              transaction.destinationPath == destinationURL.standardizedFileURL.path else {
            throw NotesMigrationError.pendingDifferentMigration
        }

        let standardizedStagingParent = stagingParent.standardizedFileURL
        let stagingURL = URL(fileURLWithPath: transaction.stagingPath, isDirectory: true).standardizedFileURL
        guard stagingURL.deletingLastPathComponent() == standardizedStagingParent,
              stagingURL.lastPathComponent.hasPrefix(Self.stagingPrefix),
              stagingURL.lastPathComponent.count > Self.stagingPrefix.count else {
            throw NotesMigrationError.pendingDifferentMigration
        }
        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
        let stagingExists = fileManager.fileExists(atPath: stagingURL.path)
        if stagingExists {
            let stagingValues = try stagingURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard stagingValues.isDirectory == true, stagingValues.isSymbolicLink != true else {
                throw NotesMigrationError.pendingDifferentMigration
            }
        }

        switch transaction.phase {
        case .copying:
            if stagingExists { try fileManager.removeItem(at: stagingURL) }
            try fileManager.removeItem(at: transactionURL)
            return false

        case .stagedAndVerified:
            if stagingExists {
                try verifyCollection(at: stagingURL, matches: sourceURL)
                if destinationExists {
                    guard try significantContents(of: destinationURL).isEmpty else {
                        throw NotesMigrationError.destinationContainsData
                    }
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
            } else if !destinationExists {
                try fileManager.removeItem(at: transactionURL)
                return false
            }

        case .published:
            guard destinationExists else {
                try fileManager.removeItem(at: transactionURL)
                return false
            }
        }

        try verifyCollection(at: destinationURL, matches: sourceURL)
        if stagingExists && fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
        try fileManager.removeItem(at: transactionURL)
        return true
    }

    private func writeTransaction(_ transaction: NotesMigrationTransaction, to url: URL) throws {
        let data = try JSONEncoder().encode(transaction)
        try data.write(to: url, options: .atomic)
    }

    private func significantContents(of directoryURL: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ).filter { !Self.ignorableNames.contains($0.lastPathComponent) }
    }

    private func verifyCollection(at copyURL: URL, matches sourceURL: URL) throws {
        let sourcePaths = try relativePaths(in: sourceURL)
        let copiedPaths = try relativePaths(in: copyURL)
        guard sourcePaths == copiedPaths else {
            throw NotesMigrationError.verificationFailed("the collection contents")
        }

        for relativePath in sourcePaths {
            let sourceItem = sourceURL.appendingPathComponent(relativePath)
            let copiedItem = copyURL.appendingPathComponent(relativePath)
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            let sourceValues = try sourceItem.resourceValues(forKeys: keys)
            let copiedValues = try copiedItem.resourceValues(forKeys: keys)

            guard sourceValues.isDirectory == copiedValues.isDirectory,
                  sourceValues.isRegularFile == copiedValues.isRegularFile,
                  sourceValues.isSymbolicLink == copiedValues.isSymbolicLink else {
                throw NotesMigrationError.verificationFailed(relativePath)
            }

            if sourceValues.isRegularFile == true {
                guard sourceValues.fileSize == copiedValues.fileSize,
                      try filesHaveEqualContents(sourceItem, copiedItem) else {
                    throw NotesMigrationError.verificationFailed(relativePath)
                }
            } else if sourceValues.isSymbolicLink == true {
                let sourceTarget = try fileManager.destinationOfSymbolicLink(atPath: sourceItem.path)
                let copiedTarget = try fileManager.destinationOfSymbolicLink(atPath: copiedItem.path)
                guard sourceTarget == copiedTarget else {
                    throw NotesMigrationError.verificationFailed(relativePath)
                }
            } else if sourceValues.isDirectory != true {
                throw NotesMigrationError.unsupportedItem(relativePath)
            }
        }
    }

    private func relativePaths(in rootURL: URL) throws -> [String] {
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            return []
        }

        let rootPath = rootURL.standardizedFileURL.path
        var paths: [String] = []
        for case let itemURL as URL in enumerator {
            let relativePath = String(itemURL.standardizedFileURL.path.dropFirst(rootPath.count + 1))
            if relativePath.split(separator: "/").contains(where: { Self.ignorableNames.contains(String($0)) }) {
                continue
            }
            paths.append(relativePath)
        }
        if let enumerationError {
            throw enumerationError
        }
        return paths.sorted()
    }

    private func filesHaveEqualContents(_ firstURL: URL, _ secondURL: URL) throws -> Bool {
        let firstHandle = try FileHandle(forReadingFrom: firstURL)
        let secondHandle = try FileHandle(forReadingFrom: secondURL)
        defer {
            try? firstHandle.close()
            try? secondHandle.close()
        }

        let chunkSize = 1024 * 1024
        while true {
            let firstChunk = try firstHandle.read(upToCount: chunkSize) ?? Data()
            let secondChunk = try secondHandle.read(upToCount: chunkSize) ?? Data()
            guard firstChunk == secondChunk else { return false }
            if firstChunk.isEmpty { return true }
        }
    }
}

private struct NotesMigrationTransaction: Codable {
    enum Phase: String, Codable {
        case copying
        case stagedAndVerified
        case published
    }

    let sourcePath: String
    let destinationPath: String
    let stagingPath: String
    var phase: Phase
}
