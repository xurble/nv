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
import Testing
@testable import SpiralCore

@Suite("Phase 4 coordinated iCloud adapters")
struct CoordinatedCloudAdapterTests {
    @Test("Foundation adapter coordinates write, read, move, delete, and traversal refusal")
    func coordinatedFileOperations() throws {
        let root = temporaryRoot("FoundationAdapter")
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = try FoundationCloudDocumentAdapter(rootURL: root)

        try adapter.write(Data("one".utf8), relativePath: "Folder/One.txt")
        #expect(try adapter.read(relativePath: "Folder/One.txt") == Data("one".utf8))
        #expect(try adapter.listDocuments().map(\.relativePath) == ["Folder/One.txt"])

        try adapter.move(from: "Folder/One.txt", to: "Renamed.txt")
        #expect(try adapter.listDocuments().map(\.relativePath) == ["Renamed.txt"])
        try adapter.delete(relativePath: "Renamed.txt")
        #expect(try adapter.listDocuments().isEmpty)

        do {
            try adapter.write(Data(), relativePath: "../escape.txt")
            Issue.record("Expected traversal to be refused")
        } catch let error as CloudDocumentAdapterError {
            #expect(error == .unsafeRelativePath("../escape.txt"))
        }
    }
}

@Suite("Phase 4 identity and content reconciliation")
struct CloudReconciliationPolicyTests {
    @Test("Identity matching uses current path, recent paths, hash, and refuses ambiguity")
    func identityMatchingOrder() {
        let firstID = NoteID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let secondID = NoteID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        let data = Data("same".utf8)
        let first = record(
            id: firstID,
            path: "Current.txt",
            data: data,
            recentPaths: ["Old.txt"]
        )
        let second = record(id: secondID, path: "Other.txt", data: data)
        let resolver = ReconciliationIdentityResolver()

        #expect(
            resolver.resolve(snapshot(path: "Current.txt", data: Data("changed".utf8)), records: [first, second])
                == .matched(firstID)
        )
        #expect(
            resolver.resolve(snapshot(path: "Old.txt", data: Data("changed".utf8)), records: [first, second])
                == .matched(firstID)
        )
        #expect(
            resolver.resolve(snapshot(path: "Moved.txt", data: data), records: [first])
                == .matched(firstID)
        )
        #expect(
            resolver.resolve(snapshot(path: "Copied.txt", data: data), records: [first, second])
                == .ambiguous([firstID, secondID])
        )
        #expect(
            resolver.resolve(
                CloudDocumentSnapshot(
                    relativePath: "Delayed.txt",
                    contentHash: nil,
                    modifiedAt: nil,
                    availability: .downloadPending
                ),
                records: [first]
            ) == .deferred
        )
    }

    @Test("Plain-text non-overlapping edits merge and same-line edits conflict")
    func plainTextThreeWayMerge() throws {
        let id = NoteID()
        let merger = NoteContentMerger()
        let base = revision("alpha\nbeta\ngamma", time: 1)
        let local = revision("ALPHA\nbeta\ngamma", time: 2)
        let remote = revision("alpha\nbeta\nGAMMA", time: 3)

        #expect(
            merger.merge(noteID: id, format: .plainText, base: base, local: local, external: remote)
                == .resolved(Data("ALPHA\nbeta\nGAMMA".utf8))
        )

        let conflicting = merger.merge(
            noteID: id,
            format: .plainText,
            base: base,
            local: revision("local\nbeta\ngamma", time: 2),
            external: revision("remote\nbeta\ngamma", time: 3)
        )
        guard case let .conflict(conflict) = conflicting else {
            Issue.record("Expected divergent same-line edits to conflict")
            return
        }
        #expect(conflict.noteID == id)
        #expect(conflict.commonBase == base)
    }

    @Test("RTF, HTML, and invalid text preserve both changed versions")
    func richAndInvalidDataConflict() {
        let merger = NoteContentMerger()
        let id = NoteID()
        let base = revision("base", time: 1)
        for format in [NoteFormat.richText, .html] {
            guard case .conflict = merger.merge(
                noteID: id,
                format: format,
                base: base,
                local: revision("local", time: 2),
                external: revision("external", time: 3)
            ) else {
                Issue.record("Expected \(format) to preserve both versions")
                continue
            }
        }
        let invalid = NoteRevision(
            contentHash: ContentHash.sha256(Data([0xff])),
            content: Data([0xff]),
            modifiedAt: Date(timeIntervalSince1970: 2)
        )
        guard case .conflict = merger.merge(
            noteID: id,
            format: .plainText,
            base: base,
            local: invalid,
            external: revision("external", time: 3)
        ) else {
            Issue.record("Expected invalid encoding to prevent automatic merge")
            return
        }
    }

    @Test("Unavailable files request download and never become tombstones")
    func unavailableIsNotDeletion() async throws {
        let id = NoteID(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!)
        let data = Data("remote".utf8)
        let documents = FaultCloudAdapter(identifier: "documents")
        documents.seed("Delayed.txt", data: data, availability: .unavailable)
        let records = FaultCloudAdapter(identifier: "records")
        records.seed("\(id.description).json", data: try encoded(record(id: id, path: "Delayed.txt", data: data)))
        let reconciler = CloudCollectionReconciler(
            documents: documents,
            reconciliationRecords: records
        )

        let report = try await reconciler.reconcile(confirmedDeletions: [id])

        #expect(report.deferredPaths == ["Delayed.txt"])
        #expect(report.tombstonedIdentities.isEmpty)
        #expect(documents.requestedDownloads == ["Delayed.txt"])
    }

    @Test("Unresolved NSFileVersion data is surfaced without rewriting the canonical file")
    func unresolvedVersionConflict() async throws {
        let id = NoteID(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!)
        let base = Data("base".utf8)
        let canonical = Data("canonical".utf8)
        let other = Data("other device".utf8)
        let documents = FaultCloudAdapter(identifier: "documents")
        documents.seed(
            "Versioned.txt",
            data: canonical,
            conflicts: [
                CloudDocumentConflictVersion(
                    data: other,
                    modifiedAt: Date(timeIntervalSince1970: 4),
                    deviceName: "Other Mac"
                )
            ]
        )
        let records = FaultCloudAdapter(identifier: "records")
        records.seed("\(id.description).json", data: try encoded(record(id: id, path: "Versioned.txt", data: base)))
        let reconciler = CloudCollectionReconciler(
            documents: documents,
            reconciliationRecords: records
        )

        let report = try await reconciler.reconcile()

        #expect(report.conflicts.count == 1)
        #expect(report.conflicts.first?.local.content == canonical)
        #expect(report.conflicts.first?.external.content == other)
        #expect(documents.data(at: "Versioned.txt") == canonical)
    }

    @Test("Duplicate reconciliation UUIDs and path collisions are surfaced")
    func duplicateRecordIdentity() async throws {
        let id = NoteID(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
        let data = Data("body".utf8)
        let documents = FaultCloudAdapter(identifier: "documents")
        documents.seed("Note.txt", data: data)
        let records = FaultCloudAdapter(identifier: "records")
        records.seed("first.json", data: try encoded(record(id: id, path: "Note.txt", data: data)))
        records.seed("second.json", data: try encoded(record(id: id, path: "Note.txt", data: data)))
        let reconciler = CloudCollectionReconciler(
            documents: documents,
            reconciliationRecords: records
        )

        let report = try await reconciler.reconcile()

        #expect(report.duplicateRecordIdentities == [id])
        #expect(report.ambiguousPaths == ["Note.txt"])
        #expect(documents.data(at: "Note.txt") == data)
    }
}

