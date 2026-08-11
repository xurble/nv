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

import Foundation

public enum CloudMigrationNamespace: String, Codable, Equatable, Sendable {
    case documents
    case reconciliationRecords
}

public enum CloudMigrationPhase: String, Codable, Equatable, Sendable {
    case backupVerified
    case publishing
    case published
    case committed
    case rollingBack
}

public struct CloudMigrationJournalItem: Codable, Hashable, Sendable {
    public let namespace: CloudMigrationNamespace
    public let relativePath: String
    public let contentHash: String

    public init(namespace: CloudMigrationNamespace, relativePath: String, contentHash: String) {
        self.namespace = namespace
        self.relativePath = relativePath
        self.contentHash = contentHash
    }
}

public struct CloudMigrationJournal: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let transactionID: UUID
    public let sourceDocumentsPath: String
    public let sourceRecordsPath: String
    public let destinationDocumentsIdentifier: String
    public let destinationRecordsIdentifier: String
    public let retainedBackupPath: String
    public let items: [CloudMigrationJournalItem]
    public var publishedItems: [CloudMigrationJournalItem]
    public var phase: CloudMigrationPhase

    public init(
        transactionID: UUID = UUID(),
        sourceDocumentsPath: String,
        sourceRecordsPath: String,
        destinationDocumentsIdentifier: String,
        destinationRecordsIdentifier: String,
        retainedBackupPath: String,
        items: [CloudMigrationJournalItem],
        publishedItems: [CloudMigrationJournalItem] = [],
        phase: CloudMigrationPhase
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.transactionID = transactionID
        self.sourceDocumentsPath = sourceDocumentsPath
        self.sourceRecordsPath = sourceRecordsPath
        self.destinationDocumentsIdentifier = destinationDocumentsIdentifier
        self.destinationRecordsIdentifier = destinationRecordsIdentifier
        self.retainedBackupPath = retainedBackupPath
        self.items = items
        self.publishedItems = publishedItems
        self.phase = phase
    }
}

public enum CloudMigrationCheckpoint: Equatable, Sendable {
    case backupVerified
    case publishedItem(CloudMigrationNamespace, String, Int)
    case published
    case committed
    case rollingBack
}

public enum CloudCollectionMigrationError: Error, Equatable, Sendable {
    case unsafePath(String)
    case sourceMissing(String)
    case sourceContainsNoNotes
    case sourceReconciliationMismatch(String)
    case destinationContainsData
    case backupAlreadyExists
    case journalDoesNotMatch
    case unsupportedJournalSchema(Int)
    case sourceChanged(String)
    case backupVerificationFailed(String)
    case publicationVerificationFailed(String)
    case destinationChangedDuringRollback(String)
    case injectedFailure(CloudMigrationCheckpoint)
}

public struct CloudCollectionMigrationResult: Equatable, Sendable {
    public let transactionID: UUID
    public let publishedItemCount: Int
    public let retainedBackupURL: URL
    public let journalURL: URL

    public init(
        transactionID: UUID,
        publishedItemCount: Int,
        retainedBackupURL: URL,
        journalURL: URL
    ) {
        self.transactionID = transactionID
        self.publishedItemCount = publishedItemCount
        self.retainedBackupURL = retainedBackupURL
        self.journalURL = journalURL
    }
}

/// Copy-only publication of clean note files plus private reconciliation
/// records. The journal is atomically rewritten after every item so an
/// interrupted migration can resume or remove only its own verified writes.
public struct CloudCollectionMigrationService: @unchecked Sendable {
    public typealias CheckpointHandler = @Sendable (CloudMigrationCheckpoint) throws -> Void

    private let fileManager: FileManager
    private let checkpointHandler: CheckpointHandler?

    public init(
        fileManager: FileManager = .default,
        checkpointHandler: CheckpointHandler? = nil
    ) {
        self.fileManager = fileManager
        self.checkpointHandler = checkpointHandler
    }

