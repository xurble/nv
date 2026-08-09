import Foundation
import Testing
@testable import SpiralCore

private struct TestDirectories {
    let root: URL
    let documents: URL
    let reconciliation: URL
    let index: URL

    init(name: String = #function) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SpiralCoreTests-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        documents = root.appendingPathComponent("Documents", isDirectory: true)
        reconciliation = root.appendingPathComponent("Private/Reconciliation", isDirectory: true)
        index = root.appendingPathComponent("Cache/index.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class LoaderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    func increment() { lock.withLock { storage += 1 } }
    var count: Int { lock.withLock { storage } }
}

@Suite("Platform-neutral note codecs")
struct NoteFileCodecTests {
    @Test("TXT, RTF, and HTML writes are deterministic and metadata-free")
    func deterministicWrites() throws {
        let codec = NoteFileCodec()
        for format in NoteFormat.allCases {
            let content = NoteContent(format: format, text: "A <note> & café 📝\nsecond line")
            let first = try codec.encode(content)
            let second = try codec.encode(content)
            #expect(first == second)
            #expect(!first.contains(Data("Spiral".utf8)))
            #expect(!first.contains(Data("UUID".utf8)))
            #expect(
                try codec.decode(first, as: format).text == content.text,
                "round trip failed for \(format.rawValue)"
            )
        }
    }

    @Test("Externally produced rich files remain byte-for-byte unchanged until edited")
    func externalRepresentationsArePreserved() throws {
        let codec = NoteFileCodec()
        for (name, format) in [("rich-note.rtf", NoteFormat.richText), ("html-note.html", .html)] {
            let source = repositoryFixtures.appendingPathComponent(name)
            let bytes = try Data(contentsOf: source)
            let content = try codec.decode(bytes, as: format)
            #expect(content.text.contains(format == .richText ? "Rich title" : "HTML title"))
            #expect(try codec.encode(content) == bytes)
        }
    }

    @Test("Legacy plain-text encodings decode")
    func legacyEncodings() throws {
        let latin1 = Data([0x63, 0x61, 0x66, 0xE9])
        let macRoman = Data([0x63, 0x61, 0x66, 0x8E])
        #expect(try NoteFileCodec().decode(latin1, as: .plainText).text == "café")
        #expect(try NoteFileCodec().decode(macRoman, as: .plainText).text == "café")
    }
}

@Suite("Per-note reconciliation records")
struct ReconciliationStoreTests {
    @Test("Records are independent, bounded, deterministic files outside Documents")
    func independentRecords() throws {
        let dirs = try TestDirectories()
        defer { dirs.remove() }
        let store = ReconciliationStore(rootURL: dirs.reconciliation)
        let id = NoteID(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
        let record = ReconciliationRecord(
            noteID: id,
            currentRelativePath: "Folder/Note.txt",
            recentRelativePaths: (0..<20).map { "Old/\($0).txt" },
            rawContentHash: ContentHash.sha256(Data("note".utf8)),
            mergeBaseContent: Data(repeating: 0, count: ReconciliationRecord.maximumMergeBaseBytes + 1),
            tags: ["one"],
            createdAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: 2)
        )
        try store.save(record)
        let loaded = try #require(store.loadAll()[id])
        #expect(loaded.recentRelativePaths.count == ReconciliationRecord.maximumRecentPaths)
        #expect(loaded.mergeBaseContent == nil)
        #expect(!loaded.isTombstone)
        #expect(dirs.reconciliation.path != dirs.documents.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dirs.reconciliation.path) == ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.json"])
    }

    @Test("Traversal paths are refused")
    func pathTraversal() throws {
        #expect(throws: ReconciliationStoreError.self) {
            try ReconciliationStore.validate(relativePath: "../outside.txt")
        }
        #expect(throws: ReconciliationStoreError.self) {
            try ReconciliationStore.validate(relativePath: "/absolute.txt")
        }
    }
}