@Suite("Phase 4 multi-device fault tests")
struct CloudMultiDeviceFaultTests {
    @Test("Two offline devices editing different notes converge")
    func twoDeviceDifferentNoteConvergence() async throws {
        let documents = FaultCloudAdapter(identifier: "shared-documents")
        let firstID = NoteID(UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)
        let secondID = NoteID(UUID(uuidString: "20000000-0000-0000-0000-000000000002")!)
        let firstBase = Data("first base".utf8)
        let secondBase = Data("second base".utf8)
        documents.seed("First.txt", data: firstBase)
        documents.seed("Second.txt", data: secondBase)

        let deviceOneRecords = FaultCloudAdapter(identifier: "device-one-records")
        let deviceTwoRecords = FaultCloudAdapter(identifier: "device-two-records")
        for records in [deviceOneRecords, deviceTwoRecords] {
            records.seed("\(firstID.description).json", data: try encoded(record(id: firstID, path: "First.txt", data: firstBase)))
            records.seed("\(secondID.description).json", data: try encoded(record(id: secondID, path: "Second.txt", data: secondBase)))
        }

        let deviceOne = CloudCollectionReconciler(
            documents: documents,
            reconciliationRecords: deviceOneRecords
        )
        let deviceTwo = CloudCollectionReconciler(
            documents: documents,
            reconciliationRecords: deviceTwoRecords
        )
        _ = try await deviceOne.reconcile(
            pendingLocalEdits: [firstID: CloudPendingEdit(data: Data("first from device one".utf8))]
        )
        _ = try await deviceTwo.reconcile(
            pendingLocalEdits: [secondID: CloudPendingEdit(data: Data("second from device two".utf8))]
        )

        #expect(documents.data(at: "First.txt") == Data("first from device one".utf8))
        #expect(documents.data(at: "Second.txt") == Data("second from device two".utf8))
    }

