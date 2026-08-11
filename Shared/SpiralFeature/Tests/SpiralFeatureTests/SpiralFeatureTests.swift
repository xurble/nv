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
import SpiralCore
@testable import SpiralFeature
import Testing

@Suite("Cross-platform feature state")
@MainActor
struct SpiralFeatureTests {
    @Test("Large collections page summaries and use indexed search without loading every body")
    func largeCollectionUsesCatalogBoundary() async throws {
        let notes = (0..<1_000).map { index in
            Note(
                title: "Note \(String(format: "%04d", index))",
                content: NoteContent(format: .plainText, text: index == 732 ? "needle body" : "body"),
                tags: index == 411 ? ["needle-tag"] : [],
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let store = CatalogBoundaryProbeStore(notes: notes)
        let model = SpiralFeatureModel(
            store: store,
            settings: SpiralFeatureSettings(sort: .title),
            summaryPageSize: 100,
            searchPageSize: 1,
            searchDebounce: .zero
        )

        await model.load()
        #expect(model.summaries.count == 100)
        #expect(model.totalNoteCount == 1_000)
        #expect(model.selectedNote?.title == "Note 0900")
        var calls = await store.calls()
        #expect(calls.summaryRequests == [.init(limit: 100, offset: 0)])
        #expect(calls.noteRequests.count == 1)
        #expect(calls.allNotes == 0)

        let lastSummary = try #require(model.visibleSummaries.last)
        await model.loadMoreIfNeeded(after: lastSummary.id)
        #expect(model.summaries.count == 200)
        #expect(model.hasMoreSummaries)

        model.searchText = "needle"
        await model.searchNow()
        #expect(model.visibleSummaries.map(\.title) == ["Note 0732"])
        #expect(model.preview(for: model.visibleSummaries[0].id) == "needle body")
        #expect(model.hasMoreSearchResults)

        let firstHit = try #require(model.visibleSummaries.last)
        await model.loadMoreIfNeeded(after: firstHit.id)
        #expect(model.visibleSummaries.map(\.title) == ["Note 0732", "Note 0411"])
        calls = await store.calls()
        #expect(calls.summaryRequests == [
            .init(limit: 100, offset: 0),
            .init(limit: 100, offset: 100)
        ])
        #expect(calls.searchRequests == [
            .init(text: "needle", limit: 1, offset: 0),
            .init(text: "needle", limit: 1, offset: 1)
        ])
        #expect(calls.noteRequests.count == 1)
        #expect(calls.allNotes == 0)
    }

    @Test("Selecting loads one body on demand and unavailable bodies stay read-only")
    func selectedBodyLoadsOnDemand() async throws {
        let available = Note(
            title: "Available",
            content: .init(format: .plainText, text: "editable"),
            modifiedAt: .now
        )
        let offloaded = Note(
            title: "Offloaded",
            content: .init(format: .plainText, text: "last indexed body"),
            modifiedAt: .distantPast
        )
        let store = CatalogBoundaryProbeStore(
            notes: [available, offloaded],
            unavailableIDs: [offloaded.id]
        )
        let model = SpiralFeatureModel(store: store, searchDebounce: .zero)

        await model.load()
        #expect(model.selectedNote?.id == available.id)
        model.selectNote(offloaded.id)
        await model.loadSelectedNote()

        #expect(model.selectedNoteID == offloaded.id)
        #expect(model.selectedNote == nil)
        #expect(model.selectedSummary?.bodyAvailability == .staleCachedCopy)
        #expect(!model.isLoadingSelectedNote)
        #expect(!model.selectedNoteSupportsTextEditing)

        await model.updateSelectedContent("must not save")
        await model.renameSelected(to: "must not rename")
        var calls = await store.calls()
        #expect(calls.noteRequests == [available.id, offloaded.id])
        #expect(calls.updateRequests == 0)

        model.searchText = "indexed"
        await model.searchNow()
        #expect(model.visibleSummaries.map(\.id) == [offloaded.id])
        #expect(model.searchStatusMessage == "1 indexed note may be out of date")
        calls = await store.calls()
        #expect(calls.noteRequests == [available.id, offloaded.id])
    }

    @Test("Delayed editor saves remain bound to their originating note")
    func delayedEditorSaveUsesOriginatingIdentity() async throws {
        let first = Note(
            title: "First",
            content: .init(format: .plainText, text: "first body"),
            modifiedAt: .now
        )
        let second = Note(
            title: "Second",
            content: .init(format: .plainText, text: "second body"),
            modifiedAt: .distantPast
        )
        let store = MemoryNoteStore(notes: [first, second])
        let model = SpiralFeatureModel(store: store)

        await model.load()
        model.selectNote(second.id)
        await model.loadSelectedNote()
        await model.updateContent(
            NoteContent(format: .plainText, text: "saved after selection changed"),
            for: first.id
        )
        await model.renameNote(id: first.id, to: "First Renamed")
        await model.setTags(for: first.id, from: "originating-note")

        let savedFirst = try #require(await store.note(id: first.id))
        let untouchedSecond = try #require(await store.note(id: second.id))
        #expect(savedFirst.title == "First Renamed")
        #expect(savedFirst.content.text == "saved after selection changed")
        #expect(savedFirst.tags == ["originating-note"])
        #expect(untouchedSecond.title == "Second")
        #expect(untouchedSecond.content.text == "second body")
        #expect(untouchedSecond.tags.isEmpty)
        #expect(model.selectedNote?.id == second.id)
    }

    @Test("Collection opening schedules one bounded hydration batch")
    func collectionOpenSchedulesBoundedHydration() async {
        let store = HydrationProbeStore()
        let model = SpiralFeatureModel(store: store, hydrationBatchSize: 2)

        await model.load()
        await model.waitForBackgroundHydration()

        #expect(await store.requestedMaximums() == [2])
        #expect(model.hydrationProgress?.pendingCount == 1)
        #expect(model.hydrationProgress?.remainingCount == 2)
        #expect(model.indexingStatusMessage == "3 notes still indexing")
        #expect(!model.isHydratingSearchIndex)
        let offloadedID = store.offloadedID
        #expect(model.summaries.first(where: { $0.id == offloadedID })?.bodyAvailability == .downloadPending)
    }

    @Test("Create, rename, edit, tag, pin, restore, and delete use NoteStore")
    func completeMutationWorkflow() async throws {
        let store = MemoryNoteStore()
        let model = SpiralFeatureModel(store: store)
        await model.load()
        #expect(model.phase == .empty)

        let created = try #require(await model.createNote())
        await model.renameSelected(to: "Roadmap")
        await model.updateSelectedContent("Ship the vertical slice")
        await model.setSelectedTags(from: "phase3, swiftui, phase3")
        await model.toggleSelectedPin()

        let saved = try #require(await store.note(id: created.id))
        #expect(saved.title == "Roadmap")
        #expect(saved.content.text == "Ship the vertical slice")
        #expect(saved.tags == ["phase3", "swiftui"])
        #expect(saved.isPinned)

        model.selectNote(nil)
        model.restoreSelection(created.id.description)
        #expect(model.selectedNoteID == created.id)
        await model.deleteSelected()
        #expect(model.phase == .empty)
        #expect(await store.allNotes().isEmpty)
    }

    @Test("Availability, error, and conflict states are explicit")
    func explicitStates() async throws {
        let note = Note(title: "Conflict", content: .init(format: .plainText, text: "local"))
        let revision = NoteRevision(contentHash: "a", content: Data("local".utf8), modifiedAt: .now)
        let conflict = NoteConflict(noteID: note.id, local: revision, external: revision, commonBase: nil)
        let store = MemoryNoteStore(notes: [note], conflicts: [conflict])
        let model = SpiralFeatureModel(store: store)

        await model.load()
        #expect(model.phase == .conflict(count: 1))
        model.setAvailability(.downloading(progress: 0.5))
        #expect(model.phase == .downloading(progress: 0.5))
        model.setAvailability(.unavailable(message: "Not downloaded"))
        #expect(model.phase == .failure("Not downloaded"))

        let failing = SpiralFeatureModel(store: FailingNoteStore())
        await failing.load()
        guard case .failure = failing.phase else {
            Issue.record("Expected a load failure")
            return
        }
    }

    @Test("Pinned notes remain first in both sort modes")
    func pinnedSort() async {
        let oldPinned = Note(
            title: "Zulu",
            content: .init(format: .plainText, text: ""),
            modifiedAt: .distantPast,
            isPinned: true
        )
        let recent = Note(
            title: "Alpha",
            content: .init(format: .plainText, text: ""),
            modifiedAt: .now
        )
        let model = SpiralFeatureModel(store: MemoryNoteStore(notes: [recent, oldPinned]))
        await model.load()
        #expect(model.visibleSummaries.first?.id == oldPinned.id)
        model.settings.sort = .title
        #expect(model.visibleSummaries.first?.id == oldPinned.id)
    }

    @Test("Loaded RTF and HTML bodies edit through the format-preserving model")
    func richBodiesRemainFormatted() async throws {
        let codec = NoteFileCodec()
        for format in [NoteFormat.richText, .html] {
            var content = try codec.decode(
                codec.encode(NoteContent(format: format, text: "formatted body")),
                as: format
            )
            let styleRange = (content.text as NSString).range(of: "formatted")
            try content.apply(.bold, toUTF16: styleRange.location..<NSMaxRange(styleRange))
            let note = Note(title: format.rawValue, content: content)
            let store = MemoryNoteStore(notes: [note])
            let model = SpiralFeatureModel(store: store)

            await model.load()
            #expect(model.selectedNoteSupportsTextEditing)
            await model.updateSelectedContent("formatted edited body")
            let edited = try #require(await store.note(id: note.id)?.content)
            #expect(try codec.decode(codec.encode(edited), as: format).text == "formatted edited body")

            await model.renameSelected(to: "Renamed")
            await model.setSelectedTags(from: "safe-metadata")
            await model.toggleSelectedPin()
            let safelyUpdated = try #require(await store.note(id: note.id))
            #expect(safelyUpdated.title == "Renamed")
            #expect(safelyUpdated.tags == ["safe-metadata"])
            #expect(safelyUpdated.isPinned)
            #expect(safelyUpdated.content.text == "formatted edited body")
        }
    }
}