@Suite("Local temporary-directory NoteStore")
struct LocalNoteStoreTests {
    @Test("Create, rename, move, reopen, and cache rebuild preserve UUID")
    func lifecycleAndIndexRebuild() async throws {
        let dirs = try TestDirectories()
        defer { dirs.remove() }
        let store = try await LocalNoteStore.open(
            documentsURL: dirs.documents,
            reconciliationURL: dirs.reconciliation,
            indexURL: dirs.index
        )
        var note = Note(
            id: NoteID(UUID(uuidString: "11111111-2222-3333-4444-555555555555")!),
            title: "First / note",
            content: NoteContent(format: .plainText, text: "body"),
            tags: ["project"],
            legacyMetadata: ["sync": Data("historic-id".utf8)],
            createdAt: Date(timeIntervalSince1970: 10),
            modifiedAt: Date(timeIntervalSince1970: 20)
        )
        note = try await store.create(note)
        let firstRecord = try #require(await store.record(for: note.id))
        #expect(firstRecord.currentRelativePath == "First - note.txt")
        let canonical = try Data(contentsOf: dirs.documents.appendingPathComponent(firstRecord.currentRelativePath))
        #expect(canonical == Data("body".utf8))
        #expect(!canonical.contains(Data(note.id.description.utf8)))

        note.title = "Renamed"
        note.folder = "Work"
        note.content.text = "updated"
        try await store.update(note)
        let movedRecord = try #require(await store.record(for: note.id))
        #expect(movedRecord.currentRelativePath == "Work/Renamed.txt")
        #expect(movedRecord.recentRelativePaths == ["First - note.txt"])

        try FileManager.default.removeItem(at: dirs.index)
        let reopened = try await LocalNoteStore.open(
            documentsURL: dirs.documents,
            reconciliationURL: dirs.reconciliation,
            indexURL: dirs.index
        )
        let reopenedNote = try #require(await reopened.note(id: note.id))
        #expect(reopenedNote.title == "Renamed")
        #expect(reopenedNote.tags == ["project"])
        #expect(reopenedNote.legacyMetadata["sync"] == Data("historic-id".utf8))
        #expect(FileManager.default.fileExists(atPath: dirs.index.path))
    }

    @Test("Filename collisions do not merge identities")
    func collisions() async throws {
        let dirs = try TestDirectories()
        defer { dirs.remove() }
        let store = try await LocalNoteStore.open(
            documentsURL: dirs.documents,
            reconciliationURL: dirs.reconciliation,
            indexURL: dirs.index
        )
        let first = try await store.create(Note(title: "Same", content: .init(format: .plainText, text: "one")))
        let second = try await store.create(Note(title: "Same", content: .init(format: .plainText, text: "two")))
        #expect(first.id != second.id)
        #expect(await store.record(for: first.id)?.currentRelativePath == "Same.txt")
        #expect(await store.record(for: second.id)?.currentRelativePath == "Same 2.txt")
    }

    @Test("Hidden titles remain visible and folder symlinks cannot redirect writes")
    func hiddenTitlesAndSymlinkSafety() async throws {
        let dirs = try TestDirectories()
        defer { dirs.remove() }
        let store = try await LocalNoteStore.open(
            documentsURL: dirs.documents,
            reconciliationURL: dirs.reconciliation,
            indexURL: dirs.index
        )
        let hidden = try await store.create(Note(
            title: ".hidden",
            content: .init(format: .plainText, text: "visible")
        ))
        #expect(await store.record(for: hidden.id)?.currentRelativePath == "_.hidden.txt")

        let outside = dirs.root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: dirs.documents.appendingPathComponent("Redirect", isDirectory: true),
            withDestinationURL: outside
        )
        await #expect(throws: LocalNoteStoreError.unsafePathComponent("Redirect")) {
            try await store.create(Note(
                title: "Must stay inside",
                content: .init(format: .plainText, text: "protected"),
                folder: "Redirect"
            ))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test("Deletion retains a content-free tombstone and emits an index event")
    func deletionAndConflict() async throws {
        let dirs = try TestDirectories()
        defer { dirs.remove() }
        let store = try await LocalNoteStore.open(
            documentsURL: dirs.documents,
            reconciliationURL: dirs.reconciliation,
            indexURL: dirs.index
        )
        let note = try await store.create(Note(title: "Delete", content: .init(format: .plainText, text: "secret")))
        let local = NoteRevision(contentHash: "a", content: Data("local".utf8), modifiedAt: .now)
        let external = NoteRevision(contentHash: "b", content: Data("external".utf8), modifiedAt: .now)
        try await store.recordConflict(.init(noteID: note.id, local: local, external: external, commonBase: nil))
        #expect(await store.conflicts().count == 1)
        try await store.delete(id: note.id)
        let tombstone = try #require(await store.record(for: note.id))
        #expect(tombstone.isTombstone)
        #expect(tombstone.mergeBaseContent == nil)
        #expect(await store.note(id: note.id) == nil)
        #expect(await store.drainEvents().contains(.deleted(note.id)))
    }
}