    @Test("Three delayed devices merge non-overlapping same-note edits")
    func threeDeviceSameNoteConvergence() async throws {
        let documents = FaultCloudAdapter(identifier: "shared-documents")
        let id = NoteID(UUID(uuidString: "30000000-0000-0000-0000-000000000003")!)
        let base = Data("alpha\nbeta\ngamma".utf8)
        documents.seed("Shared.txt", data: base)
        let recordData = try encoded(record(id: id, path: "Shared.txt", data: base))

        let deviceRecords = (1...3).map { FaultCloudAdapter(identifier: "device-\($0)-records") }
        for records in deviceRecords {
            records.seed("\(id.description).json", data: recordData)
        }
        let devices = deviceRecords.map {
            CloudCollectionReconciler(documents: documents, reconciliationRecords: $0)
        }

        _ = try await devices[0].reconcile(
            pendingLocalEdits: [id: CloudPendingEdit(data: Data("ALPHA\nbeta\ngamma".utf8))]
        )
        _ = try await devices[1].reconcile(
            pendingLocalEdits: [id: CloudPendingEdit(data: Data("alpha\nBETA\ngamma".utf8))]
        )
        let finalReport = try await devices[2].reconcile(
            pendingLocalEdits: [id: CloudPendingEdit(data: Data("alpha\nbeta\nGAMMA".utf8))]
        )

        #expect(documents.data(at: "Shared.txt") == Data("ALPHA\nBETA\nGAMMA".utf8))
        #expect(finalReport.conflicts.isEmpty)
        #expect(finalReport.mergedIdentities == [id])
    }

    @Test("Three-device same-line fault preserves a visible conflict copy")
    func threeDeviceConflictPreservesBoth() async throws {
        let documents = FaultCloudAdapter(identifier: "shared-documents")
        let id = NoteID(UUID(uuidString: "40000000-0000-0000-0000-000000000004")!)
        let base = Data("base\nsecond".utf8)
        documents.seed("Shared.txt", data: base)
        let staleRecords = FaultCloudAdapter(identifier: "stale-device-records")
        staleRecords.seed(
            "\(id.description).json",
            data: try encoded(record(id: id, path: "Shared.txt", data: base))
        )

        documents.seed("Shared.txt", data: Data("remote\nsecond".utf8))
        let device = CloudCollectionReconciler(
            documents: documents,
            reconciliationRecords: staleRecords
        )
        let report = try await device.reconcile(
            pendingLocalEdits: [id: CloudPendingEdit(data: Data("local\nsecond".utf8))]
        )

        #expect(report.conflicts.count == 1)
        #expect(report.preservedConflictPaths == ["Shared (Conflict).txt"])
        #expect(documents.data(at: "Shared.txt") == Data("local\nsecond".utf8))
        #expect(documents.data(at: "Shared (Conflict).txt") == Data("remote\nsecond".utf8))
    }
}

@Suite("Phase 4 durable migration journal")
struct CloudMigrationJournalTests {
    @Test("Preflight rejects a collection missing a private reconciliation record")
    func rejectsIncompleteReconciliation() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let recordURLs = try FileManager.default.contentsOfDirectory(
            at: fixture.records,
            includingPropertiesForKeys: nil
        )
        try FileManager.default.removeItem(at: try #require(recordURLs.first))
        let documents = FaultCloudAdapter(identifier: "destination-documents")
        let records = FaultCloudAdapter(identifier: "destination-records")

        do {
            _ = try CloudCollectionMigrationService().migrate(
                sourceDocumentsURL: fixture.documents,
                sourceReconciliationURL: fixture.records,
                destinationDocuments: documents,
                destinationReconciliationRecords: records,
                retainedBackupURL: fixture.backup,
                journalURL: fixture.journal
            )
            Issue.record("Expected reconciliation preflight to fail")
        } catch let error as CloudCollectionMigrationError {
            #expect(error == .sourceReconciliationMismatch("collection"))
        }
        #expect(try documents.listDocuments().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.backup.path))
    }

