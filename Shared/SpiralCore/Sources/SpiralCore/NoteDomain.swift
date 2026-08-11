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

public struct NoteID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString.lowercased() }
}

public enum NoteFormat: String, CaseIterable, Codable, Sendable {
    case plainText = "txt"
    case richText = "rtf"
    case html

    public var preferredPathExtension: String { rawValue }

    public static func format(forPathExtension pathExtension: String) -> NoteFormat? {
        switch pathExtension.lowercased() {
        case "txt", "text", "utf8", "taskpaper", "md", "markdown": .plainText
        case "rtf": .richText
        case "html", "htm": .html
        default: nil
        }
    }
}

/// Platform-neutral note content. Loaded RTF and HTML use a lossless token
/// document so text edits and inline formatting retain untouched source
/// controls, attributes, and markup.
public struct NoteContent: Equatable, Codable, Sendable {
    public var format: NoteFormat
    public var text: String
    public var originalData: Data?
    public var originalText: String?
    public var formattedDocument: FormattedTextDocument?

    public init(
        format: NoteFormat,
        text: String,
        originalData: Data? = nil,
        originalText: String? = nil,
        formattedDocument: FormattedTextDocument? = nil
    ) {
        self.format = format
        self.text = text
        self.originalData = originalData
        self.originalText = originalText
        self.formattedDocument = formattedDocument
    }

    public var supportsFormatPreservingEditing: Bool {
        format == .plainText || formattedDocument != nil || originalData == nil
    }

    public mutating func replaceTextPreservingFormat(with replacement: String) throws {
        guard var document = formattedDocument else {
            if format != .plainText, originalData != nil {
                throw NoteFileCodecError.formatPreservingEditRequired(format)
            }
            text = replacement
            return
        }
        let oldUnits = Array(document.text.utf16)
        let newUnits = Array(replacement.utf16)
        var prefix = 0
        while prefix < oldUnits.count,
              prefix < newUnits.count,
              oldUnits[prefix] == newUnits[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldUnits.count - prefix,
              suffix < newUnits.count - prefix,
              oldUnits[oldUnits.count - suffix - 1] == newUnits[newUnits.count - suffix - 1] {
            suffix += 1
        }
        let changedNewUnits = newUnits[prefix..<(newUnits.count - suffix)]
        let changedText = String(decoding: changedNewUnits, as: UTF16.self)
        try document.replaceText(
            inUTF16: prefix..<(oldUnits.count - suffix),
            with: changedText
        )
        formattedDocument = document
        text = document.text
    }

    public mutating func apply(
        _ attribute: InlineTextAttribute,
        toUTF16 range: Range<Int>
    ) throws {
        guard var document = formattedDocument else {
            throw NoteFileCodecError.formatPreservingEditRequired(format)
        }
        try document.apply(attribute, toUTF16: range)
        formattedDocument = document
        text = document.text
    }
}

public struct Note: Identifiable, Equatable, Codable, Sendable {
    public let id: NoteID
    public var title: String
    public var content: NoteContent
    public var tags: [String]
    public var legacyMetadata: [String: Data]
    public var folder: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var isPinned: Bool
    public var isPrivate: Bool

    public init(
        id: NoteID = NoteID(),
        title: String,
        content: NoteContent,
        tags: [String] = [],
        legacyMetadata: [String: Data] = [:],
        folder: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        isPinned: Bool = false,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.tags = tags
        self.legacyMetadata = legacyMetadata
        self.folder = folder
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
        self.isPrivate = isPrivate
    }
}

public enum NoteBodyAvailability: String, Equatable, Codable, Sendable {
    case available
    case staleCachedCopy
    case notDownloaded
    case downloadPending
    case downloadFailed
    case deletedOrMissingPendingConfirmation
}

public enum NoteMetadataAvailability: String, Equatable, Codable, Sendable {
    case available
    case awaitingMetadata
}

public enum NoteSearchFreshness: String, Equatable, Codable, Sendable {
    case current
    case stale
    case neverIndexed
    case excluded
}

public enum NotePairingState: String, Equatable, Codable, Sendable {
    case paired
    case awaitingBody
    case awaitingMetadata
    case provisionalDiscovery
    case deletionInFlight
    case missingPendingConfirmation
    case conflict
    case repairConflict
}

/// A durable, body-independent projection used to list and search notes even
/// when an iCloud document is not currently downloaded.
public struct NoteSummary: Identifiable, Equatable, Codable, Sendable {
    public let id: NoteID
    public var title: String
    public var folder: String?
    public var tags: [String]
    public var createdAt: Date
    public var modifiedAt: Date
    public var isPinned: Bool
    public var isPrivate: Bool
    public var relativePath: String?
    public var contentHash: String?
    public var bodyAvailability: NoteBodyAvailability
    public var metadataAvailability: NoteMetadataAvailability
    public var searchFreshness: NoteSearchFreshness
    public var lastIndexedRevision: String?
    public var pairingState: NotePairingState
    public var isSearchEligible: Bool

