import Foundation

public enum LocalNoteStoreError: Error, Equatable, Sendable {
    case noteNotFound(NoteID)
    case duplicateIdentity(NoteID)
    case unsupportedFile(String)
    case unsafeFolder(String)
    case unsafePathComponent(String)
    case destinationNotEmpty
}

private struct LocalIndexEntry: Codable, Sendable {
    let id: NoteID
    let relativePath: String
    let title: String
    let contentHash: String
}

private struct LocalIndexFile: Codable, Sendable {
    let version: Int
    let entries: [LocalIndexEntry]
}

public actor LocalNoteStore: NoteStore {
    public let documentsURL: URL
    public let reconciliationURL: URL
    public let indexURL: URL

    private let codec: NoteFileCodec
    private let reconciliationStore: ReconciliationStore
    private var notesByID: [NoteID: Note] = [:]
    private var recordsByID: [NoteID: ReconciliationRecord] = [:]
    private var storedConflicts: [NoteConflict] = []
    private var pendingEvents: [NoteStoreEvent] = []

    public init(
        documentsURL: URL,
        reconciliationURL: URL,
        indexURL: URL,
        codec: NoteFileCodec = NoteFileCodec()
    ) {
        self.documentsURL = documentsURL
        self.reconciliationURL = reconciliationURL
        self.indexURL = indexURL
        self.codec = codec
        reconciliationStore = ReconciliationStore(rootURL: reconciliationURL)
    }

    public static func open(
        documentsURL: URL,
        reconciliationURL: URL,
        indexURL: URL
    ) async throws -> LocalNoteStore {
        let store = LocalNoteStore(
            documentsURL: documentsURL,
            reconciliationURL: reconciliationURL,
            indexURL: indexURL
        )
        try await store.reloadFromDisk()
        return store
    }

    public func reloadFromDisk() throws {
        try prepareDocumentsRoot()
        try reconciliationStore.prepare()
        recordsByID = try reconciliationStore.loadAll()
        notesByID.removeAll(keepingCapacity: true)

        var claimedIDs = Set<NoteID>()
        for fileURL in try canonicalFiles() {
            let relativePath = try relativePath(for: fileURL)
            let data = try Data(contentsOf: fileURL)
            let hash = ContentHash.sha256(data)
            let matchedRecord = recordsByID.values.first {
                !claimedIDs.contains($0.noteID) && (
                    $0.currentRelativePath == relativePath
                    || $0.recentRelativePaths.contains(relativePath)
                    || ($0.rawContentHash == hash && $0.currentRelativePath != relativePath)
                )
            }
            var record = matchedRecord ?? newRecord(for: fileURL, relativePath: relativePath, hash: hash)
            if matchedRecord != nil { record.move(to: relativePath) }
            record.rawContentHash = hash
            record.isTombstone = false
            try reconciliationStore.save(record)
            recordsByID[record.noteID] = record
            claimedIDs.insert(record.noteID)

            let content = try codec.decode(data, as: format(for: fileURL))
            notesByID[record.noteID] = Note(
                id: record.noteID,
                title: fileURL.deletingPathExtension().lastPathComponent,
                content: content,
                tags: record.tags,
                legacyMetadata: record.legacyMetadata,
                folder: folder(for: relativePath),
                createdAt: record.createdAt,
                modifiedAt: record.modifiedAt,
                isPinned: record.isPinned,
                isPrivate: record.isPrivate
            )
        }
        try rebuildIndex()
    }

    public func allNotes() -> [Note] {
        notesByID.values.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    public func note(id: NoteID) -> Note? { notesByID[id] }

    @discardableResult
    public func create(_ note: Note) throws -> Note {
        guard notesByID[note.id] == nil else { throw LocalNoteStoreError.duplicateIdentity(note.id) }
        var created = note
        let now = Date()
        if created.modifiedAt < created.createdAt { created.modifiedAt = now }
        let relativePath = try availableRelativePath(for: created, excluding: nil)
        let data = try codec.encode(created.content)
        try write(data, toRelativePath: relativePath)
        let record = ReconciliationRecord(
            noteID: created.id,
            currentRelativePath: relativePath,
            rawContentHash: ContentHash.sha256(data),
            lastCommonRevisionHash: ContentHash.sha256(data),
            mergeBaseContent: data,
            tags: created.tags,
            legacyMetadata: created.legacyMetadata,
            createdAt: created.createdAt,
            modifiedAt: created.modifiedAt,
            isPinned: created.isPinned,
            isPrivate: created.isPrivate
        )
        try reconciliationStore.save(record)
        notesByID[created.id] = created
        recordsByID[created.id] = record
        pendingEvents.append(.inserted(created.id))
        try rebuildIndex()
        return created
    }

    public func update(_ note: Note) throws {
        guard notesByID[note.id] != nil, var record = recordsByID[note.id] else {
            throw LocalNoteStoreError.noteNotFound(note.id)
        }
        let oldRelativePath = record.currentRelativePath
        let newRelativePath = try availableRelativePath(for: note, excluding: note.id)
        let data = try codec.encode(note.content)
        try write(data, toRelativePath: newRelativePath)
        if oldRelativePath != newRelativePath {
            let oldURL = documentsURL.appendingPathComponent(oldRelativePath)
            if FileManager.default.fileExists(atPath: oldURL.path) { try FileManager.default.removeItem(at: oldURL) }
            record.move(to: newRelativePath)
            pendingEvents.append(.moved(note.id))
        } else {
            pendingEvents.append(.updated(note.id))
        }
        record.rawContentHash = ContentHash.sha256(data)
        record.lastCommonRevisionHash = record.rawContentHash
        record.mergeBaseContent = data.count <= ReconciliationRecord.maximumMergeBaseBytes ? data : nil
        record.tags = note.tags
        record.legacyMetadata = note.legacyMetadata
        record.modifiedAt = note.modifiedAt
        record.isPinned = note.isPinned
        record.isPrivate = note.isPrivate
        record.isTombstone = false
        try reconciliationStore.save(record)
        recordsByID[note.id] = record
        notesByID[note.id] = note
        try rebuildIndex()
    }

    public func delete(id: NoteID) throws {
        guard notesByID.removeValue(forKey: id) != nil, var record = recordsByID[id] else {
            throw LocalNoteStoreError.noteNotFound(id)
        }
        let url = documentsURL.appendingPathComponent(record.currentRelativePath)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        record.isTombstone = true
        record.mergeBaseContent = nil
        try reconciliationStore.save(record)
        recordsByID[id] = record
        pendingEvents.append(.deleted(id))
        try rebuildIndex()
    }

    public func conflicts() -> [NoteConflict] { storedConflicts }

    public func recordConflict(_ conflict: NoteConflict) throws {
        guard recordsByID[conflict.noteID] != nil else {
            throw LocalNoteStoreError.noteNotFound(conflict.noteID)
        }
        storedConflicts.append(conflict)
        pendingEvents.append(.conflict(conflict.noteID))
    }

    public func drainEvents() -> [NoteStoreEvent] {
        defer { pendingEvents.removeAll(keepingCapacity: true) }
        return pendingEvents
    }

    public func rebuildIndex() throws {
        let entries = notesByID.values.compactMap { note -> LocalIndexEntry? in
            guard let record = recordsByID[note.id] else { return nil }
            return LocalIndexEntry(
                id: note.id,
                relativePath: record.currentRelativePath,
                title: note.title,
                contentHash: record.rawContentHash
            )
        }.sorted { $0.id.description < $1.id.description }
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(LocalIndexFile(version: 1, entries: entries))
            .write(to: indexURL, options: .atomic)
        pendingEvents.append(.rebuilt)
    }

    public func record(for id: NoteID) -> ReconciliationRecord? { recordsByID[id] }

    private func newRecord(for fileURL: URL, relativePath: String, hash: String) -> ReconciliationRecord {
        let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let created = values?.creationDate ?? Date()
        let modified = values?.contentModificationDate ?? created
        return ReconciliationRecord(
            noteID: NoteID(),
            currentRelativePath: relativePath,
            rawContentHash: hash,
            lastCommonRevisionHash: hash,
            mergeBaseContent: try? Data(contentsOf: fileURL),
            createdAt: created,
            modifiedAt: modified
        )
    }

    private func canonicalFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: documentsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { continue }
            if values.isRegularFile == true, NoteFormat.format(forPathExtension: url.pathExtension) != nil {
                result.append(url)
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    private func relativePath(for url: URL) throws -> String {
        let root = documentsURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { throw ReconciliationStoreError.unsafeRelativePath(path) }
        let relative = String(path.dropFirst(root.count + 1))
        try ReconciliationStore.validate(relativePath: relative)
        return relative
    }

    private func format(for url: URL) throws -> NoteFormat {
        guard let format = NoteFormat.format(forPathExtension: url.pathExtension) else {
            throw LocalNoteStoreError.unsupportedFile(url.lastPathComponent)
        }
        return format
    }

    private func folder(for relativePath: String) -> String? {
        let folder = (relativePath as NSString).deletingLastPathComponent
        return folder == "." || folder.isEmpty ? nil : folder
    }

    private func availableRelativePath(for note: Note, excluding noteID: NoteID?) throws -> String {
        let folder = try sanitizedFolder(note.folder)
        let base = sanitizedFilename(note.title)
        let ext = note.content.format.preferredPathExtension
        let existing = Set(recordsByID.compactMap { id, record in
            id == noteID || record.isTombstone ? nil : record.currentRelativePath.lowercased()
        })
        var counter = 0
        while true {
            let suffix = counter == 0 ? "" : " \(counter + 1)"
            let filename = "\(base)\(suffix).\(ext)"
            let path = folder.map { "\($0)/\(filename)" } ?? filename
            let onDiskURL = documentsURL.appendingPathComponent(path)
            let belongsToExcludedNote = noteID.flatMap { recordsByID[$0]?.currentRelativePath } == path
            if !existing.contains(path.lowercased())
                && (belongsToExcludedNote || !FileManager.default.fileExists(atPath: onDiskURL.path)) {
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

    private func write(_ data: Data, toRelativePath relativePath: String) throws {
        try ReconciliationStore.validate(relativePath: relativePath)
        try prepareDocumentsRoot()
        let components = relativePath.split(separator: "/").map(String.init)
        var parent = documentsURL
        for component in components.dropLast() {
            parent.appendPathComponent(component, isDirectory: true)
            if FileManager.default.fileExists(atPath: parent.path) {
                let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw LocalNoteStoreError.unsafePathComponent(component)
                }
            } else {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            }
        }
        let url = parent.appendingPathComponent(components.last!)
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw LocalNoteStoreError.unsafePathComponent(components.last!)
            }
        }
        try data.write(to: url, options: .atomic)
    }

    private func prepareDocumentsRoot() throws {
        if FileManager.default.fileExists(atPath: documentsURL.path) {
            let values = try documentsURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw LocalNoteStoreError.unsafePathComponent(documentsURL.lastPathComponent)
            }
        } else {
            try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }
    }
}