@Suite("Legacy compatibility and migration")
struct LegacyMigrationTests {
    @Test("Golden NV and nvAlt model snapshots retain notes and historical metadata")
    func goldenSnapshots() throws {
        for name in ["legacy-notational-velocity", "legacy-nvalt"] {
            let url = try #require(Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Fixtures"
            ))
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let snapshot = try decoder.decode(LegacyCollectionSnapshot.self, from: data)
            #expect(snapshot.notes.count == 1)
            #expect(!snapshot.notes[0].content.text.isEmpty)
            if name.contains("notational") {
                #expect(snapshot.notes[0].legacyMetadata["syncServicesMD"] != nil)
            } else {
                #expect(snapshot.recoveredWAL)
            }
        }
    }

    @Test("Separate files infer one family and reject mixed formats")
    func separateFileInference() throws {
        let dirs = try TestDirectories()
        defer { dirs.remove() }
        try FileManager.default.createDirectory(at: dirs.documents, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: dirs.documents.appendingPathComponent("One.text"))
        try Data("two".utf8).write(to: dirs.documents.appendingPathComponent("Two.taskpaper"))
        let source = LegacySeparateFileSource(collectionURL: dirs.documents)
        let snapshot = try source.loadSnapshot(from: dirs.documents)
        #expect(snapshot.notes.map(\.title) == ["One", "Two"])
        try Data("{\\rtf1 mixed}".utf8).write(to: dirs.documents.appendingPathComponent("Mixed.rtf"))
        #expect(throws: LegacyCompatibilityError.mixedSeparateFileFormats) {
            try source.loadSnapshot(from: dirs.documents)
        }
    }

    @Test("Copy-only migration preserves source, backup, values, clean files, and private identity")
    func copyOnlyMigration() async throws {
        let dirs = try TestDirectories()
        defer { dirs.remove() }
        let sourceURL = dirs.root.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try Data("café".utf8).write(to: sourceURL.appendingPathComponent("Café.txt"))
        let sourceBefore = try LegacyCollectionVerifier.fingerprint(at: sourceURL)
        let backup = dirs.root.appendingPathComponent("Backups/Legacy", isDirectory: true)
        let source = LegacySeparateFileSource(collectionURL: sourceURL)
        let result = try await LegacyMigrationService().migrate(
            source: source,
            to: .init(
                documentsURL: dirs.documents,
                reconciliationURL: dirs.reconciliation,
                indexURL: dirs.index,
                retainedBackupURL: backup
            ),
            confirmsPlaintextDestination: false
        )
        #expect(result.importedNoteCount == 1)
        #expect(try LegacyCollectionVerifier.fingerprint(at: sourceURL) == sourceBefore)
        #expect(try LegacyCollectionVerifier.fingerprint(at: backup) == sourceBefore)
        let imported = try #require(await result.store.allNotes().first)
        #expect(imported.content.text == "café")
        #expect(await result.store.record(for: imported.id) != nil)
        #expect(!String(data: try Data(contentsOf: dirs.documents.appendingPathComponent("Café.txt")), encoding: .utf8)!.contains(imported.id.description))
    }

    @Test("Encrypted sources require explicit plaintext confirmation before decryption")
    func encryptedConfirmation() async throws {
        let dirs = try TestDirectories()
        defer { dirs.remove() }
        let sourceURL = dirs.root.appendingPathComponent("Encrypted", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try Data("encrypted archive bytes".utf8).write(to: sourceURL.appendingPathComponent("Notes & Settings"))
        let probe = LoaderProbe()
        let source = LegacySnapshotSource(
            collectionURL: sourceURL,
            protection: .legacyApplicationEncryption
        ) { _ in
            probe.increment()
            throw LegacyCompatibilityError.wrongPassphrase
        }
        await #expect(throws: LegacyMigrationError.plaintextConfirmationRequired) {
            try await LegacyMigrationService().migrate(
                source: source,
                to: destination(for: dirs),
                confirmsPlaintextDestination: false
            )
        }
        #expect(probe.count == 0)
        #expect(!FileManager.default.fileExists(atPath: dirs.documents.path))
    }

    @Test("A failed conversion rolls back modern files while retaining the verified source backup")
    func rollback() async throws {
        let dirs = try TestDirectories()
        defer { dirs.remove() }
        let sourceURL = dirs.root.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try Data("archive".utf8).write(to: sourceURL.appendingPathComponent("Notes & Settings"))
        let date = Date(timeIntervalSince1970: 1)
        let source = LegacySnapshotSource(collectionURL: sourceURL, protection: .plaintext) { _ in
            LegacyCollectionSnapshot(sourceApplication: "fixture", notes: [
                LegacyNoteSnapshot(title: "valid", content: .init(format: .plainText, text: "one"), createdAt: date, modifiedAt: date),
                LegacyNoteSnapshot(title: "invalid", content: .init(format: .plainText, text: "two"), folder: "../escape", createdAt: date, modifiedAt: date)
            ])
        }
        await #expect(throws: (any Error).self) {
            try await LegacyMigrationService().migrate(
                source: source,
                to: destination(for: dirs),
                confirmsPlaintextDestination: false
            )
        }
        #expect(!FileManager.default.fileExists(atPath: dirs.documents.path))
        #expect(!FileManager.default.fileExists(atPath: dirs.reconciliation.path))
        #expect(FileManager.default.fileExists(atPath: dirs.root.appendingPathComponent("Backup").path))
    }

    private func destination(for dirs: TestDirectories) -> LegacyMigrationDestination {
        .init(
            documentsURL: dirs.documents,
            reconciliationURL: dirs.reconciliation,
            indexURL: dirs.index,
            retainedBackupURL: dirs.root.appendingPathComponent("Backup", isDirectory: true)
        )
    }
}

private var repositoryFixtures: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tests/macOS/Fixtures", isDirectory: true)
}