    public init(
        id: NoteID,
        title: String,
        folder: String? = nil,
        tags: [String] = [],
        createdAt: Date,
        modifiedAt: Date,
        isPinned: Bool = false,
        isPrivate: Bool = false,
        relativePath: String? = nil,
        contentHash: String? = nil,
        bodyAvailability: NoteBodyAvailability = .available,
        metadataAvailability: NoteMetadataAvailability = .available,
        searchFreshness: NoteSearchFreshness = .current,
        lastIndexedRevision: String? = nil,
        pairingState: NotePairingState = .paired,
        isSearchEligible: Bool = true
    ) {
        self.id = id
        self.title = title
        self.folder = folder
        self.tags = tags
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
        self.isPrivate = isPrivate
        self.relativePath = relativePath
        self.contentHash = contentHash
        self.bodyAvailability = bodyAvailability
        self.metadataAvailability = metadataAvailability
        self.searchFreshness = searchFreshness
        self.lastIndexedRevision = lastIndexedRevision
        self.pairingState = pairingState
        self.isSearchEligible = isSearchEligible
    }

    public init(
        note: Note,
        relativePath: String? = nil,
        contentHash: String? = nil,
        isSearchEligible: Bool? = nil
    ) {
        self.init(
            id: note.id,
            title: note.title,
            folder: note.folder,
            tags: note.tags,
            createdAt: note.createdAt,
            modifiedAt: note.modifiedAt,
            isPinned: note.isPinned,
            isPrivate: note.isPrivate,
            relativePath: relativePath,
            contentHash: contentHash,
            lastIndexedRevision: contentHash,
            isSearchEligible: isSearchEligible ?? !note.isPrivate
        )
    }
}

public struct NoteSummaryPage: Equatable, Sendable {
    public let summaries: [NoteSummary]
    public let offset: Int
    public let totalCount: Int

    public init(summaries: [NoteSummary], offset: Int, totalCount: Int) {
        self.summaries = summaries
        self.offset = offset
        self.totalCount = totalCount
    }
}

public struct NoteSearchRequest: Equatable, Sendable {
    public var text: String
    public var limit: Int
    public var offset: Int

    public init(text: String, limit: Int = 50, offset: Int = 0) {
        self.text = text
        self.limit = limit
        self.offset = offset
    }
}

public struct NoteSearchHit: Identifiable, Equatable, Sendable {
    public var id: NoteID { summary.id }
    public let summary: NoteSummary
    public let snippet: String
    public let relevance: Double

    public init(summary: NoteSummary, snippet: String, relevance: Double) {
        self.summary = summary
        self.snippet = snippet
        self.relevance = relevance
    }
}

public struct NoteSearchCoverage: Equatable, Sendable {
    public let eligibleCount: Int
    public let currentCount: Int
    public let staleCount: Int
    public let neverIndexedCount: Int
    public let excludedCount: Int

    public init(
        eligibleCount: Int,
        currentCount: Int,
        staleCount: Int,
        neverIndexedCount: Int,
        excludedCount: Int
    ) {
        self.eligibleCount = eligibleCount
        self.currentCount = currentCount
        self.staleCount = staleCount
        self.neverIndexedCount = neverIndexedCount
        self.excludedCount = excludedCount
    }

    public var isComplete: Bool { neverIndexedCount == 0 }
}

public struct NoteSearchPage: Equatable, Sendable {
    public let hits: [NoteSearchHit]
    public let offset: Int
    public let totalCount: Int
    public let coverage: NoteSearchCoverage

    public init(
        hits: [NoteSearchHit],
        offset: Int,
        totalCount: Int,
        coverage: NoteSearchCoverage
    ) {
        self.hits = hits
        self.offset = offset
        self.totalCount = totalCount
        self.coverage = coverage
    }
}

public struct NoteSearchHydrationProgress: Equatable, Sendable {
    public let requestedNoteIDs: [NoteID]
    public let indexedNoteIDs: [NoteID]
    public let pendingCount: Int
    public let remainingCount: Int

