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
    func note(id: NoteID) async throws -> Note?
    @discardableResult func create(_ note: Note) async throws -> Note
    func update(_ note: Note) async throws
    func delete(id: NoteID) async throws
    func conflicts() async -> [NoteConflict]
    func rebuildIndex() async throws
}
