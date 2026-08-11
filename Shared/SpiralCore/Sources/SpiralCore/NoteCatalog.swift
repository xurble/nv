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
import SQLite3

public struct NoteCatalogScope: Hashable, Codable, Sendable {
    public let accountIdentifier: String
    public let collectionIdentifier: String

    public init(accountIdentifier: String, collectionIdentifier: String) {
        self.accountIdentifier = accountIdentifier
        self.collectionIdentifier = collectionIdentifier
    }

    /// The ubiquity token is opaque and meaningful only on this client, which
    /// is exactly the boundary needed to prevent one signed-in account from
    /// reopening another account's local catalog.
    public static func currentICloud(
        collectionIdentifier: String,
        fileManager: FileManager = .default
    ) throws -> NoteCatalogScope {
        guard let token = fileManager.ubiquityIdentityToken else {
            throw NoteCatalogError.iCloudAccountUnavailable
        }
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: false
        )
        return NoteCatalogScope(
            accountIdentifier: ContentHash.sha256(data),
            collectionIdentifier: collectionIdentifier
        )
    }
}

public enum NoteCatalogError: Error, Equatable, Sendable {
    case iCloudAccountUnavailable
    case unsafeDatabaseURL
    case databaseOpenFailed(String)
    case databaseOperationFailed(String)
    case scopeMismatch(expected: NoteCatalogScope, actual: NoteCatalogScope)
    case unsupportedSchema(Int)
    case invalidStoredValue(String)
}

public enum NoteCatalogTextUpdate: Equatable, Sendable {
    case replace(text: String, revision: String)
    case preserveAsStale
    case remove
}

public struct NoteCatalogEntry: Equatable, Sendable {
    public var summary: NoteSummary
    public var textUpdate: NoteCatalogTextUpdate

    public init(summary: NoteSummary, textUpdate: NoteCatalogTextUpdate) {
        self.summary = summary
        self.textUpdate = textUpdate
    }
}

public struct NoteCatalogProvisionalDiscovery: Equatable, Sendable {
    public let localID: NoteID
    public let normalizedRelativePath: String
    public let contentHash: String
    public let observationGeneration: Int64
    public let observedAt: Date

    public init(
        localID: NoteID,
        normalizedRelativePath: String,
        contentHash: String,
        observationGeneration: Int64,
        observedAt: Date
    ) {
        self.localID = localID
        self.normalizedRelativePath = normalizedRelativePath
        self.contentHash = contentHash
        self.observationGeneration = observationGeneration
        self.observedAt = observedAt
    }
}

public struct NoteCatalogOperationSummary: Equatable, Sendable {
    public let id: UUID
    public let noteID: NoteID?
    public let kind: String
    public let state: String
    public let updatedAt: Date

    public init(id: UUID, noteID: NoteID?, kind: String, state: String, updatedAt: Date) {
        self.id = id
        self.noteID = noteID
        self.kind = kind
        self.state = state
        self.updatedAt = updatedAt
    }
}

struct NoteCatalogHydrationCounts: Equatable, Sendable {
    let pending: Int
    let remaining: Int
}

/// A local, rebuildable SQLite catalog. The synchronized document and
/// reconciliation stores remain authoritative; this database exists only to
/// make body-independent listing, offload-aware search, and recovery fast.
public final class NoteCatalog: @unchecked Sendable {
    public static let currentSchemaVersion = 1

    public let databaseURL: URL
    public let scope: NoteCatalogScope

    private let lock = NSLock()
    private let database: SQLiteDatabase

