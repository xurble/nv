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

public enum NoteListSort: String, CaseIterable, Codable, Sendable {
    case title
    case modified

    public var label: String {
        switch self {
        case .title: "Title"
        case .modified: "Recently Edited"
        }
    }
}

public struct SpiralFeatureSettings: Equatable, Codable, Sendable {
    public var sort: NoteListSort
    public var showPreviews: Bool

    public init(sort: NoteListSort = .modified, showPreviews: Bool = true) {
        self.sort = sort
        self.showPreviews = showPreviews
    }
}

public enum CollectionAvailability: Equatable, Sendable {
    case available
    case downloading(progress: Double?)
    case unavailable(message: String)
}

public enum SpiralFeaturePhase: Equatable, Sendable {
    case loading
    case empty
    case ready
    case downloading(progress: Double?)
    case conflict(count: Int)
    case failure(String)
}

@MainActor
public final class SpiralFeatureModel: ObservableObject {
    @Published public private(set) var summaries: [NoteSummary] = []
    @Published public private(set) var totalNoteCount = 0
    @Published public private(set) var selectedNoteID: NoteID?
    @Published public private(set) var selectedNote: Note?
    @Published public private(set) var isLoadingSelectedNote = false
    @Published public private(set) var selectedNoteLoadError: String?
    @Published public var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }
    @Published public private(set) var searchCoverage: NoteSearchCoverage?
    @Published public private(set) var searchResultCount = 0
    @Published public private(set) var isSearching = false
    @Published public private(set) var searchError: String?
    @Published public private(set) var hydrationProgress: NoteSearchHydrationProgress?
    @Published public private(set) var isHydratingSearchIndex = false
    @Published public private(set) var hydrationError: String?
    @Published public private(set) var conflicts: [NoteConflict] = []
    @Published public private(set) var phase: SpiralFeaturePhase = .loading
    @Published public var settings: SpiralFeatureSettings

    private let store: any NoteStore
    private let summaryPageSize: Int
    private let searchPageSize: Int
    private let searchDebounce: Duration
    private let hydrationBatchSize: Int
    private var availability: CollectionAvailability = .available
    private var nextSummaryOffset = 0
    private var searchHits: [NoteSearchHit] = []
    private var isLoadingSummaryPage = false
    private var isLoadingSearchPage = false
    private var selectedBodyTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var hydrationTask: Task<Void, Never>?

    public init(
        store: any NoteStore,
        settings: SpiralFeatureSettings = SpiralFeatureSettings(),
        summaryPageSize: Int = 100,
        searchPageSize: Int = 50,
        searchDebounce: Duration = .milliseconds(250),
        hydrationBatchSize: Int = 4
    ) {
        self.store = store
        self.settings = settings
        self.summaryPageSize = max(1, summaryPageSize)
        self.searchPageSize = max(1, searchPageSize)
        self.searchDebounce = searchDebounce
        self.hydrationBatchSize = max(1, min(hydrationBatchSize, 8))
    }

    public var selectedSummary: NoteSummary? {
        guard let selectedNoteID else { return nil }
        return searchHits.first { $0.id == selectedNoteID }?.summary
            ?? summaries.first { $0.id == selectedNoteID }
    }

    public var selectedNoteSupportsTextEditing: Bool {
        selectedNote?.content.supportsFormatPreservingEditing == true
    }

    public var visibleSummaries: [NoteSummary] {
        if normalizedSearchText.isEmpty {
            return summaries.sorted(by: noteSort)
        }
        return searchHits.map(\.summary)
    }

    public var isSearchActive: Bool {
        !normalizedSearchText.isEmpty
    }

    public var hasMoreSummaries: Bool {
        nextSummaryOffset < totalNoteCount
    }

    public var hasMoreSearchResults: Bool {
        searchHits.count < searchResultCount
    }

    public var searchStatusMessage: String? {
        guard !normalizedSearchText.isEmpty, let coverage = searchCoverage else { return nil }
        if coverage.neverIndexedCount > 0 {
            return "\(coverage.neverIndexedCount) \(noteWord(coverage.neverIndexedCount)) still indexing"
        }
        if coverage.staleCount > 0 {
            return "\(coverage.staleCount) indexed \(noteWord(coverage.staleCount)) may be out of date"
        }
        return nil
    }

    public var indexingStatusMessage: String? {
        guard let hydrationProgress, hydrationProgress.incompleteCount > 0 else { return nil }
        return "\(hydrationProgress.incompleteCount) \(noteWord(hydrationProgress.incompleteCount)) still indexing"
    }

    public func preview(for id: NoteID) -> String? {
        guard !normalizedSearchText.isEmpty else { return nil }
        return searchHits.first { $0.id == id }?.snippet
    }

    public func load() async {
        selectedBodyTask?.cancel()
        searchTask?.cancel()
        phase = .loading
        do {
            let page = try await store.summaries(limit: summaryPageSize, offset: 0)
            summaries = page.summaries
            nextSummaryOffset = page.offset + page.summaries.count
            totalNoteCount = page.totalCount
            conflicts = await store.conflicts()
            if selectedNoteID == nil {
                selectedNoteID = visibleSummaries.first?.id
            }
            await loadSelectedBody(for: selectedNoteID)
            updatePhase()
            scheduleHydration()
        } catch {
            phase = .failure(Self.message(for: error))
        }
    }

    public func loadMoreIfNeeded(after id: NoteID) async {
        guard visibleSummaries.last?.id == id else { return }
        if normalizedSearchText.isEmpty {
            await loadNextSummaryPage()
        } else {
            await loadNextSearchPage()
        }
    }

    public func selectNote(_ id: NoteID?) {
        guard selectedNoteID != id || (id != nil && selectedNote == nil) else { return }
        prepareSelection(id)
        guard let id else { return }
        selectedBodyTask = Task { [weak self] in
            await self?.loadSelectedBody(for: id)
        }
    }

    public func loadSelectedNote() async {
        if let selectedBodyTask {
            let selectedID = selectedNoteID
            await selectedBodyTask.value
            if selectedNoteID == selectedID { self.selectedBodyTask = nil }
            return
        }
        await loadSelectedBody(for: selectedNoteID)
    }

    public func searchNow() async {
        searchTask?.cancel()
        searchTask = nil
        let query = normalizedSearchText
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        await requestSearch(query: query, offset: 0, replacing: true)
    }

    public func hydrateSearchIndex() async {
        guard !isHydratingSearchIndex else { return }
        isHydratingSearchIndex = true
        hydrationError = nil
        do {
            let progress = try await store.hydrateSearchIndex(
                maximumConcurrentDownloads: hydrationBatchSize
            )
            hydrationProgress = progress
            for id in progress.requestedNoteIDs + progress.indexedNoteIDs {
                if let summary = try await store.summary(id: id) {
                    replaceCachedSummary(summary, insertIfMissing: false)
                }
            }
            if !normalizedSearchText.isEmpty, !progress.indexedNoteIDs.isEmpty {
                await searchNow()
            }
            isHydratingSearchIndex = false
        } catch {
            hydrationError = Self.message(for: error)
            isHydratingSearchIndex = false
        }
    }

    func waitForBackgroundHydration() async {
        await hydrationTask?.value
    }

    @discardableResult
    public func createNote() async -> Note? {
        let note = Note(
            title: uniqueUntitledTitle(),
            content: NoteContent(format: .plainText, text: "")
        )
        do {
            let created = try await store.create(note)
            searchText = ""
            try await refreshLoadedSummaries(minimumCount: summaries.count + 1)
            prepareSelection(created.id)
            selectedNote = created
            updatePhase()
            return created
        } catch {
            phase = .failure(Self.message(for: error))
            return nil
        }
    }

    public func renameSelected(to title: String) async {
        guard let selectedNoteID else { return }
        await renameNote(id: selectedNoteID, to: title)
    }

    public func renameNote(id: NoteID, to title: String) async {
        await mutateNote(id: id) { note in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            note.title = trimmed.isEmpty ? "Untitled" : trimmed
        }
    }

    public func updateSelectedContent(_ text: String) async {
        guard var changed = selectedNote else { return }
        do {
            try changed.content.replaceTextPreservingFormat(with: text)
            changed.modifiedAt = Date()
            await persist(changed)
        } catch {
            phase = .failure(Self.message(for: error))
        }
    }

    public func updateSelectedContent(_ content: NoteContent) async {
        guard let selectedNoteID else { return }
        await updateContent(content, for: selectedNoteID)
    }

    public func updateContent(_ content: NoteContent, for id: NoteID) async {
        do {
            guard var changed = try await editableNote(id: id),
                  changed.content.format == content.format,
                  content.supportsFormatPreservingEditing else { return }
            changed.content = content
            changed.modifiedAt = Date()
            await persist(changed)
        } catch {
            phase = .failure(Self.message(for: error))
        }
    }

    public func setSelectedTags(from text: String) async {
        guard let selectedNoteID else { return }
        await setTags(for: selectedNoteID, from: text)
    }

    public func setTags(for id: NoteID, from text: String) async {
        let tags = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let uniqueTags = tags.filter { seen.insert($0.localizedLowercase).inserted }
        await mutateNote(id: id) { $0.tags = uniqueTags }
    }

    public func toggleSelectedPin() async {
        await mutateSelected { $0.isPinned.toggle() }
    }

    public func deleteSelected() async {
        guard let selectedNoteID else { return }
        do {
            try await store.delete(id: selectedNoteID)
            conflicts.removeAll { $0.noteID == selectedNoteID }
            searchHits.removeAll { $0.id == selectedNoteID }
            searchResultCount = max(0, searchResultCount - 1)
            let retainedCount = max(summaryPageSize, summaries.count)
            try await refreshLoadedSummaries(minimumCount: retainedCount)
            if !normalizedSearchText.isEmpty {
                await searchNow()
            }
            if self.selectedNoteID == selectedNoteID {
                let nextID = visibleSummaries.first?.id
                prepareSelection(nextID)
                await loadSelectedBody(for: nextID)
            }
            updatePhase()
        } catch {
            phase = .failure(Self.message(for: error))
        }
    }

    public func restoreSelection(_ rawValue: String?) {
        guard let rawValue, let uuid = UUID(uuidString: rawValue) else { return }
        let candidate = NoteID(uuid)
        guard summaries.contains(where: { $0.id == candidate }) else { return }
        selectNote(candidate)
    }

    public func setAvailability(_ availability: CollectionAvailability) {
        self.availability = availability
        updatePhase()
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prepareSelection(_ id: NoteID?) {
        selectedBodyTask?.cancel()
        selectedBodyTask = nil
        if let id,
           !summaries.contains(where: { $0.id == id }),
           let searchedSummary = searchHits.first(where: { $0.id == id })?.summary {
            summaries.append(searchedSummary)
        }
        selectedNoteID = id
        selectedNote = nil
        selectedNoteLoadError = nil
        isLoadingSelectedNote = false
    }

    private func loadSelectedBody(for id: NoteID?) async {
        guard let id else {
            selectedNote = nil
            selectedNoteLoadError = nil
            isLoadingSelectedNote = false
            return
        }
        isLoadingSelectedNote = true
        selectedNoteLoadError = nil
        do {
            let loaded = try await store.note(id: id)
            guard !Task.isCancelled, selectedNoteID == id else { return }
            selectedNote = loaded
            if let loaded {
                updateCachedSummary(from: loaded)
            } else if let refreshed = try await store.summary(id: id) {
                guard !Task.isCancelled, selectedNoteID == id else { return }
                replaceCachedSummary(refreshed, insertIfMissing: true)
            }
            if selectedNoteID == id { isLoadingSelectedNote = false }
        } catch is CancellationError {
            if selectedNoteID == id { isLoadingSelectedNote = false }
        } catch {
            guard selectedNoteID == id else { return }
            selectedNote = nil
            selectedNoteLoadError = Self.message(for: error)
            isLoadingSelectedNote = false
        }
    }

    private func loadNextSummaryPage() async {
        guard hasMoreSummaries, !isLoadingSummaryPage else { return }
        isLoadingSummaryPage = true
        defer { isLoadingSummaryPage = false }
        do {
            let page = try await store.summaries(limit: summaryPageSize, offset: nextSummaryOffset)
            appendUnique(page.summaries, to: &summaries)
            nextSummaryOffset = page.offset + page.summaries.count
            totalNoteCount = page.totalCount
            updatePhase()
        } catch {
            phase = .failure(Self.message(for: error))
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = nil
        let query = normalizedSearchText
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        searchHits = []
        searchCoverage = nil
        searchResultCount = 0
        searchError = nil
        isSearching = true
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: searchDebounce)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await requestSearch(query: query, offset: 0, replacing: true)
        }
    }

    private func scheduleHydration() {
        guard hydrationTask == nil else { return }
        hydrationTask = Task { [weak self] in
            guard let self else { return }
            await hydrateSearchIndex()
            hydrationTask = nil
        }
    }

    private func requestSearch(query: String, offset: Int, replacing: Bool) async {
        if replacing { isSearching = true }
        do {
            let page = try await store.search(
                NoteSearchRequest(text: query, limit: searchPageSize, offset: offset)
            )
            guard !Task.isCancelled, normalizedSearchText == query else { return }
            if replacing {
                searchHits = page.hits
            } else {
                appendUnique(page.hits, to: &searchHits)
            }
            searchCoverage = page.coverage
            searchResultCount = page.totalCount
            searchError = nil
            isSearching = false
        } catch is CancellationError {
            if normalizedSearchText == query { isSearching = false }
        } catch {
            guard normalizedSearchText == query else { return }
            searchError = Self.message(for: error)
            isSearching = false
        }
    }

    private func loadNextSearchPage() async {
        guard hasMoreSearchResults, !isLoadingSearchPage else { return }
        let query = normalizedSearchText
        guard !query.isEmpty else { return }
        isLoadingSearchPage = true
        defer { isLoadingSearchPage = false }
        await requestSearch(query: query, offset: searchHits.count, replacing: false)
    }

    private func clearSearch() {
        searchHits = []
        searchCoverage = nil
        searchResultCount = 0
        searchError = nil
        isSearching = false
    }

    private func mutateSelected(_ mutation: (inout Note) -> Void) async {
        guard let selectedNoteID else { return }
        await mutateNote(id: selectedNoteID, mutation)
    }

    private func mutateNote(id: NoteID, _ mutation: (inout Note) -> Void) async {
        do {
            guard var changed = try await editableNote(id: id) else { return }
            mutation(&changed)
            await persist(changed)
        } catch {
            phase = .failure(Self.message(for: error))
        }
    }

    private func editableNote(id: NoteID) async throws -> Note? {
        if selectedNoteID == id {
            return selectedNote
        }
        return try await store.note(id: id)
    }

    private func persist(_ changed: Note) async {
        do {
            try await store.update(changed)
            if selectedNoteID == changed.id {
                selectedNote = changed
            }
            try await refreshLoadedSummaries(minimumCount: max(summaryPageSize, summaries.count))
            if !normalizedSearchText.isEmpty {
                await searchNow()
            }
            updatePhase()
        } catch {
            phase = .failure(Self.message(for: error))
        }
    }

    private func refreshLoadedSummaries(minimumCount: Int) async throws {
        let page = try await store.summaries(limit: max(summaryPageSize, minimumCount), offset: 0)
        summaries = page.summaries
        nextSummaryOffset = page.offset + page.summaries.count
        totalNoteCount = page.totalCount
    }

    private func updateCachedSummary(from note: Note) {
        var summary = summaries.first(where: { $0.id == note.id })
            ?? searchHits.first(where: { $0.id == note.id })?.summary
            ?? NoteSummary(note: note)
        summary.title = note.title
        summary.folder = note.folder
        summary.tags = note.tags
        summary.createdAt = note.createdAt
        summary.modifiedAt = note.modifiedAt
        summary.isPinned = note.isPinned
        summary.isPrivate = note.isPrivate
        summary.bodyAvailability = .available
        replaceCachedSummary(summary, insertIfMissing: true)
    }

    private func replaceCachedSummary(_ summary: NoteSummary, insertIfMissing: Bool) {
        if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
            summaries[index] = summary
        } else if insertIfMissing {
            summaries.append(summary)
        }
        if let index = searchHits.firstIndex(where: { $0.id == summary.id }) {
            let hit = searchHits[index]
            searchHits[index] = NoteSearchHit(
                summary: summary,
                snippet: hit.snippet,
                relevance: hit.relevance
            )
        }
    }

    private func updatePhase() {
        switch availability {
        case .available:
            if !conflicts.isEmpty {
                phase = .conflict(count: conflicts.count)
            } else {
                phase = totalNoteCount == 0 ? .empty : .ready
            }
        case let .downloading(progress):
            phase = .downloading(progress: progress)
        case let .unavailable(message):
            phase = .failure(message)
        }
    }

    private func uniqueUntitledTitle() -> String {
        let titles = Set(summaries.map { $0.title.localizedLowercase })
        if !titles.contains("untitled") { return "Untitled" }
        var number = 2
        while titles.contains("untitled \(number)") { number += 1 }
        return "Untitled \(number)"
    }

    private func noteSort(_ lhs: NoteSummary, _ rhs: NoteSummary) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        switch settings.sort {
        case .title:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case .modified:
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func noteWord(_ count: Int) -> String {
        count == 1 ? "note" : "notes"
    }

    private func appendUnique<T: Identifiable>(_ additions: [T], to values: inout [T]) where T.ID: Hashable {
        var identifiers = Set(values.map(\.id))
        values.append(contentsOf: additions.filter { identifiers.insert($0.id).inserted })
    }

    private static func message(for error: Error) -> String {
        let description = String(describing: error)
        return description.isEmpty ? "The collection could not be opened." : description
    }
}