    public init(
        requestedNoteIDs: [NoteID] = [],
        indexedNoteIDs: [NoteID] = [],
        pendingCount: Int = 0,
        remainingCount: Int = 0
    ) {
        self.requestedNoteIDs = requestedNoteIDs
        self.indexedNoteIDs = indexedNoteIDs
        self.pendingCount = max(0, pendingCount)
        self.remainingCount = max(0, remainingCount)
    }

    public var incompleteCount: Int { pendingCount + remainingCount }
    public var isComplete: Bool { incompleteCount == 0 }
}

public struct NoteRevision: Equatable, Codable, Sendable {
    public let contentHash: String
    public let content: Data
    public let modifiedAt: Date

    public init(contentHash: String, content: Data, modifiedAt: Date) {
        self.contentHash = contentHash
        self.content = content
        self.modifiedAt = modifiedAt
    }
}

public struct NoteConflict: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let noteID: NoteID
    public let local: NoteRevision
    public let external: NoteRevision
    public let commonBase: NoteRevision?

    public init(
        id: UUID = UUID(),
        noteID: NoteID,
        local: NoteRevision,
        external: NoteRevision,
        commonBase: NoteRevision?
    ) {
        self.id = id
        self.noteID = noteID
        self.local = local
        self.external = external
        self.commonBase = commonBase
    }
}

public enum NoteStoreEvent: Equatable, Sendable {
    case inserted(NoteID)
    case updated(NoteID)
    case moved(NoteID)
    case deleted(NoteID)
    case conflict(NoteID)
    case rebuilt
}

public protocol NoteStore: Sendable {
    func allNotes() async throws -> [Note]
    func summary(id: NoteID) async throws -> NoteSummary?
    func summaries(limit: Int, offset: Int) async throws -> NoteSummaryPage
    func search(_ request: NoteSearchRequest) async throws -> NoteSearchPage
    func hydrateSearchIndex(maximumConcurrentDownloads: Int) async throws -> NoteSearchHydrationProgress
    func note(id: NoteID) async throws -> Note?
    @discardableResult func create(_ note: Note) async throws -> Note
    func update(_ note: Note) async throws
    func delete(id: NoteID) async throws
    func conflicts() async -> [NoteConflict]
    func rebuildIndex() async throws
}

public extension NoteStore {
    func summary(id: NoteID) async throws -> NoteSummary? { nil }

    func summaries(limit: Int = 100, offset: Int = 0) async throws -> NoteSummaryPage {
        let notes = try await allNotes().sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        let safeOffset = max(0, offset)
        let safeLimit = max(0, limit)
        let page = notes.dropFirst(min(safeOffset, notes.count)).prefix(safeLimit)
        return NoteSummaryPage(
            summaries: page.map { NoteSummary(note: $0) },
            offset: safeOffset,
            totalCount: notes.count
        )
    }

    func search(_ request: NoteSearchRequest) async throws -> NoteSearchPage {
        let query = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = try await allNotes()
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let eligible = notes.filter { !$0.isPrivate }
        let matches = eligible.filter { note in
            let fields = [note.title, note.content.text, note.tags.joined(separator: " "), note.folder ?? ""]
            return terms.allSatisfy { term in
                fields.contains { $0.localizedCaseInsensitiveContains(term) }
            }
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        let safeOffset = max(0, request.offset)
        let safeLimit = max(0, request.limit)
        let page = matches.dropFirst(min(safeOffset, matches.count)).prefix(safeLimit)
        let hits = page.map { note in
            NoteSearchHit(
                summary: NoteSummary(note: note),
                snippet: String(note.content.text.replacingOccurrences(of: "\n", with: " ").prefix(180)),
                relevance: note.isPinned ? 1 : 0
            )
        }
        return NoteSearchPage(
            hits: hits,
            offset: safeOffset,
            totalCount: matches.count,
            coverage: NoteSearchCoverage(
                eligibleCount: eligible.count,
                currentCount: eligible.count,
                staleCount: 0,
                neverIndexedCount: 0,
                excludedCount: notes.count - eligible.count
            )
        )
    }

    func hydrateSearchIndex(
        maximumConcurrentDownloads: Int
    ) async throws -> NoteSearchHydrationProgress {
        NoteSearchHydrationProgress()
    }
}