    public init(databaseURL: URL, scope: NoteCatalogScope) throws {
        let standardized = databaseURL.standardizedFileURL
        guard standardized.isFileURL, standardized.path != "/", !standardized.path.isEmpty else {
            throw NoteCatalogError.unsafeDatabaseURL
        }
        let parent = standardized.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) {
            let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw NoteCatalogError.unsafeDatabaseURL
            }
        } else {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: parent.path
        )
        #endif
        if FileManager.default.fileExists(atPath: standardized.path) {
            let values = try standardized.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw NoteCatalogError.unsafeDatabaseURL
            }
        }

        database = try SQLiteDatabase(url: standardized)
        self.databaseURL = standardized
        self.scope = scope
        try prepareSchemaAndScope()
    }

    public func upsert(_ entry: NoteCatalogEntry) throws {
        try lock.withLock {
            try transaction {
                try upsertUnlocked(entry)
            }
            if entry.summary.isPrivate || !entry.summary.isSearchEligible {
                try purgeDeletedContentUnlocked()
            }
        }
    }

    public func replaceAll(with entries: [NoteCatalogEntry]) throws {
        try lock.withLock {
            try transaction {
                for entry in entries {
                    try upsertUnlocked(entry)
                }
                let retained = Set(entries.map { $0.summary.id.description })
                let existing = try database.query("SELECT note_id FROM notes")
                    .compactMap { $0.optionalText(at: 0) }
                for noteID in existing where !retained.contains(noteID) {
                    try database.execute(
                        "DELETE FROM note_search WHERE note_id = ?",
                        bindings: [.text(noteID)]
                    )
                    try database.execute(
                        "DELETE FROM notes WHERE note_id = ?",
                        bindings: [.text(noteID)]
                    )
                }
            }
            try purgeDeletedContentUnlocked()
        }
    }

    public func remove(noteID: NoteID) throws {
        try lock.withLock {
            try transaction {
                try database.execute(
                    "DELETE FROM note_search WHERE note_id = ?",
                    bindings: [.text(noteID.description)]
                )
                try database.execute(
                    "DELETE FROM notes WHERE note_id = ?",
                    bindings: [.text(noteID.description)]
                )
            }
            try purgeDeletedContentUnlocked()
        }
    }

    public func summary(id: NoteID) throws -> NoteSummary? {
        try lock.withLock {
            let rows = try database.query(
                Self.summarySelect + " WHERE note_id = ? LIMIT 1",
                bindings: [.text(id.description)]
            )
            return try rows.first.map(Self.decodeSummary)
        }
    }

    public func summaries(limit: Int = 100, offset: Int = 0) throws -> NoteSummaryPage {
        try lock.withLock {
            let safeLimit = max(0, min(limit, 1_000))
            let safeOffset = max(0, offset)
            let total = try database.scalarInt("SELECT count(*) FROM notes")
            let rows = try database.query(
                Self.summarySelect
                    + " ORDER BY is_pinned DESC, modified_at DESC, title COLLATE NOCASE, note_id"
                    + " LIMIT ? OFFSET ?",
                bindings: [.integer(Int64(safeLimit)), .integer(Int64(safeOffset))]
            )
            return NoteSummaryPage(
                summaries: try rows.map(Self.decodeSummary),
                offset: safeOffset,
                totalCount: total
            )
        }
    }

    func hydrationCounts() throws -> NoteCatalogHydrationCounts {
        try lock.withLock {
            let row = try database.query(
                """
                SELECT
                    sum(CASE WHEN body_availability = 'downloadPending' THEN 1 ELSE 0 END),
                    sum(CASE WHEN body_availability IN ('notDownloaded', 'available') THEN 1 ELSE 0 END)
                FROM notes
                WHERE search_eligible = 1 AND search_freshness = 'neverIndexed'
                """
            )[0]
            return NoteCatalogHydrationCounts(
                pending: Int(row.integer(at: 0)),
                remaining: Int(row.integer(at: 1))
            )
        }
    }

    func hydrationCandidates(limit: Int) throws -> [NoteSummary] {
        try lock.withLock {
            let safeLimit = max(0, min(limit, 64))
            let rows = try database.query(
                Self.summarySelect
                    + " WHERE search_eligible = 1"
                    + " AND search_freshness = 'neverIndexed'"
                    + " AND body_availability IN ('notDownloaded', 'available')"
                    + " ORDER BY is_pinned DESC, modified_at DESC, title COLLATE NOCASE, note_id"
                    + " LIMIT ?",
                bindings: [.integer(Int64(safeLimit))]
            )
            return try rows.map(Self.decodeSummary)
        }
    }

    public func search(_ request: NoteSearchRequest) throws -> NoteSearchPage {
        try lock.withLock {
            let safeLimit = max(0, min(request.limit, 500))
            let safeOffset = max(0, request.offset)
            let coverage = try searchCoverageUnlocked()
            guard let expression = Self.matchExpression(for: request.text) else {
                let summaries = try summariesUnlocked(
                    eligibleOnly: true,
                    limit: safeLimit,
                    offset: safeOffset
                )
                return NoteSearchPage(
                    hits: summaries.summaries.map {
                        NoteSearchHit(summary: $0, snippet: "", relevance: $0.isPinned ? 1 : 0)
                    },
                    offset: safeOffset,
                    totalCount: summaries.totalCount,
                    coverage: coverage
                )
            }

            let total = try database.scalarInt(
                """
                SELECT count(*)
                FROM note_search
                JOIN notes ON notes.note_id = note_search.note_id
                WHERE note_search MATCH ? AND notes.search_eligible = 1
                """,
                bindings: [.text(expression)]
            )
            let rows = try database.query(
                """
                SELECT \(Self.summaryColumns),
                       snippet(note_search, 2, '', '', ' … ', 24),
                       bm25(note_search, 8.0, 1.0, 3.0, 2.0)
                FROM note_search
                JOIN notes ON notes.note_id = note_search.note_id
                WHERE note_search MATCH ? AND notes.search_eligible = 1
                ORDER BY notes.is_pinned DESC,
                         bm25(note_search, 8.0, 1.0, 3.0, 2.0),
                         notes.modified_at DESC,
                         notes.note_id
                LIMIT ? OFFSET ?
                """,
                bindings: [
                    .text(expression),
                    .integer(Int64(safeLimit)),
                    .integer(Int64(safeOffset))
                ]
            )
            let hits = try rows.map { row in
                let summary = try Self.decodeSummary(row)
                let rawRank = row.double(at: Self.summaryColumnCount + 1)
                return NoteSearchHit(
                    summary: summary,
                    snippet: row.optionalText(at: Self.summaryColumnCount) ?? "",
                    relevance: -rawRank + (summary.isPinned ? 1 : 0)
                )
            }
            return NoteSearchPage(
                hits: hits,
                offset: safeOffset,
                totalCount: total,
                coverage: coverage
            )
        }
    }

    public func addAlias(_ alias: NoteID, canonicalID: NoteID) throws {
        try lock.withLock {
            try database.execute(
                """
                INSERT INTO aliases(alias_id, canonical_id) VALUES(?, ?)
                ON CONFLICT(alias_id) DO UPDATE SET canonical_id = excluded.canonical_id
                """,
                bindings: [.text(alias.description), .text(canonicalID.description)]
            )
        }
    }

    public func resolve(_ id: NoteID) throws -> NoteID? {
        try lock.withLock {
            if try database.scalarInt(
                "SELECT count(*) FROM notes WHERE note_id = ?",
                bindings: [.text(id.description)]
            ) == 1 {
                return id
            }
            let rows = try database.query(
                "SELECT canonical_id FROM aliases WHERE alias_id = ? LIMIT 1",
                bindings: [.text(id.description)]
            )
            guard let value = rows.first?.optionalText(at: 0), let uuid = UUID(uuidString: value) else {
                return nil
            }
            return NoteID(uuid)
        }
    }

    public func store(_ discovery: NoteCatalogProvisionalDiscovery) throws {
        try lock.withLock {
            try database.execute(
                """
                INSERT INTO provisional_discoveries(
                    local_id, normalized_path, content_hash, observation_generation, observed_at
                ) VALUES(?, ?, ?, ?, ?)
                ON CONFLICT(local_id) DO UPDATE SET
                    normalized_path = excluded.normalized_path,
                    content_hash = excluded.content_hash,
                    observation_generation = excluded.observation_generation,
                    observed_at = excluded.observed_at
                """,
                bindings: [
                    .text(discovery.localID.description),
                    .text(discovery.normalizedRelativePath),
                    .text(discovery.contentHash),
                    .integer(discovery.observationGeneration),
                    .double(discovery.observedAt.timeIntervalSince1970)
                ]
            )
        }
    }

    public func provisionalDiscoveries() throws -> [NoteCatalogProvisionalDiscovery] {
        try lock.withLock {
            try database.query(
                """
                SELECT local_id, normalized_path, content_hash, observation_generation, observed_at
                FROM provisional_discoveries ORDER BY observed_at, local_id
                """
            ).map { row in
                NoteCatalogProvisionalDiscovery(
                    localID: try Self.noteID(try row.requiredText(at: 0)),
                    normalizedRelativePath: try row.requiredText(at: 1),
                    contentHash: try row.requiredText(at: 2),
                    observationGeneration: row.integer(at: 3),
                    observedAt: Date(timeIntervalSince1970: row.double(at: 4))
                )
            }
        }
    }

    public func removeProvisionalDiscovery(localID: NoteID) throws {
        try lock.withLock {
            try database.execute(
                "DELETE FROM provisional_discoveries WHERE local_id = ?",
                bindings: [.text(localID.description)]
            )
        }
    }

    public func store(_ operation: NoteCatalogOperationSummary) throws {
        try lock.withLock {
            try database.execute(
                """
                INSERT INTO operation_summaries(operation_id, note_id, kind, state, updated_at)
                VALUES(?, ?, ?, ?, ?)
                ON CONFLICT(operation_id) DO UPDATE SET
                    note_id = excluded.note_id,
                    kind = excluded.kind,
                    state = excluded.state,
                    updated_at = excluded.updated_at
                """,
                bindings: [
                    .text(operation.id.uuidString.lowercased()),
                    operation.noteID.map { .text($0.description) } ?? .null,
                    .text(operation.kind),
                    .text(operation.state),
                    .double(operation.updatedAt.timeIntervalSince1970)
                ]
            )
        }
    }

    public func operationSummaries() throws -> [NoteCatalogOperationSummary] {
        try lock.withLock {
            try database.query(
                """
                SELECT operation_id, note_id, kind, state, updated_at
                FROM operation_summaries ORDER BY updated_at, operation_id
                """
            ).map { row in
                guard let operationID = UUID(uuidString: try row.requiredText(at: 0)) else {
                    throw NoteCatalogError.invalidStoredValue("operation_id")
                }
                let noteID = try row.optionalText(at: 1).map(Self.noteID)
                return NoteCatalogOperationSummary(
                    id: operationID,
                    noteID: noteID,
                    kind: try row.requiredText(at: 2),
                    state: try row.requiredText(at: 3),
                    updatedAt: Date(timeIntervalSince1970: row.double(at: 4))
                )
            }
        }
    }

    public func removeOperation(id: UUID) throws {
        try lock.withLock {
            try database.execute(
                "DELETE FROM operation_summaries WHERE operation_id = ?",
                bindings: [.text(id.uuidString.lowercased())]
            )
        }
    }

    private func prepareSchemaAndScope() throws {
        try lock.withLock {
            try database.execute("PRAGMA journal_mode = WAL")
            try database.execute("PRAGMA synchronous = NORMAL")
            try database.execute("PRAGMA foreign_keys = ON")
            try database.execute("PRAGMA secure_delete = ON")
            let version = try database.scalarInt("PRAGMA user_version")
            guard version == 0 || version == Self.currentSchemaVersion else {
                throw NoteCatalogError.unsupportedSchema(version)
            }
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS catalog_metadata(
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                ) WITHOUT ROWID
                """
            )
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS notes(
                    note_id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    folder TEXT,
                    tags_json TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    modified_at REAL NOT NULL,
                    is_pinned INTEGER NOT NULL,
                    is_private INTEGER NOT NULL,
                    relative_path TEXT,
                    content_hash TEXT,
                    body_availability TEXT NOT NULL,
                    metadata_availability TEXT NOT NULL,
                    search_freshness TEXT NOT NULL,
                    last_indexed_revision TEXT,
                    pairing_state TEXT NOT NULL,
                    search_eligible INTEGER NOT NULL,
                    indexed_text TEXT
                ) WITHOUT ROWID
                """
            )
            try database.execute(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS note_search USING fts5(
                    note_id UNINDEXED,
                    title,
                    body,
                    tags,
                    folder,
                    tokenize = 'unicode61 remove_diacritics 2',
                    prefix = '2 3 4'
                )
                """
            )
            try database.execute(
                "INSERT INTO note_search(note_search, rank) VALUES('secure-delete', 1)"
            )
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS aliases(
                    alias_id TEXT PRIMARY KEY NOT NULL,
                    canonical_id TEXT NOT NULL REFERENCES notes(note_id) ON DELETE CASCADE
                ) WITHOUT ROWID
                """
            )
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS provisional_discoveries(
                    local_id TEXT PRIMARY KEY NOT NULL,
                    normalized_path TEXT NOT NULL,
                    content_hash TEXT NOT NULL,
                    observation_generation INTEGER NOT NULL,
                    observed_at REAL NOT NULL
                ) WITHOUT ROWID
                """
            )
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS operation_summaries(
                    operation_id TEXT PRIMARY KEY NOT NULL,
                    note_id TEXT,
                    kind TEXT NOT NULL,
                    state TEXT NOT NULL,
                    updated_at REAL NOT NULL
                ) WITHOUT ROWID
                """
            )
            try database.execute("PRAGMA user_version = \(Self.currentSchemaVersion)")

            let storedAccount = try metadataValue(for: "accountIdentifier")
            let storedCollection = try metadataValue(for: "collectionIdentifier")
            if let storedAccount, let storedCollection {
                let actual = NoteCatalogScope(
                    accountIdentifier: storedAccount,
                    collectionIdentifier: storedCollection
                )
                guard actual == scope else {
                    throw NoteCatalogError.scopeMismatch(expected: scope, actual: actual)
                }
            } else if storedAccount == nil, storedCollection == nil {
                try database.execute(
                    "INSERT INTO catalog_metadata(key, value) VALUES(?, ?), (?, ?)",
                    bindings: [
                        .text("accountIdentifier"), .text(scope.accountIdentifier),
                        .text("collectionIdentifier"), .text(scope.collectionIdentifier)
                    ]
                )
            } else {
                throw NoteCatalogError.invalidStoredValue("catalog scope")
            }
        }
    }

    private func metadataValue(for key: String) throws -> String? {
        try database.query(
            "SELECT value FROM catalog_metadata WHERE key = ? LIMIT 1",
            bindings: [.text(key)]
        ).first?.optionalText(at: 0)
    }

    private func upsertUnlocked(_ entry: NoteCatalogEntry) throws {
        let existing = try database.query(
            "SELECT indexed_text, last_indexed_revision FROM notes WHERE note_id = ? LIMIT 1",
            bindings: [.text(entry.summary.id.description)]
        ).first
        var summary = entry.summary
        summary.isSearchEligible = summary.isSearchEligible && !summary.isPrivate
        let indexedText: String?
        switch entry.textUpdate {
        case let .replace(text, revision):
            if summary.isSearchEligible {
                indexedText = text
                summary.searchFreshness = .current
                summary.lastIndexedRevision = revision
            } else {
                indexedText = nil
                summary.searchFreshness = .excluded
                summary.lastIndexedRevision = nil
            }
        case .preserveAsStale:
            if summary.isSearchEligible {
                indexedText = existing?.optionalText(at: 0)
                summary.lastIndexedRevision = existing?.optionalText(at: 1)
                summary.searchFreshness = indexedText == nil ? .neverIndexed : .stale
            } else {
                indexedText = nil
                summary.searchFreshness = .excluded
                summary.lastIndexedRevision = nil
            }
        case .remove:
            indexedText = nil
            summary.lastIndexedRevision = nil
            summary.searchFreshness = summary.isSearchEligible ? .neverIndexed : .excluded
        }

        let tagsJSON = try Self.encodeTags(summary.tags)
        try database.execute(
            """
            INSERT INTO notes(
                note_id, title, folder, tags_json, created_at, modified_at,
                is_pinned, is_private, relative_path, content_hash,
                body_availability, metadata_availability, search_freshness,
                last_indexed_revision, pairing_state, search_eligible, indexed_text
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(note_id) DO UPDATE SET
                title = excluded.title,
                folder = excluded.folder,
                tags_json = excluded.tags_json,
                created_at = excluded.created_at,
                modified_at = excluded.modified_at,
                is_pinned = excluded.is_pinned,
                is_private = excluded.is_private,
                relative_path = excluded.relative_path,
                content_hash = excluded.content_hash,
                body_availability = excluded.body_availability,
                metadata_availability = excluded.metadata_availability,
                search_freshness = excluded.search_freshness,
                last_indexed_revision = excluded.last_indexed_revision,
                pairing_state = excluded.pairing_state,
                search_eligible = excluded.search_eligible,
                indexed_text = excluded.indexed_text
            """,
            bindings: [
                .text(summary.id.description),
                .text(summary.title),
                summary.folder.map(SQLiteBinding.text) ?? .null,
                .text(tagsJSON),
                .double(summary.createdAt.timeIntervalSince1970),
                .double(summary.modifiedAt.timeIntervalSince1970),
                .integer(summary.isPinned ? 1 : 0),
                .integer(summary.isPrivate ? 1 : 0),
                summary.relativePath.map(SQLiteBinding.text) ?? .null,
                summary.contentHash.map(SQLiteBinding.text) ?? .null,
                .text(summary.bodyAvailability.rawValue),
                .text(summary.metadataAvailability.rawValue),
                .text(summary.searchFreshness.rawValue),
                summary.lastIndexedRevision.map(SQLiteBinding.text) ?? .null,
                .text(summary.pairingState.rawValue),
                .integer(summary.isSearchEligible ? 1 : 0),
                indexedText.map(SQLiteBinding.text) ?? .null
            ]
        )
        try database.execute(
            "DELETE FROM note_search WHERE note_id = ?",
            bindings: [.text(summary.id.description)]
        )
        if summary.isSearchEligible {
            try database.execute(
                "INSERT INTO note_search(note_id, title, body, tags, folder) VALUES(?, ?, ?, ?, ?)",
                bindings: [
                    .text(summary.id.description),
                    .text(summary.title),
                    .text(indexedText ?? ""),
                    .text(summary.tags.joined(separator: " ")),
                    .text(summary.folder ?? "")
                ]
            )
        }
    }

    private func searchCoverageUnlocked() throws -> NoteSearchCoverage {
        let rows = try database.query(
            """
            SELECT
                sum(CASE WHEN search_eligible = 1 THEN 1 ELSE 0 END),
                sum(CASE WHEN search_freshness = 'current' THEN 1 ELSE 0 END),
                sum(CASE WHEN search_freshness = 'stale' THEN 1 ELSE 0 END),
                sum(CASE WHEN search_freshness = 'neverIndexed' THEN 1 ELSE 0 END),
                sum(CASE WHEN search_freshness = 'excluded' THEN 1 ELSE 0 END)
            FROM notes
            """
        )
        let row = rows[0]
        return NoteSearchCoverage(
            eligibleCount: Int(row.integer(at: 0)),
            currentCount: Int(row.integer(at: 1)),
            staleCount: Int(row.integer(at: 2)),
            neverIndexedCount: Int(row.integer(at: 3)),
            excludedCount: Int(row.integer(at: 4))
        )
    }

    private func summariesUnlocked(
        eligibleOnly: Bool,
        limit: Int,
        offset: Int
    ) throws -> NoteSummaryPage {
        let predicate = eligibleOnly ? " WHERE search_eligible = 1" : ""
        let total = try database.scalarInt("SELECT count(*) FROM notes" + predicate)
        let rows = try database.query(
            Self.summarySelect + predicate
                + " ORDER BY is_pinned DESC, modified_at DESC, title COLLATE NOCASE, note_id"
                + " LIMIT ? OFFSET ?",
            bindings: [.integer(Int64(limit)), .integer(Int64(offset))]
        )
        return NoteSummaryPage(
            summaries: try rows.map(Self.decodeSummary),
            offset: offset,
            totalCount: total
        )
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try database.execute("BEGIN IMMEDIATE")
        do {
            try operation()
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    private func purgeDeletedContentUnlocked() throws {
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    private static let summaryColumns = """
        notes.note_id, notes.title, notes.folder, notes.tags_json,
        notes.created_at, notes.modified_at, notes.is_pinned, notes.is_private,
        notes.relative_path, notes.content_hash, notes.body_availability,
        notes.metadata_availability, notes.search_freshness,
        notes.last_indexed_revision, notes.pairing_state, notes.search_eligible
        """
    private static let summaryColumnCount = 16
    private static let summarySelect = "SELECT \(summaryColumns) FROM notes"

    private static func decodeSummary(_ row: SQLiteRow) throws -> NoteSummary {
        guard let bodyAvailability = NoteBodyAvailability(rawValue: try row.requiredText(at: 10)),
              let metadataAvailability = NoteMetadataAvailability(rawValue: try row.requiredText(at: 11)),
              let searchFreshness = NoteSearchFreshness(rawValue: try row.requiredText(at: 12)),
              let pairingState = NotePairingState(rawValue: try row.requiredText(at: 14)) else {
            throw NoteCatalogError.invalidStoredValue("summary state")
        }
        return NoteSummary(
            id: try noteID(try row.requiredText(at: 0)),
            title: try row.requiredText(at: 1),
            folder: row.optionalText(at: 2),
            tags: try decodeTags(try row.requiredText(at: 3)),
            createdAt: Date(timeIntervalSince1970: row.double(at: 4)),
            modifiedAt: Date(timeIntervalSince1970: row.double(at: 5)),
            isPinned: row.integer(at: 6) != 0,
            isPrivate: row.integer(at: 7) != 0,
            relativePath: row.optionalText(at: 8),
            contentHash: row.optionalText(at: 9),
            bodyAvailability: bodyAvailability,
            metadataAvailability: metadataAvailability,
            searchFreshness: searchFreshness,
            lastIndexedRevision: row.optionalText(at: 13),
            pairingState: pairingState,
            isSearchEligible: row.integer(at: 15) != 0
        )
    }

    private static func encodeTags(_ tags: [String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(tags)
        guard let result = String(data: data, encoding: .utf8) else {
            throw NoteCatalogError.invalidStoredValue("tags")
        }
        return result
    }

    private static func decodeTags(_ value: String) throws -> [String] {
        guard let data = value.data(using: .utf8) else {
            throw NoteCatalogError.invalidStoredValue("tags")
        }
        return try JSONDecoder().decode([String].self, from: data)
    }

    private static func noteID(_ value: String) throws -> NoteID {
        guard let uuid = UUID(uuidString: value) else {
            throw NoteCatalogError.invalidStoredValue("note_id")
        }
        return NoteID(uuid)
    }

    private static func matchExpression(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var terms: [(text: String, phrase: Bool)] = []
        var current = ""
        var inPhrase = false
        for character in trimmed {
            if character == "\"" {
                if inPhrase, !current.isEmpty {
                    terms.append((current, true))
                    current = ""
                } else if !inPhrase, !current.isEmpty {
                    terms.append((current, false))
                    current = ""
                }
                inPhrase.toggle()
            } else if character.isWhitespace, !inPhrase {
                if !current.isEmpty {
                    terms.append((current, false))
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { terms.append((current, inPhrase)) }
        guard !terms.isEmpty else { return nil }
        return terms.map { term in
            let escaped = term.text.replacingOccurrences(of: "\"", with: "\"\"")
            return term.phrase ? "\"\(escaped)\"" : "\"\(escaped)\"*"
        }.joined(separator: " AND ")
    }
}

private enum SQLiteBinding {
    case null
    case integer(Int64)
    case double(Double)
    case text(String)
}

private struct SQLiteRow {
    private let values: [SQLiteValue]

    init(statement: OpaquePointer) {
        values = (0..<sqlite3_column_count(statement)).map { index in
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                return .integer(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT:
                return .double(sqlite3_column_double(statement, index))
            case SQLITE_TEXT:
                guard let pointer = sqlite3_column_text(statement, index) else { return .null }
                return .text(String(cString: pointer))
            default:
                return .null
            }
        }
    }

    func optionalText(at index: Int) -> String? {
        guard case let .text(value) = values[index] else { return nil }
        return value
    }

    func requiredText(at index: Int) throws -> String {
        guard let value = optionalText(at: index) else {
            throw NoteCatalogError.invalidStoredValue("column \(index)")
        }
        return value
    }

    func integer(at index: Int) -> Int64 {
        if case let .integer(value) = values[index] { return value }
        return 0
    }

    func double(at index: Int) -> Double {
        switch values[index] {
        case let .double(value): value
        case let .integer(value): Double(value)
        default: 0
        }
    }
}

private enum SQLiteValue {
    case null
    case integer(Int64)
    case double(Double)
    case text(String)
}

private final class SQLiteDatabase: @unchecked Sendable {
    private let handle: OpaquePointer

    init(url: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "SQLite returned \(result)"
            if let database { sqlite3_close(database) }
            throw NoteCatalogError.databaseOpenFailed(message)
        }
        handle = database
        sqlite3_busy_timeout(handle, 5_000)
    }

    deinit { sqlite3_close_v2(handle) }

    func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return }
            if result != SQLITE_ROW { throw operationError(sql) }
        }
    }

    func query(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw operationError(sql) }
            rows.append(SQLiteRow(statement: statement))
        }
    }

    func scalarInt(_ sql: String, bindings: [SQLiteBinding] = []) throws -> Int {
        Int(try query(sql, bindings: bindings).first?.integer(at: 0) ?? 0)
    }

    private func prepare(_ sql: String, bindings: [SQLiteBinding]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw operationError(sql)
        }
        do {
            for (offset, binding) in bindings.enumerated() {
                let index = Int32(offset + 1)
                let result: Int32
                switch binding {
                case .null:
                    result = sqlite3_bind_null(statement, index)
                case let .integer(value):
                    result = sqlite3_bind_int64(statement, index, value)
                case let .double(value):
                    result = sqlite3_bind_double(statement, index, value)
                case let .text(value):
                    result = value.withCString { pointer in
                        sqlite3_bind_text(statement, index, pointer, -1, sqliteTransient)
                    }
                }
                guard result == SQLITE_OK else { throw operationError(sql) }
            }
            return statement
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
    }

    private func operationError(_ sql: String) -> NoteCatalogError {
        NoteCatalogError.databaseOperationFailed("\(String(cString: sqlite3_errmsg(handle))) [\(sql)]")
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
