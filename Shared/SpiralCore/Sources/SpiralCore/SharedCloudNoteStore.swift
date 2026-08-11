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

/// The single production iCloud container shared by Spiral on every platform.
public enum SharedICloudStoreConfiguration {
    public static let containerIdentifier = "iCloud.farm.poplar.spiral"
}

public enum SharedCloudStoreReadiness: Equatable, Sendable {
    case ready(canonicalNoteCount: Int)
    case requiresLegacyMigration(legacyPaths: [String], canonicalNoteCount: Int)
    case containsUnsupportedData(paths: [String])
}

/// Keeps the public iCloud Documents directory limited to ordinary note files.
/// Legacy database and WAL artifacts must be retired on Mac before a mobile
/// client opens the collection; unrelated files are never silently ignored.
public struct SharedCloudStorePolicy: Sendable {
    public static let legacyArtifactNames: Set<String> = [
        "Notes & Settings",
        "Interim Note-Changes"
    ]

    public init() {}

    public func readiness(
        for snapshots: [CloudDocumentSnapshot]
    ) -> SharedCloudStoreReadiness {
        var canonicalCount = 0
        var legacyPaths: [String] = []
        var unsupportedPaths: [String] = []
        for snapshot in snapshots {
            let pathExtension = (snapshot.relativePath as NSString).pathExtension
            if NoteFormat.format(forPathExtension: pathExtension) != nil {
                canonicalCount += 1
            } else if Self.legacyArtifactNames.contains(snapshot.relativePath) {
                legacyPaths.append(snapshot.relativePath)
            } else {
                unsupportedPaths.append(snapshot.relativePath)
            }
        }
        if !unsupportedPaths.isEmpty {
            return .containsUnsupportedData(paths: unsupportedPaths.sorted())
        }
        if !legacyPaths.isEmpty {
            return .requiresLegacyMigration(
                legacyPaths: legacyPaths.sorted(),
                canonicalNoteCount: canonicalCount
            )
        }
        return .ready(canonicalNoteCount: canonicalCount)
    }
}

public enum LegacyCloudArtifactRetirementError: Error, Equatable, Sendable {
    case canonicalNotesRequired
    case unsupportedData([String])
    case unavailable(String)
    case unsafeBackupPath
    case backupContainsData
    case backupVerificationFailed(String)
    case rollbackVerificationFailed(String)
}

/// Makes a byte-verified, local retained backup before removing the obsolete
/// live database/WAL artifacts from public iCloud Documents. Canonical notes
/// are never removed or rewritten by this service.
public struct LegacyCloudArtifactRetirementService: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    public func retire(
        from documents: any CloudDocumentAccess,
        retainedBackupURL: URL
    ) throws -> [String] {
        let snapshots = try documents.listDocuments()
        let readiness = SharedCloudStorePolicy().readiness(for: snapshots)
        let paths: [String]
        switch readiness {
        case .ready:
            return []
        case let .requiresLegacyMigration(legacyPaths, canonicalNoteCount):
            guard canonicalNoteCount > 0 else {
                throw LegacyCloudArtifactRetirementError.canonicalNotesRequired
            }
            paths = legacyPaths
        case let .containsUnsupportedData(unsupportedPaths):
            throw LegacyCloudArtifactRetirementError.unsupportedData(unsupportedPaths)
        }

        let backup = retainedBackupURL.standardizedFileURL
        guard !backup.path.isEmpty, backup.path != "/" else {
            throw LegacyCloudArtifactRetirementError.unsafeBackupPath
        }
        if fileManager.fileExists(atPath: backup.path) {
            let values = try backup.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw LegacyCloudArtifactRetirementError.unsafeBackupPath
            }
            guard try fileManager.contentsOfDirectory(atPath: backup.path).isEmpty else {
                throw LegacyCloudArtifactRetirementError.backupContainsData
            }
        } else {
            try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        }

        var retained: [(path: String, data: Data)] = []
        for path in paths {
            guard let snapshot = snapshots.first(where: { $0.relativePath == path }),
                  snapshot.availability == .available else {
                if snapshots.first(where: { $0.relativePath == path })?.availability == .unavailable {
                    try documents.requestDownload(relativePath: path)
                }
                throw LegacyCloudArtifactRetirementError.unavailable(path)
            }
            let data = try documents.read(relativePath: path)
            let destination = backup.appendingPathComponent(path)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
            guard ContentHash.sha256(try Data(contentsOf: destination)) == ContentHash.sha256(data) else {
                throw LegacyCloudArtifactRetirementError.backupVerificationFailed(path)
            }
            retained.append((path, data))
        }

        for item in retained {
            let destination = backup.appendingPathComponent(item.path)
            guard ContentHash.sha256(try Data(contentsOf: destination)) == ContentHash.sha256(item.data) else {
                throw LegacyCloudArtifactRetirementError.backupVerificationFailed(item.path)
            }
        }
        var deleted: [(path: String, data: Data)] = []
        do {
            for item in retained {
                try documents.delete(relativePath: item.path)
                deleted.append(item)
            }
        } catch {
            for item in deleted.reversed() {
                do {
                    try documents.write(item.data, relativePath: item.path)
                    guard try documents.read(relativePath: item.path) == item.data else {
                        throw LegacyCloudArtifactRetirementError.rollbackVerificationFailed(item.path)
                    }
                } catch {
                    throw LegacyCloudArtifactRetirementError.rollbackVerificationFailed(item.path)
                }
            }
            throw error
        }
        return paths
    }
}