private actor HydrationProbeStore: NoteStore {
    private let available = Note(
        title: "Available",
        content: .init(format: .plainText, text: "body"),
        modifiedAt: .now
    )
    let offloadedID = NoteID()
    private var maximums: [Int] = []
    private var hydrationRequested = false

    func requestedMaximums() -> [Int] { maximums }
    func allNotes() -> [Note] { [available] }

    func summary(id: NoteID) -> NoteSummary? {
        if id == available.id { return NoteSummary(note: available) }
        guard id == offloadedID else { return nil }
        return offloadedSummary
    }

    func summaries(limit: Int, offset: Int) -> NoteSummaryPage {
        let values = [NoteSummary(note: available), offloadedSummary]
        return NoteSummaryPage(
            summaries: Array(values.dropFirst(offset).prefix(limit)),
            offset: offset,
            totalCount: values.count
        )
    }

    func search(_ request: NoteSearchRequest) -> NoteSearchPage {
        NoteSearchPage(
            hits: [],
            offset: request.offset,
            totalCount: 0,
            coverage: NoteSearchCoverage(
                eligibleCount: 2,
                currentCount: 1,
                staleCount: 0,
                neverIndexedCount: 1,
                excludedCount: 0
            )
        )
    }

    func hydrateSearchIndex(
        maximumConcurrentDownloads: Int
    ) -> NoteSearchHydrationProgress {
        maximums.append(maximumConcurrentDownloads)
        hydrationRequested = true
        return NoteSearchHydrationProgress(
            requestedNoteIDs: [offloadedID],
            pendingCount: 1,
            remainingCount: 2
        )
    }

    func note(id: NoteID) -> Note? { id == available.id ? available : nil }
    func create(_ note: Note) -> Note { note }
    func update(_ note: Note) {}
    func delete(id: NoteID) {}
    func conflicts() -> [NoteConflict] { [] }
    func rebuildIndex() {}

    private var offloadedSummary: NoteSummary {
        NoteSummary(
            id: offloadedID,
            title: "Offloaded",
            createdAt: .distantPast,
            modifiedAt: .distantPast,
            bodyAvailability: hydrationRequested ? .downloadPending : .notDownloaded,
            searchFreshness: .neverIndexed,
            pairingState: .awaitingBody
        )
    }
}

