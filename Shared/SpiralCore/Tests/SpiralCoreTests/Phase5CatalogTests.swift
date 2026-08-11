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
@testable import SpiralCore
import Testing

@Suite("Phase 5 SQLite summary and search catalog")
struct NoteCatalogTests {
    @Test("FTS search, ranking, snippets, pagination, and summaries survive reopen")
    func durableSearch() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try fixture.open()
        let olderID = NoteID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let pinnedID = NoteID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)

        try catalog.upsert(entry(
            id: olderID,
            title: "Architecture notes",
            body: "durable catalog uses sqlite full text search",
            tags: ["phase5"],
            modifiedAt: Date(timeIntervalSince1970: 10)
        ))
        try catalog.upsert(entry(
            id: pinnedID,
            title: "Pinned search plan",
            body: "durable catalog ranks this sqlite result",
            tags: ["phase5", "search"],
            modifiedAt: Date(timeIntervalSince1970: 20),
            isPinned: true
        ))

        let firstPage = try catalog.search(.init(text: "durab sql", limit: 1))
        #expect(firstPage.totalCount == 2)
        #expect(firstPage.hits.map(\.id) == [pinnedID])
        #expect(firstPage.hits[0].snippet.contains("durable catalog"))
        #expect(firstPage.coverage.isComplete)
        let secondPage = try catalog.search(.init(text: "\"full text\"", limit: 10))
        #expect(secondPage.hits.map(\.id) == [olderID])

        let reopened = try fixture.open()
        #expect(try reopened.summaries(limit: 1, offset: 0).totalCount == 2)
        #expect(try reopened.summaries(limit: 1, offset: 1).summaries.count == 1)
        #expect(try reopened.search(.init(text: "phase5")).totalCount == 2)
    }

    @Test("Offloaded text stays searchable and never-indexed coverage remains honest")
    func offloadAndCoverage() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try fixture.open()
        let staleID = NoteID(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
        let neverID = NoteID(UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)
        let privateID = NoteID(UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)

        var stale = summary(id: staleID, title: "Downloaded", hash: "revision-a")
        try catalog.upsert(.init(
            summary: stale,
            textUpdate: .replace(text: "offline searchable phrase", revision: "revision-a")
        ))
        stale.bodyAvailability = .notDownloaded
        stale.pairingState = .awaitingBody
        try catalog.upsert(.init(summary: stale, textUpdate: .preserveAsStale))

        var never = summary(id: neverID, title: "Cloud placeholder", hash: "revision-b")
        never.bodyAvailability = .notDownloaded
        never.pairingState = .awaitingBody
        try catalog.upsert(.init(summary: never, textUpdate: .remove))

        var privateSummary = summary(id: privateID, title: "Private secret", hash: "revision-c")
        try catalog.upsert(.init(
            summary: privateSummary,
            textUpdate: .replace(text: "must never remain searchable", revision: "revision-c")
        ))
        privateSummary.isPrivate = true
        privateSummary.isSearchEligible = false
        try catalog.upsert(.init(
            summary: privateSummary,
            textUpdate: .replace(text: "must never remain searchable", revision: "revision-c")
        ))

        let staleResult = try catalog.search(.init(text: "offline searchable"))
        #expect(staleResult.hits.map(\.id) == [staleID])
        #expect(staleResult.hits[0].summary.searchFreshness == .stale)
        #expect(staleResult.hits[0].summary.bodyAvailability == .notDownloaded)
        #expect(staleResult.coverage.eligibleCount == 2)
        #expect(staleResult.coverage.staleCount == 1)
        #expect(staleResult.coverage.neverIndexedCount == 1)
        #expect(staleResult.coverage.excludedCount == 1)
        #expect(!staleResult.coverage.isComplete)

        let placeholder = try catalog.search(.init(text: "placeholder"))
        #expect(placeholder.hits.map(\.id) == [neverID])
        #expect(placeholder.hits[0].summary.searchFreshness == .neverIndexed)
        #expect(try catalog.search(.init(text: "private secret")).hits.isEmpty)
        #expect(try catalog.search(.init(text: "must never")).hits.isEmpty)
        let catalogFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        for url in catalogFiles {
            let bytes = try Data(contentsOf: url)
            #expect(!bytes.contains(Data("must never remain searchable".utf8)))
        }
    }

    @Test("Catalog scope, aliases, provisional discoveries, and operations are durable")
    func recoveryStateAndScope() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try fixture.open()
        let canonicalID = NoteID(UUID(uuidString: "66666666-6666-6666-6666-666666666666")!)
        let aliasID = NoteID(UUID(uuidString: "77777777-7777-7777-7777-777777777777")!)
        let provisionalID = NoteID(UUID(uuidString: "88888888-8888-8888-8888-888888888888")!)
        let operationID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        try catalog.upsert(entry(id: canonicalID, title: "Canonical", body: "body"))
        try catalog.addAlias(aliasID, canonicalID: canonicalID)
        try catalog.store(.init(
            localID: provisionalID,
            normalizedRelativePath: "outside.txt",
            contentHash: "hash",
            observationGeneration: 42,
            observedAt: Date(timeIntervalSince1970: 50)
        ))
        try catalog.store(.init(
            id: operationID,
            noteID: canonicalID,
            kind: "move",
            state: "recordPublished",
            updatedAt: Date(timeIntervalSince1970: 60)
        ))

        let reopened = try fixture.open()
        #expect(try reopened.resolve(aliasID) == canonicalID)
        #expect(try reopened.provisionalDiscoveries().map(\.localID) == [provisionalID])
        #expect(try reopened.operationSummaries().map(\.id) == [operationID])

        do {
            _ = try NoteCatalog(
                databaseURL: fixture.database,
                scope: .init(accountIdentifier: "another-account", collectionIdentifier: "collection")
            )
            Issue.record("Expected a catalog from another account to be refused")
        } catch let error as NoteCatalogError {
            #expect(error == .scopeMismatch(
                expected: .init(accountIdentifier: "another-account", collectionIdentifier: "collection"),
                actual: fixture.scope
            ))
        }
    }

    @Test("Local NoteStore routes mutation and search through the catalog")
    func localStoreIntegration() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let store = try await LocalNoteStore.open(
            documentsURL: fixture.root.appendingPathComponent("Documents", isDirectory: true),
            reconciliationURL: fixture.root.appendingPathComponent("Reconciliation", isDirectory: true),
            indexURL: fixture.database
        )
        let searchable = try await store.create(Note(
            title: "Roadmap",
            content: .init(format: .plainText, text: "bounded hydration work"),
            tags: ["phase5"]
        ))
        _ = try await store.create(Note(
            title: "Private roadmap",
            content: .init(format: .plainText, text: "bounded private body"),
            isPrivate: true
        ))

        #expect(try await store.search(.init(text: "bounded")).hits.map(\.id) == [searchable.id])
        #expect(try await store.summaries(limit: 10, offset: 0).totalCount == 2)
        try await store.delete(id: searchable.id)
        #expect(try await store.search(.init(text: "hydration")).hits.isEmpty)
    }

    private func entry(
        id: NoteID,
        title: String,
        body: String,
        tags: [String] = [],
        modifiedAt: Date = Date(timeIntervalSince1970: 1),
        isPinned: Bool = false
    ) -> NoteCatalogEntry {
        let revision = ContentHash.sha256(Data(body.utf8))
        return NoteCatalogEntry(
            summary: NoteSummary(
                id: id,
                title: title,
                tags: tags,
                createdAt: Date(timeIntervalSince1970: 1),
                modifiedAt: modifiedAt,
                isPinned: isPinned,
                relativePath: "\(title).txt",
                contentHash: revision,
                lastIndexedRevision: revision
            ),
            textUpdate: .replace(text: body, revision: revision)
        )
    }

    private func summary(id: NoteID, title: String, hash: String) -> NoteSummary {
        NoteSummary(
            id: id,
            title: title,
            createdAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: 2),
            relativePath: "\(title).txt",
            contentHash: hash,
            lastIndexedRevision: hash
        )
    }
}

private struct CatalogFixture {
    let root: URL
    let database: URL
    let scope = NoteCatalogScope(accountIdentifier: "account", collectionIdentifier: "collection")

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SpiralCatalogTests-\(UUID().uuidString)",
            isDirectory: true
        )
        database = root.appendingPathComponent("Catalog.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func open() throws -> NoteCatalog {
        try NoteCatalog(databaseURL: database, scope: scope)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