    @Test("Interrupted publication resumes from its per-item journal")
    func resumeAfterInjectedFailure() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let documents = FaultCloudAdapter(identifier: "destination-documents")
        let records = FaultCloudAdapter(identifier: "destination-records")
        let interrupted = CloudCollectionMigrationService { checkpoint in
            if case let .publishedItem(_, _, index) = checkpoint, index == 0 {
                throw CloudCollectionMigrationError.injectedFailure(checkpoint)
            }
        }

        do {
            _ = try interrupted.migrate(
                sourceDocumentsURL: fixture.documents,
                sourceReconciliationURL: fixture.records,
                destinationDocuments: documents,
                destinationReconciliationRecords: records,
                retainedBackupURL: fixture.backup,
                journalURL: fixture.journal
            )
            Issue.record("Expected injected publication failure")
        } catch let error as CloudCollectionMigrationError {
            guard case .injectedFailure = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }

        let partial = try CloudCollectionMigrationService().loadJournal(at: fixture.journal)
        #expect(partial.phase == .publishing)
        #expect(partial.publishedItems.count == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.backup.path))
        #expect(try Data(contentsOf: fixture.documents.appendingPathComponent("First.txt")) == Data("first".utf8))

        let result = try CloudCollectionMigrationService().migrate(
            sourceDocumentsURL: fixture.documents,
            sourceReconciliationURL: fixture.records,
            destinationDocuments: documents,
            destinationReconciliationRecords: records,
            retainedBackupURL: fixture.backup,
            journalURL: fixture.journal
        )

        #expect(result.publishedItemCount == 4)
        #expect(try CloudCollectionMigrationService().loadJournal(at: fixture.journal).phase == .committed)
        #expect(documents.data(at: "First.txt") == Data("first".utf8))
        #expect(documents.data(at: "Second.rtf") == Data("second".utf8))
        #expect(records.data(at: fixture.recordName) != nil)
    }

    @Test("Rollback removes only journal-owned bytes and retains the verified backup")
    func rollbackPublishedCollection() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let documents = FaultCloudAdapter(identifier: "destination-documents")
        let records = FaultCloudAdapter(identifier: "destination-records")
        let service = CloudCollectionMigrationService()
        _ = try service.migrate(
            sourceDocumentsURL: fixture.documents,
            sourceReconciliationURL: fixture.records,
            destinationDocuments: documents,
            destinationReconciliationRecords: records,
            retainedBackupURL: fixture.backup,
            journalURL: fixture.journal
        )

        try service.rollback(
            journalURL: fixture.journal,
            destinationDocuments: documents,
            destinationReconciliationRecords: records
        )

        #expect(try documents.listDocuments().isEmpty)
        #expect(try records.listDocuments().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.journal.path))
        #expect(FileManager.default.fileExists(atPath: fixture.backup.path))
        #expect(try Data(contentsOf: fixture.documents.appendingPathComponent("First.txt")) == Data("first".utf8))
    }

    @Test("Rollback refuses to erase an unrelated post-publication edit")
    func rollbackRefusesChangedDestination() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let documents = FaultCloudAdapter(identifier: "destination-documents")
        let records = FaultCloudAdapter(identifier: "destination-records")
        let service = CloudCollectionMigrationService()
        _ = try service.migrate(
            sourceDocumentsURL: fixture.documents,
            sourceReconciliationURL: fixture.records,
            destinationDocuments: documents,
            destinationReconciliationRecords: records,
            retainedBackupURL: fixture.backup,
            journalURL: fixture.journal
        )
        documents.seed("First.txt", data: Data("external edit".utf8))

        do {
            try service.rollback(
                journalURL: fixture.journal,
                destinationDocuments: documents,
                destinationReconciliationRecords: records
            )
            Issue.record("Expected rollback to preserve an external edit")
        } catch let error as CloudCollectionMigrationError {
            #expect(error == .destinationChangedDuringRollback("First.txt"))
        }
        #expect(documents.data(at: "First.txt") == Data("external edit".utf8))
        #expect(FileManager.default.fileExists(atPath: fixture.backup.path))
    }
}

private final class FaultCloudAdapter: CloudDocumentAccess, @unchecked Sendable {
    struct Entry {
        var data: Data
        var availability: CloudItemAvailability
        var modifiedAt: Date
        var conflicts: [CloudDocumentConflictVersion]
    }

    let identifier: String
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var downloadRequests: [String] = []

    init(identifier: String) { self.identifier = identifier }

    var requestedDownloads: [String] { lock.withLock { downloadRequests } }