public enum CloudNoteStoreError: Error, Equatable, Sendable {
    case noteNotFound(NoteID)
    case duplicateIdentity(NoteID)
    case ambiguousDocument(String)
    case duplicateReconciliationRecord(NoteID)
    case unavailableDocuments([String])
    case unsupportedPublicData([String])
}

/// Production NoteStore for the one shared iCloud collection. Every public
/// document mutation uses CloudDocumentAccess/NSFileCoordinator and every UUID
/// record is stored in the private synchronized reconciliation directory.
public actor CloudNoteStore: NoteStore {
    private static let maximumHydrationBatchSize = 8

    public let indexURL: URL
    public let catalogScope: NoteCatalogScope

    private let documents: any CloudDocumentAccess
    private let reconciliationRecords: any CloudDocumentAccess
    private let reconciler: CloudCollectionReconciler
    private let codec: NoteFileCodec
    private var notesByID: [NoteID: Note] = [:]
    private var recordsByID: [NoteID: ReconciliationRecord] = [:]
    private var storedConflicts: [NoteConflict] = []
    private var catalogStorage: NoteCatalog?

    public init(
        documents: any CloudDocumentAccess,
        reconciliationRecords: any CloudDocumentAccess,
        indexURL: URL,
        catalogScope: NoteCatalogScope? = nil,
        codec: NoteFileCodec = NoteFileCodec()
    ) {
        self.documents = documents
        self.reconciliationRecords = reconciliationRecords
        self.indexURL = indexURL
        self.catalogScope = catalogScope ?? NoteCatalogScope(
            accountIdentifier: "catalog-at:\(indexURL.standardizedFileURL.path)",
            collectionIdentifier: SharedICloudStoreConfiguration.containerIdentifier
        )
        self.codec = codec
        reconciler = CloudCollectionReconciler(
            documents: documents,
            reconciliationRecords: reconciliationRecords
        )
    }

    public func reloadFromCloud() async throws {
        let snapshots = try documents.listDocuments()
        switch SharedCloudStorePolicy().readiness(for: snapshots) {
        case .ready:
            break
        case .requiresLegacyMigration:
            let legacy = snapshots.map(\.relativePath).filter {
                SharedCloudStorePolicy.legacyArtifactNames.contains($0)
            }
            throw CloudNoteStoreError.unsupportedPublicData(legacy.sorted())
        case let .containsUnsupportedData(paths):
            throw CloudNoteStoreError.unsupportedPublicData(paths)
        }

        let report = try await reconciler.reconcile()
        try loadState(report: report)
    }

    public func allNotes() -> [Note] {
        notesByID.values.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    public func summary(id: NoteID) throws -> NoteSummary? {
        try catalog().summary(id: id)
    }

    public func note(id: NoteID) async throws -> Note? {
        if let note = notesByID[id] { return note }
        guard let record = recordsByID[id], !record.isTombstone else { return nil }
        guard let snapshot = try documents.listDocuments().first(where: {
            $0.relativePath == record.currentRelativePath
        }) else { return nil }

        switch snapshot.availability {
        case .available:
            let note = try decodedNote(record: record, snapshot: snapshot)
            notesByID[id] = note
            try catalog().upsert(catalogEntry(note: note, record: record))
            return note

        case .downloadPending:
            try markBodyUnavailable(record: record, availability: .downloadPending)
            return nil

        case .unavailable:
            if try catalog().summary(id: id)?.bodyAvailability != .downloadPending {
                try documents.requestDownload(relativePath: record.currentRelativePath)
                try markBodyUnavailable(record: record, availability: .downloadPending)
            }
            return nil
        }
    }

    @discardableResult
    public func create(_ note: Note) throws -> Note {
        guard notesByID[note.id] == nil, recordsByID[note.id] == nil else {
            throw CloudNoteStoreError.duplicateIdentity(note.id)
        }
        let relativePath = try availableRelativePath(for: note, excluding: nil)
        let data = try codec.encode(note.content)
        try documents.write(data, relativePath: relativePath)
        let record = ReconciliationRecord(
            noteID: note.id,
            currentRelativePath: relativePath,
            rawContentHash: ContentHash.sha256(data),
            lastCommonRevisionHash: ContentHash.sha256(data),
            mergeBaseContent: data,
            tags: note.tags,
            legacyMetadata: note.legacyMetadata,
            createdAt: note.createdAt,
            modifiedAt: note.modifiedAt,
            isPinned: note.isPinned,
            isPrivate: note.isPrivate
        )
        do {
            try save(record)
        } catch {
            if (try? documents.read(relativePath: relativePath)) == data {
                try? documents.delete(relativePath: relativePath)
            }
            throw error
        }
        notesByID[note.id] = note
        recordsByID[note.id] = record
        try catalog().upsert(catalogEntry(note: note, record: record))
        return note
    }

    public func update(_ note: Note) async throws {
        guard recordsByID[note.id] != nil else {
            throw CloudNoteStoreError.noteNotFound(note.id)
        }
        let editedData = try codec.encode(note.content)
        let report = try await reconciler.reconcile(
            pendingLocalEdits: [note.id: CloudPendingEdit(data: editedData, modifiedAt: note.modifiedAt)]
        )
        try loadState(report: report)
        guard var record = recordsByID[note.id] else {
            throw CloudNoteStoreError.noteNotFound(note.id)
        }

        let oldPath = record.currentRelativePath
        let newPath = try availableRelativePath(
            for: note,
            excluding: note.id,
            pathExtension: pathExtension(for: note, currentRelativePath: oldPath)
        )
        if oldPath != newPath {
            try documents.move(from: oldPath, to: newPath)
            record.move(to: newPath)
        }
        record.tags = note.tags
        record.legacyMetadata = note.legacyMetadata
        record.modifiedAt = note.modifiedAt
        record.isPinned = note.isPinned
        record.isPrivate = note.isPrivate
        record.isTombstone = false
        try save(record)
        recordsByID[note.id] = record

        let finalData = try documents.read(relativePath: record.currentRelativePath)
        var persisted = note
        persisted.content = try codec.decode(finalData, as: format(for: record.currentRelativePath))
        notesByID[note.id] = persisted
        storedConflicts = report.conflicts
        try catalog().upsert(catalogEntry(note: persisted, record: record))
    }

    public func delete(id: NoteID) throws {
        guard var record = recordsByID[id], notesByID[id] != nil else {
            throw CloudNoteStoreError.noteNotFound(id)
        }
        try documents.delete(relativePath: record.currentRelativePath)
        record.isTombstone = true
        record.mergeBaseContent = nil
        try save(record)
        recordsByID[id] = record
        notesByID.removeValue(forKey: id)
        storedConflicts.removeAll { $0.noteID == id }
        try catalog().remove(noteID: id)
    }

    public func conflicts() -> [NoteConflict] { storedConflicts }

    public func rebuildIndex() throws {
        let snapshots = try documents.listDocuments()
        let availability = Dictionary(uniqueKeysWithValues: snapshots.map {
            ($0.relativePath, $0.availability)
        })
        for record in recordsByID.values {
            if record.isTombstone {
                try catalog().remove(noteID: record.noteID)
            } else if let note = notesByID[record.noteID] {
                try catalog().upsert(catalogEntry(note: note, record: record))
            } else {
                let itemAvailability = availability[record.currentRelativePath]
                let isMissing = itemAvailability == nil
                let bodyState = itemAvailability.map(bodyAvailability(for:))
                    ?? .deletedOrMissingPendingConfirmation
                try catalog().upsert(NoteCatalogEntry(
                    summary: catalogSummary(
                        record: record,
                        bodyAvailability: bodyState,
                        pairingState: isMissing ? .missingPendingConfirmation : .awaitingBody
                    ),
                    textUpdate: .preserveAsStale
                ))
            }
        }
    }

    public func summaries(limit: Int, offset: Int) async throws -> NoteSummaryPage {
        try catalog().summaries(limit: limit, offset: offset)
    }

    public func search(_ request: NoteSearchRequest) async throws -> NoteSearchPage {
        try catalog().search(request)
    }

    public func hydrateSearchIndex(
        maximumConcurrentDownloads: Int
    ) async throws -> NoteSearchHydrationProgress {
        let maximum = min(
            max(0, maximumConcurrentDownloads),
            Self.maximumHydrationBatchSize
        )
        var counts = try catalog().hydrationCounts()
        guard maximum > 0, counts.pending < maximum else {
            return NoteSearchHydrationProgress(
                pendingCount: counts.pending,
                remainingCount: counts.remaining
            )
        }

        let snapshots = Dictionary(uniqueKeysWithValues: try documents.listDocuments().map {
            ($0.relativePath, $0)
        })
        var slots = maximum - counts.pending
        let inspectionLimit = min(64, max(slots, slots * 4))
        let candidates = try catalog().hydrationCandidates(limit: inspectionLimit)
        var requested: [NoteID] = []
        var indexed: [NoteID] = []

        for summary in candidates where slots > 0 {
            guard let record = recordsByID[summary.id],
                  !record.isTombstone,
                  !record.isPrivate,
                  let snapshot = snapshots[record.currentRelativePath] else { continue }
            switch snapshot.availability {
            case .available:
                let note = try decodedNote(record: record, snapshot: snapshot)
                notesByID[record.noteID] = note
                try catalog().upsert(catalogEntry(note: note, record: record))
                indexed.append(record.noteID)
                slots -= 1

            case .unavailable:
                try documents.requestDownload(relativePath: record.currentRelativePath)
                try markBodyUnavailable(record: record, availability: .downloadPending)
                requested.append(record.noteID)
                slots -= 1

            case .downloadPending:
                try markBodyUnavailable(record: record, availability: .downloadPending)
                slots -= 1
            }
        }

        counts = try catalog().hydrationCounts()
        return NoteSearchHydrationProgress(
            requestedNoteIDs: requested,
            indexedNoteIDs: indexed,
            pendingCount: counts.pending,
            remainingCount: counts.remaining
        )
    }

    public func record(for id: NoteID) -> ReconciliationRecord? { recordsByID[id] }

    private func loadState(report: CloudReconciliationReport) throws {
        let loadedRecords = try loadRecords()
        if let duplicate = report.duplicateRecordIdentities.first {
            throw CloudNoteStoreError.duplicateReconciliationRecord(duplicate)
        }
        if let ambiguous = report.ambiguousPaths.first {
            throw CloudNoteStoreError.ambiguousDocument(ambiguous)
        }

        var nextNotes: [NoteID: Note] = [:]
        for record in loadedRecords.values where record.isTombstone {
            nextNotes.removeValue(forKey: record.noteID)
            try catalog().remove(noteID: record.noteID)
        }
        var recordsByPath: [String: ReconciliationRecord] = [:]
        for record in loadedRecords.values where !record.isTombstone {
            if recordsByPath.updateValue(record, forKey: record.currentRelativePath) != nil {
                throw CloudNoteStoreError.ambiguousDocument(record.currentRelativePath)
            }
        }

        var observedPaths = Set<String>()
        for snapshot in try documents.listDocuments() where isCanonical(snapshot.relativePath) {
            observedPaths.insert(snapshot.relativePath)
            guard let record = recordsByPath[snapshot.relativePath] else {
                continue
            }
            guard snapshot.availability == .available else {
                try catalog().upsert(NoteCatalogEntry(
                    summary: catalogSummary(
                        record: record,
                        bodyAvailability: bodyAvailability(for: snapshot.availability),
                        pairingState: .awaitingBody
                    ),
                    textUpdate: .preserveAsStale
                ))
                continue
            }
            nextNotes[record.noteID] = try decodedNote(record: record, snapshot: snapshot)
            if let note = nextNotes[record.noteID] {
                try catalog().upsert(catalogEntry(note: note, record: record))
            }
        }

        for record in loadedRecords.values where !record.isTombstone
            && !observedPaths.contains(record.currentRelativePath) {
            try catalog().upsert(NoteCatalogEntry(
                summary: catalogSummary(
                    record: record,
                    bodyAvailability: .deletedOrMissingPendingConfirmation,
                    pairingState: .missingPendingConfirmation
                ),
                textUpdate: .preserveAsStale
            ))
        }

        recordsByID = loadedRecords
        notesByID = nextNotes
        storedConflicts = report.conflicts
    }

    private func catalog() throws -> NoteCatalog {
        if let catalogStorage { return catalogStorage }
        let opened = try NoteCatalog(databaseURL: indexURL, scope: catalogScope)
        catalogStorage = opened
        return opened
    }

    private func catalogEntry(note: Note, record: ReconciliationRecord) -> NoteCatalogEntry {
        NoteCatalogEntry(
            summary: NoteSummary(
                note: note,
                relativePath: record.currentRelativePath,
                contentHash: record.rawContentHash
            ),
            textUpdate: .replace(text: note.content.text, revision: record.rawContentHash)
        )
    }

    private func decodedNote(
        record: ReconciliationRecord,
        snapshot: CloudDocumentSnapshot
    ) throws -> Note {
        let data = try documents.read(relativePath: snapshot.relativePath)
        return Note(
            id: record.noteID,
            title: ((snapshot.relativePath as NSString).lastPathComponent as NSString)
                .deletingPathExtension,
            content: try codec.decode(data, as: format(for: snapshot.relativePath)),
            tags: record.tags,
            legacyMetadata: record.legacyMetadata,
            folder: folder(for: snapshot.relativePath),
            createdAt: record.createdAt,
            modifiedAt: record.modifiedAt,
            isPinned: record.isPinned,
            isPrivate: record.isPrivate
        )
    }

    private func markBodyUnavailable(
        record: ReconciliationRecord,
        availability: NoteBodyAvailability
    ) throws {
        try catalog().upsert(NoteCatalogEntry(
            summary: catalogSummary(
                record: record,
                bodyAvailability: availability,
                pairingState: .awaitingBody
            ),
            textUpdate: .preserveAsStale
        ))
    }

    private func bodyAvailability(
        for availability: CloudItemAvailability
    ) -> NoteBodyAvailability {
        switch availability {
        case .available: .available
        case .unavailable: .notDownloaded
        case .downloadPending: .downloadPending
        }
    }

    private func catalogSummary(
        record: ReconciliationRecord,
        bodyAvailability: NoteBodyAvailability,
        pairingState: NotePairingState
    ) -> NoteSummary {
        NoteSummary(
            id: record.noteID,
            title: ((record.currentRelativePath as NSString).lastPathComponent as NSString)
                .deletingPathExtension,
            folder: folder(for: record.currentRelativePath),
            tags: record.tags,
            createdAt: record.createdAt,
            modifiedAt: record.modifiedAt,
            isPinned: record.isPinned,
            isPrivate: record.isPrivate,
            relativePath: record.currentRelativePath,
            contentHash: record.rawContentHash,
            bodyAvailability: bodyAvailability,
            metadataAvailability: .available,
            searchFreshness: .neverIndexed,
            lastIndexedRevision: nil,
            pairingState: pairingState,
            isSearchEligible: !record.isPrivate
        )
    }

    private func loadRecords() throws -> [NoteID: ReconciliationRecord] {
        var result: [NoteID: ReconciliationRecord] = [:]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for snapshot in try reconciliationRecords.listDocuments()
            where snapshot.relativePath.hasSuffix(".json") {
            guard snapshot.availability == .available else {
                if snapshot.availability == .unavailable {
                    try reconciliationRecords.requestDownload(relativePath: snapshot.relativePath)
                }
                continue
            }
            let record = try decoder.decode(
                ReconciliationRecord.self,
                from: reconciliationRecords.read(relativePath: snapshot.relativePath)
            )
            guard record.schemaVersion == ReconciliationRecord.currentSchemaVersion else {
                throw ReconciliationStoreError.unsupportedSchema(record.schemaVersion)
            }
            guard (snapshot.relativePath as NSString).deletingPathExtension == record.noteID.description else {
                throw ReconciliationStoreError.recordIdentityMismatch
            }
            if result.updateValue(record, forKey: record.noteID) != nil {
                throw CloudNoteStoreError.duplicateReconciliationRecord(record.noteID)
            }
        }
        return result
    }

    private func save(_ record: ReconciliationRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try reconciliationRecords.write(
            encoder.encode(record),
            relativePath: record.noteID.description + ".json"
        )
    }

    private func availableRelativePath(
        for note: Note,
        excluding noteID: NoteID?,
        pathExtension: String? = nil
    ) throws -> String {
        let folder = try sanitizedFolder(note.folder)
        let base = sanitizedFilename(note.title)
        let ext = pathExtension ?? note.content.format.preferredPathExtension
        let existingRecords = Set(recordsByID.compactMap { id, record in
            id == noteID || record.isTombstone ? nil : record.currentRelativePath.lowercased()
        })
        let existingDocuments = Set(try documents.listDocuments().map {
            $0.relativePath.lowercased()
        })
        var counter = 0
        while true {
            let suffix = counter == 0 ? "" : " \(counter + 1)"
            let filename = "\(base)\(suffix).\(ext)"
            let path = folder.map { "\($0)/\(filename)" } ?? filename
            let belongsToExcludedNote = noteID.flatMap {
                recordsByID[$0]?.currentRelativePath.lowercased()
            } == path.lowercased()
            if !existingRecords.contains(path.lowercased())
                && (belongsToExcludedNote || !existingDocuments.contains(path.lowercased())) {
                return path
            }
            counter += 1
        }
    }

    private func sanitizedFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\u{0}")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = cleaned.hasPrefix(".") ? "_" + cleaned : cleaned
        return visible.isEmpty ? "Untitled" : String(visible.prefix(180))
    }

    private func sanitizedFolder(_ folder: String?) throws -> String? {
        guard let folder, !folder.isEmpty else { return nil }
        try ReconciliationStore.validate(relativePath: folder + "/placeholder")
        return folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func pathExtension(for note: Note, currentRelativePath: String) -> String {
        let currentExtension = (currentRelativePath as NSString).pathExtension
        if NoteFormat.format(forPathExtension: currentExtension) == note.content.format {
            return currentExtension
        }
        return note.content.format.preferredPathExtension
    }

    private func format(for relativePath: String) -> NoteFormat {
        NoteFormat.format(forPathExtension: (relativePath as NSString).pathExtension) ?? .plainText
    }

    private func folder(for relativePath: String) -> String? {
        let folder = (relativePath as NSString).deletingLastPathComponent
        return folder == "." || folder.isEmpty ? nil : folder
    }

    private func isCanonical(_ relativePath: String) -> Bool {
        NoteFormat.format(forPathExtension: (relativePath as NSString).pathExtension) != nil
    }
}