    public func migrate(
        sourceDocumentsURL: URL,
        sourceReconciliationURL: URL,
        destinationDocuments: any CloudDocumentAccess,
        destinationReconciliationRecords: any CloudDocumentAccess,
        retainedBackupURL: URL,
        journalURL: URL
    ) throws -> CloudCollectionMigrationResult {
        let sourceDocuments = sourceDocumentsURL.standardizedFileURL
        let sourceRecords = sourceReconciliationURL.standardizedFileURL
        let backup = retainedBackupURL.standardizedFileURL
        let journalFile = journalURL.standardizedFileURL
        try validatePaths(
            sourceDocuments: sourceDocuments,
            sourceRecords: sourceRecords,
            backup: backup,
            journal: journalFile
        )

        let sourceItems = try loadSourceItems(documents: sourceDocuments, records: sourceRecords)
        var journal: CloudMigrationJournal
        if fileManager.fileExists(atPath: journalFile.path) {
            journal = try loadJournal(at: journalFile)
            try validate(
                journal,
                sourceDocuments: sourceDocuments,
                sourceRecords: sourceRecords,
                destinationDocuments: destinationDocuments,
                destinationRecords: destinationReconciliationRecords,
                backup: backup,
                sourceItems: sourceItems
            )
            try verifyBackup(journal: journal, sourceItems: sourceItems)
            guard journal.phase != .rollingBack else {
                throw CloudCollectionMigrationError.journalDoesNotMatch
            }
        } else {
            guard try destinationDocuments.listDocuments().isEmpty,
                  try destinationReconciliationRecords.listDocuments().isEmpty else {
                throw CloudCollectionMigrationError.destinationContainsData
            }
            guard !fileManager.fileExists(atPath: backup.path) else {
                throw CloudCollectionMigrationError.backupAlreadyExists
            }
            try createBackup(at: backup, sourceItems: sourceItems)
            journal = CloudMigrationJournal(
                sourceDocumentsPath: sourceDocuments.path,
                sourceRecordsPath: sourceRecords.path,
                destinationDocumentsIdentifier: destinationDocuments.identifier,
                destinationRecordsIdentifier: destinationReconciliationRecords.identifier,
                retainedBackupPath: backup.path,
                items: sourceItems.map(\.journalItem),
                phase: .backupVerified
            )
            try write(journal, to: journalFile)
            try checkpointHandler?(.backupVerified)
        }

        if journal.phase == .committed {
            try verifyPublished(
                journal: journal,
                destinationDocuments: destinationDocuments,
                destinationRecords: destinationReconciliationRecords
            )
            return result(for: journal, journalURL: journalFile)
        }

        journal.phase = .publishing
        try write(journal, to: journalFile)
        let published = Set(journal.publishedItems)
        for (index, item) in sourceItems.enumerated() where !published.contains(item.journalItem) {
            let destination = adapter(
                for: item.namespace,
                documents: destinationDocuments,
                records: destinationReconciliationRecords
            )
            try destination.write(item.data, relativePath: item.relativePath)
            let written = try destination.read(relativePath: item.relativePath)
            guard ContentHash.sha256(written) == item.contentHash else {
                throw CloudCollectionMigrationError.publicationVerificationFailed(item.relativePath)
            }
            journal.publishedItems.append(item.journalItem)
            try write(journal, to: journalFile)
            try checkpointHandler?(.publishedItem(item.namespace, item.relativePath, index))
        }

        journal.phase = .published
        try write(journal, to: journalFile)
        try verifyPublished(
            journal: journal,
            destinationDocuments: destinationDocuments,
            destinationRecords: destinationReconciliationRecords
        )
        try checkpointHandler?(.published)

        journal.phase = .committed
        try write(journal, to: journalFile)
        try checkpointHandler?(.committed)
        return result(for: journal, journalURL: journalFile)
    }

    /// Rolls back only paths listed in a matching journal and only while their
    /// hashes still match this transaction. External changes are never erased.
    public func rollback(
        journalURL: URL,
        destinationDocuments: any CloudDocumentAccess,
        destinationReconciliationRecords: any CloudDocumentAccess
    ) throws {
        let journalFile = journalURL.standardizedFileURL
        var journal = try loadJournal(at: journalFile)
        guard journal.destinationDocumentsIdentifier == destinationDocuments.identifier,
              journal.destinationRecordsIdentifier == destinationReconciliationRecords.identifier else {
            throw CloudCollectionMigrationError.journalDoesNotMatch
        }
        journal.phase = .rollingBack
        try write(journal, to: journalFile)
        try checkpointHandler?(.rollingBack)

        for item in journal.publishedItems {
            let destination = adapter(
                for: item.namespace,
                documents: destinationDocuments,
                records: destinationReconciliationRecords
            )
            let snapshots = try destination.listDocuments()
            guard snapshots.contains(where: { $0.relativePath == item.relativePath }) else { continue }
            let data = try destination.read(relativePath: item.relativePath)
            guard ContentHash.sha256(data) == item.contentHash else {
                throw CloudCollectionMigrationError.destinationChangedDuringRollback(item.relativePath)
            }
        }
        for item in journal.publishedItems.reversed() {
            let destination = adapter(
                for: item.namespace,
                documents: destinationDocuments,
                records: destinationReconciliationRecords
            )
            let snapshots = try destination.listDocuments()
            guard snapshots.contains(where: { $0.relativePath == item.relativePath }) else { continue }
            try destination.delete(relativePath: item.relativePath)
        }
        try fileManager.removeItem(at: journalFile)
    }

