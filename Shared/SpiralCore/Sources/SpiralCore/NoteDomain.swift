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
        case "txt", "text", "utf8", "taskpaper": .plainText
        case "rtf": .richText
        case "html", "htm": .html
        default: nil
        }
    }
}

/// Platform-neutral note content. `originalData` preserves an externally
/// produced valid representation until the user actually changes its text.
public struct NoteContent: Equatable, Codable, Sendable {
    public var format: NoteFormat
    public var text: String
    public var originalData: Data?
    public var originalText: String?

    public init(
        format: NoteFormat,
        text: String,
        originalData: Data? = nil,
        originalText: String? = nil
    ) {
        self.format = format
        self.text = text
        self.originalData = originalData
        self.originalText = originalText
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