    func seed(
        _ path: String,
        data: Data,
        availability: CloudItemAvailability = .available,
        conflicts: [CloudDocumentConflictVersion] = []
    ) {
        lock.withLock {
            entries[path] = Entry(
                data: data,
                availability: availability,
                modifiedAt: Date(timeIntervalSince1970: 100),
                conflicts: conflicts
            )
        }
    }

    func data(at path: String) -> Data? { lock.withLock { entries[path]?.data } }

    func listDocuments() throws -> [CloudDocumentSnapshot] {
        lock.withLock {
            entries.map { path, entry in
                CloudDocumentSnapshot(
                    relativePath: path,
                    contentHash: entry.availability == .available ? ContentHash.sha256(entry.data) : nil,
                    modifiedAt: entry.modifiedAt,
                    availability: entry.availability,
                    hasUnresolvedConflicts: !entry.conflicts.isEmpty
                )
            }.sorted { $0.relativePath < $1.relativePath }
        }
    }

    func read(relativePath: String) throws -> Data {
        try lock.withLock {
            guard let entry = entries[relativePath], entry.availability == .available else {
                throw CloudDocumentAdapterError.unavailable(relativePath)
            }
            return entry.data
        }
    }

    func write(_ data: Data, relativePath: String) throws {
        seed(relativePath, data: data)
    }

    func move(from sourcePath: String, to destinationPath: String) throws {
        try lock.withLock {
            guard let entry = entries.removeValue(forKey: sourcePath) else {
                throw CloudDocumentAdapterError.unavailable(sourcePath)
            }
            entries[destinationPath] = entry
        }
    }

    func delete(relativePath: String) throws {
        _ = lock.withLock { entries.removeValue(forKey: relativePath) }
    }

    func requestDownload(relativePath: String) throws {
        lock.withLock { downloadRequests.append(relativePath) }
    }

    func unresolvedConflictVersions(relativePath: String) throws -> [CloudDocumentConflictVersion] {
        lock.withLock { entries[relativePath]?.conflicts ?? [] }
    }
}

private struct MigrationFixture {
    let root: URL
    let documents: URL
    let records: URL
    let backup: URL
    let journal: URL
    let recordName: String

    init() throws {
        root = temporaryRoot("MigrationJournal")
        documents = root.appendingPathComponent("Source/Documents", isDirectory: true)
        records = root.appendingPathComponent("Source/Private/Reconciliation", isDirectory: true)
        backup = root.appendingPathComponent("Retained Backup", isDirectory: true)
        journal = root.appendingPathComponent("Private/Migration.json")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: documents.appendingPathComponent("First.txt"))
        try Data("second".utf8).write(to: documents.appendingPathComponent("Second.rtf"))
        let id = NoteID(UUID(uuidString: "50000000-0000-0000-0000-000000000005")!)
        recordName = id.description + ".json"
        try encoded(record(id: id, path: "First.txt", data: Data("first".utf8)))
            .write(to: records.appendingPathComponent(recordName))
        let secondID = NoteID(UUID(uuidString: "50000000-0000-0000-0000-000000000006")!)
        try encoded(record(id: secondID, path: "Second.rtf", data: Data("second".utf8)))
            .write(to: records.appendingPathComponent(secondID.description + ".json"))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private func temporaryRoot(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "SpiralPhase4Tests-\(name)-\(UUID().uuidString)",
        isDirectory: true
    )
}

private func record(
    id: NoteID,
    path: String,
    data: Data,
    recentPaths: [String] = []
) -> ReconciliationRecord {
    ReconciliationRecord(
        noteID: id,
        currentRelativePath: path,
        recentRelativePaths: recentPaths,
        rawContentHash: ContentHash.sha256(data),
        lastCommonRevisionHash: ContentHash.sha256(data),
        mergeBaseContent: data,
        createdAt: Date(timeIntervalSince1970: 1),
        modifiedAt: Date(timeIntervalSince1970: 1)
    )
}

private func snapshot(path: String, data: Data) -> CloudDocumentSnapshot {
    CloudDocumentSnapshot(
        relativePath: path,
        contentHash: ContentHash.sha256(data),
        modifiedAt: Date(timeIntervalSince1970: 2),
        availability: .available
    )
}

private func revision(_ text: String, time: TimeInterval) -> NoteRevision {
    let data = Data(text.utf8)
    return NoteRevision(
        contentHash: ContentHash.sha256(data),
        content: data,
        modifiedAt: Date(timeIntervalSince1970: time)
    )
}

private func encoded(_ record: ReconciliationRecord) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(record)
}