    public func loadJournal(at url: URL) throws -> CloudMigrationJournal {
        let journal = try Self.decoder.decode(
            CloudMigrationJournal.self,
            from: Data(contentsOf: url)
        )
        guard journal.schemaVersion == CloudMigrationJournal.currentSchemaVersion else {
            throw CloudCollectionMigrationError.unsupportedJournalSchema(journal.schemaVersion)
        }
        return journal
    }

    private func loadSourceItems(
        documents: URL,
        records: URL
    ) throws -> [SourceItem] {
        let documentItems = try sourceItems(at: documents, namespace: .documents) { url in
            NoteFormat.format(forPathExtension: url.pathExtension) != nil
        }
        let recordItems = try sourceItems(at: records, namespace: .reconciliationRecords) { url in
            url.pathExtension.lowercased() == "json"
        }
        guard !documentItems.isEmpty else {
            throw CloudCollectionMigrationError.sourceContainsNoNotes
        }
        try verifyReconciliation(documentItems: documentItems, recordItems: recordItems)
        return (documentItems + recordItems).sorted {
            if $0.namespace.rawValue != $1.namespace.rawValue {
                return $0.namespace.rawValue < $1.namespace.rawValue
            }
            return $0.relativePath < $1.relativePath
        }
    }

    private func verifyReconciliation(
        documentItems: [SourceItem],
        recordItems: [SourceItem]
    ) throws {
        let documentsByPath = Dictionary(
            uniqueKeysWithValues: documentItems.map { ($0.relativePath, $0.contentHash) }
        )
        var activePaths: [String: NoteID] = [:]
        var noteIDs = Set<NoteID>()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for item in recordItems {
            let record: ReconciliationRecord
            do {
                record = try decoder.decode(ReconciliationRecord.self, from: item.data)
            } catch {
                throw CloudCollectionMigrationError.sourceReconciliationMismatch(item.relativePath)
            }
            guard record.schemaVersion == ReconciliationRecord.currentSchemaVersion,
                  noteIDs.insert(record.noteID).inserted else {
                throw CloudCollectionMigrationError.sourceReconciliationMismatch(item.relativePath)
            }
            guard !record.isTombstone else { continue }
            guard activePaths[record.currentRelativePath] == nil,
                  documentsByPath[record.currentRelativePath] == record.rawContentHash else {
                throw CloudCollectionMigrationError.sourceReconciliationMismatch(record.currentRelativePath)
            }
            activePaths[record.currentRelativePath] = record.noteID
        }
        guard Set(activePaths.keys) == Set(documentsByPath.keys) else {
            throw CloudCollectionMigrationError.sourceReconciliationMismatch("collection")
        }
    }

    private func sourceItems(
        at root: URL,
        namespace: CloudMigrationNamespace,
        includes: (URL) -> Bool
    ) throws -> [SourceItem] {
        guard fileManager.fileExists(atPath: root.path) else {
            throw CloudCollectionMigrationError.sourceMissing(root.path)
        }
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CloudCollectionMigrationError.unsafePath(root.path)
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [SourceItem] = []
        for case let url as URL in enumerator {
            let itemValues = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard itemValues.isSymbolicLink != true else {
                throw CloudCollectionMigrationError.unsafePath(url.path)
            }
            guard itemValues.isRegularFile == true, includes(url) else { continue }
            let relativePath = String(url.standardizedFileURL.path.dropFirst(root.path.count + 1))
            try ReconciliationStore.validate(relativePath: relativePath)
            let data = try Data(contentsOf: url)
            result.append(
                SourceItem(
                    namespace: namespace,
                    relativePath: relativePath,
                    data: data,
                    contentHash: ContentHash.sha256(data)
                )
            )
        }
        return result
    }