private actor CatalogBoundaryProbeStore: NoteStore {
    struct PageRequest: Equatable, Sendable {
        let limit: Int
        let offset: Int
    }

    struct Calls: Equatable, Sendable {
        let summaryRequests: [PageRequest]
        let searchRequests: [NoteSearchRequest]
        let noteRequests: [NoteID]
        let updateRequests: Int
        let allNotes: Int
    }

    private var notes: [NoteID: Note]
    private let unavailableIDs: Set<NoteID>
    private var summaryRequests: [PageRequest] = []
    private var searchRequests: [NoteSearchRequest] = []
    private var noteRequests: [NoteID] = []
    private var updateRequests = 0
    private var allNotesRequests = 0

    init(notes: [Note], unavailableIDs: Set<NoteID> = []) {
        self.notes = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        self.unavailableIDs = unavailableIDs
    }

    func calls() -> Calls {
        Calls(
            summaryRequests: summaryRequests,
            searchRequests: searchRequests,
            noteRequests: noteRequests,
            updateRequests: updateRequests,
            allNotes: allNotesRequests
        )
    }

    func allNotes() -> [Note] {
        allNotesRequests += 1
        return Array(notes.values)
    }

    func summaries(limit: Int, offset: Int) -> NoteSummaryPage {
        summaryRequests.append(PageRequest(limit: limit, offset: offset))
        let ordered = orderedNotes
        let page = ordered.dropFirst(offset).prefix(limit).map(summary)
        return NoteSummaryPage(summaries: page, offset: offset, totalCount: ordered.count)
    }

    func search(_ request: NoteSearchRequest) -> NoteSearchPage {
        searchRequests.append(request)
        let matches = notes.values.filter { note in
            note.title.localizedCaseInsensitiveContains(request.text)
                || note.content.text.localizedCaseInsensitiveContains(request.text)
                || note.tags.contains { $0.localizedCaseInsensitiveContains(request.text) }
        }.sorted { $0.title > $1.title }
        let page = matches.dropFirst(request.offset).prefix(request.limit).map { note in
            NoteSearchHit(
                summary: summary(note),
                snippet: note.content.text,
                relevance: Double(note.modifiedAt.timeIntervalSince1970)
            )
        }
        let staleCount = matches.filter { unavailableIDs.contains($0.id) }.count
        return NoteSearchPage(
            hits: page,
            offset: request.offset,
            totalCount: matches.count,
            coverage: NoteSearchCoverage(
                eligibleCount: notes.count,
                currentCount: notes.count - staleCount,
                staleCount: staleCount,
                neverIndexedCount: 0,
                excludedCount: 0
            )
        )
    }

    func note(id: NoteID) -> Note? {
        noteRequests.append(id)
        return unavailableIDs.contains(id) ? nil : notes[id]
    }

    func create(_ note: Note) -> Note {
        notes[note.id] = note
        return note
    }

    func update(_ note: Note) {
        updateRequests += 1
        notes[note.id] = note
    }

    func delete(id: NoteID) { notes[id] = nil }
    func conflicts() -> [NoteConflict] { [] }
    func rebuildIndex() {}

    private var orderedNotes: [Note] {
        notes.values.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func summary(_ note: Note) -> NoteSummary {
        var value = NoteSummary(note: note)
        if unavailableIDs.contains(note.id) {
            value.bodyAvailability = .staleCachedCopy
            value.searchFreshness = .stale
            value.pairingState = .awaitingBody
        }
        return value
    }
}

private actor MemoryNoteStore: NoteStore {
    private var notes: [NoteID: Note]
    private let storedConflicts: [NoteConflict]

    init(notes: [Note] = [], conflicts: [NoteConflict] = []) {
        self.notes = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        storedConflicts = conflicts
    }

    func allNotes() -> [Note] { Array(notes.values) }
    func note(id: NoteID) -> Note? { notes[id] }
    func create(_ note: Note) throws -> Note { notes[note.id] = note; return note }
    func update(_ note: Note) throws { notes[note.id] = note }
    func delete(id: NoteID) throws { notes[id] = nil }
    func conflicts() -> [NoteConflict] { storedConflicts }
    func rebuildIndex() throws {}
}

private struct FailingNoteStore: NoteStore {
    enum Failure: Error { case unavailable }
    func allNotes() async throws -> [Note] { throw Failure.unavailable }
    func note(id: NoteID) async throws -> Note? { nil }
    func create(_ note: Note) async throws -> Note { throw Failure.unavailable }
    func update(_ note: Note) async throws { throw Failure.unavailable }
    func delete(id: NoteID) async throws { throw Failure.unavailable }
    func conflicts() async -> [NoteConflict] { [] }
    func rebuildIndex() async throws { throw Failure.unavailable }
}
