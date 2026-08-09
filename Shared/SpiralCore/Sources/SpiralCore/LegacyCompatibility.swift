import CryptoKit
import Foundation

/// The permanent boundary around the legacy Objective-C archive, encryption,
/// passphrase, and WAL implementation. A macOS adapter opens only a verified
/// disposable copy, then supplies these platform-neutral values to SpiralCore.
public protocol LegacyCompatibilitySource: Sendable {
    var collectionURL: URL { get }
    var protection: LegacyCollectionProtection { get }
    func loadSnapshot(from verifiedWorkingCopyURL: URL) throws -> LegacyCollectionSnapshot
}

public enum LegacyCollectionProtection: String, Codable, Sendable {
    case plaintext
    case legacyApplicationEncryption
}

public enum LegacyCompatibilityError: Error, Equatable, Sendable {
    case noNotes
    case mixedSeparateFileFormats
    case unsupportedItem(String)
    case wrongPassphrase
    case passphraseCancelled
    case damagedArchive
    case unrecoverableWAL
}

public struct LegacyNoteSnapshot: Equatable, Codable, Sendable {
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
        title: String,
        content: NoteContent,
        tags: [String] = [],
        legacyMetadata: [String: Data] = [:],
        folder: String? = nil,
        createdAt: Date,
        modifiedAt: Date,
        isPinned: Bool = false,
        isPrivate: Bool = false
    ) {
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

public struct LegacyCollectionSnapshot: Equatable, Codable, Sendable {
    public var sourceApplication: String
    public var sourceVersion: String?
    public var notes: [LegacyNoteSnapshot]
    public var collectionMetadata: [String: Data]
    public var recoveredWAL: Bool

    public init(
        sourceApplication: String,
        sourceVersion: String? = nil,
        notes: [LegacyNoteSnapshot],
        collectionMetadata: [String: Data] = [:],
        recoveredWAL: Bool = false
    ) {
        self.sourceApplication = sourceApplication
        self.sourceVersion = sourceVersion
        self.notes = notes
        self.collectionMetadata = collectionMetadata
        self.recoveredWAL = recoveredWAL
    }
}

/// Injectable wrapper used by the macOS compatibility adapter after the
/// production legacy controller has opened/decrypted/recovered a disposable
/// collection copy.
public struct LegacySnapshotSource: LegacyCompatibilitySource {
    public let collectionURL: URL
    public let protection: LegacyCollectionProtection
    private let loader: @Sendable (URL) throws -> LegacyCollectionSnapshot

    public init(
        collectionURL: URL,
        protection: LegacyCollectionProtection,
        loader: @escaping @Sendable (URL) throws -> LegacyCollectionSnapshot
    ) {
        self.collectionURL = collectionURL
        self.protection = protection
        self.loader = loader
    }

    public func loadSnapshot(from verifiedWorkingCopyURL: URL) throws -> LegacyCollectionSnapshot {
        try loader(verifiedWorkingCopyURL)
    }
}

public struct LegacySeparateFileSource: LegacyCompatibilitySource {
    public let collectionURL: URL
    public let protection = LegacyCollectionProtection.plaintext
    private let codec: NoteFileCodec

    public init(collectionURL: URL, codec: NoteFileCodec = NoteFileCodec()) {
        self.collectionURL = collectionURL
        self.codec = codec
    }

    public func loadSnapshot(from verifiedWorkingCopyURL: URL) throws -> LegacyCollectionSnapshot {
        let files = try noteFiles(at: verifiedWorkingCopyURL)
        guard !files.isEmpty else { throw LegacyCompatibilityError.noNotes }
        let formats = Set(files.compactMap { NoteFormat.format(forPathExtension: $0.pathExtension) })
        guard formats.count == 1 else { throw LegacyCompatibilityError.mixedSeparateFileFormats }

        let rootPath = verifiedWorkingCopyURL.standardizedFileURL.path
        let notes = try files.map { url -> LegacyNoteSnapshot in
            let values = try url.resourceValues(forKeys: [
                .creationDateKey, .contentModificationDateKey, .tagNamesKey
            ])
            let relative = String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))
            let folder = (relative as NSString).deletingLastPathComponent
            let relativeData = try PropertyListSerialization.data(
                fromPropertyList: relative,
                format: .binary,
                options: 0
            )
            return LegacyNoteSnapshot(
                title: url.deletingPathExtension().lastPathComponent,
                content: try codec.read(from: url),
                tags: values.tagNames ?? [],
                legacyMetadata: ["legacy.relativePath": relativeData],
                folder: folder == "." ? nil : folder,
                createdAt: values.creationDate ?? Date(timeIntervalSince1970: 0),
                modifiedAt: values.contentModificationDate ?? values.creationDate ?? Date(timeIntervalSince1970: 0)
            )
        }
        return LegacyCollectionSnapshot(sourceApplication: "Notational Velocity/nvAlt separate files", notes: notes)
    }

    private func noteFiles(at collectionURL: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: collectionURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LegacyCompatibilityError.unsupportedItem(collectionURL.lastPathComponent)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: collectionURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw LegacyCompatibilityError.unsupportedItem(url.lastPathComponent) }
            if values.isRegularFile == true,
               NoteFormat.format(forPathExtension: url.pathExtension) != nil {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}

public struct LegacyCollectionFingerprint: Equatable, Codable, Sendable {
    public let sha256: String
    public let itemCount: Int
}

public enum LegacyCollectionVerifier {
    public static func fingerprint(at rootURL: URL) throws -> LegacyCollectionFingerprint {
        let root = rootURL.standardizedFileURL
        var items: [(String, Data)] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return LegacyCollectionFingerprint(sha256: ContentHash.sha256(Data()), itemCount: 0) }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            let relative = String(url.standardizedFileURL.path.dropFirst(root.path.count + 1))
            let payload: Data
            if values.isRegularFile == true {
                payload = try Data(contentsOf: url)
            } else if values.isSymbolicLink == true {
                payload = Data(try FileManager.default.destinationOfSymbolicLink(atPath: url.path).utf8)
            } else if values.isDirectory == true {
                payload = Data()
            } else {
                throw LegacyCompatibilityError.unsupportedItem(relative)
            }
            items.append((relative, payload))
        }
        var hasher = SHA256()
        for (path, payload) in items.sorted(by: { $0.0 < $1.0 }) {
            hasher.update(data: Data(path.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: payload)
            hasher.update(data: Data([0xFF]))
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return LegacyCollectionFingerprint(sha256: digest, itemCount: items.count)
    }

    public static func copyAndVerify(from sourceURL: URL, to backupURL: URL) throws {
        guard !FileManager.default.fileExists(atPath: backupURL.path) else {
            throw LegacyMigrationError.backupAlreadyExists
        }
        try FileManager.default.createDirectory(
            at: backupURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: sourceURL, to: backupURL)
        guard try fingerprint(at: sourceURL) == fingerprint(at: backupURL) else {
            throw LegacyMigrationError.backupVerificationFailed
        }
    }
}