    private func createBackup(at backup: URL, sourceItems: [SourceItem]) throws {
        for item in sourceItems {
            let namespace = item.namespace == .documents ? "Documents" : "Reconciliation"
            let url = backup.appendingPathComponent(namespace, isDirectory: true)
                .appendingPathComponent(item.relativePath)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try item.data.write(to: url, options: .atomic)
        }
        let journalItems = sourceItems.map(\.journalItem)
        let verificationJournal = CloudMigrationJournal(
            sourceDocumentsPath: "",
            sourceRecordsPath: "",
            destinationDocumentsIdentifier: "",
            destinationRecordsIdentifier: "",
            retainedBackupPath: backup.path,
            items: journalItems,
            phase: .backupVerified
        )
        try verifyBackup(journal: verificationJournal, sourceItems: sourceItems)
    }

    private func verifyBackup(
        journal: CloudMigrationJournal,
        sourceItems: [SourceItem]
    ) throws {
        let backup = URL(fileURLWithPath: journal.retainedBackupPath, isDirectory: true)
        for item in sourceItems {
            let namespace = item.namespace == .documents ? "Documents" : "Reconciliation"
            let url = backup.appendingPathComponent(namespace, isDirectory: true)
                .appendingPathComponent(item.relativePath)
            guard fileManager.fileExists(atPath: url.path),
                  ContentHash.sha256(try Data(contentsOf: url)) == item.contentHash else {
                throw CloudCollectionMigrationError.backupVerificationFailed(item.relativePath)
            }
        }
    }

    private func verifyPublished(
        journal: CloudMigrationJournal,
        destinationDocuments: any CloudDocumentAccess,
        destinationRecords: any CloudDocumentAccess
    ) throws {
        guard Set(journal.items) == Set(journal.publishedItems) else {
            throw CloudCollectionMigrationError.publicationVerificationFailed("journal")
        }
        for item in journal.items {
            let destination = adapter(
                for: item.namespace,
                documents: destinationDocuments,
                records: destinationRecords
            )
            guard ContentHash.sha256(try destination.read(relativePath: item.relativePath)) == item.contentHash else {
                throw CloudCollectionMigrationError.publicationVerificationFailed(item.relativePath)
            }
        }
    }

    private func validate(
        _ journal: CloudMigrationJournal,
        sourceDocuments: URL,
        sourceRecords: URL,
        destinationDocuments: any CloudDocumentAccess,
        destinationRecords: any CloudDocumentAccess,
        backup: URL,
        sourceItems: [SourceItem]
    ) throws {
        guard journal.sourceDocumentsPath == sourceDocuments.path,
              journal.sourceRecordsPath == sourceRecords.path,
              journal.destinationDocumentsIdentifier == destinationDocuments.identifier,
              journal.destinationRecordsIdentifier == destinationRecords.identifier,
              journal.retainedBackupPath == backup.path,
              journal.items == sourceItems.map(\.journalItem) else {
            throw CloudCollectionMigrationError.journalDoesNotMatch
        }
    }

    private func validatePaths(
        sourceDocuments: URL,
        sourceRecords: URL,
        backup: URL,
        journal: URL
    ) throws {
        let paths = [sourceDocuments.path, sourceRecords.path, backup.path, journal.path]
        guard paths.allSatisfy({ !$0.isEmpty && $0 != "/" }),
              Set(paths).count == paths.count,
              !backup.path.hasPrefix(sourceDocuments.path + "/"),
              !backup.path.hasPrefix(sourceRecords.path + "/"),
              !journal.path.hasPrefix(sourceDocuments.path + "/"),
              !journal.path.hasPrefix(sourceRecords.path + "/") else {
            throw CloudCollectionMigrationError.unsafePath(paths.joined(separator: ", "))
        }
    }

    private func adapter(
        for namespace: CloudMigrationNamespace,
        documents: any CloudDocumentAccess,
        records: any CloudDocumentAccess
    ) -> any CloudDocumentAccess {
        namespace == .documents ? documents : records
    }

    private func write(_ journal: CloudMigrationJournal, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.encoder.encode(journal).write(to: url, options: .atomic)
    }

    private func result(
        for journal: CloudMigrationJournal,
        journalURL: URL
    ) -> CloudCollectionMigrationResult {
        CloudCollectionMigrationResult(
            transactionID: journal.transactionID,
            publishedItemCount: journal.publishedItems.count,
            retainedBackupURL: URL(fileURLWithPath: journal.retainedBackupPath, isDirectory: true),
            journalURL: journalURL
        )
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder { JSONDecoder() }
}

private struct SourceItem: Equatable, Sendable {
    let namespace: CloudMigrationNamespace
    let relativePath: String
    let data: Data
    let contentHash: String

    var journalItem: CloudMigrationJournalItem {
        CloudMigrationJournalItem(
            namespace: namespace,
            relativePath: relativePath,
            contentHash: contentHash
        )
    }
}
