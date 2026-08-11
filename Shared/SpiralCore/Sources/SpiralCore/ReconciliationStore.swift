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

import CryptoKit
import Foundation

public struct ReconciliationRecord: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumRecentPaths = 8
    public static let maximumMergeBaseBytes = 256 * 1024

    public var schemaVersion: Int
    public let noteID: NoteID
    public var currentRelativePath: String
    public var recentRelativePaths: [String]
    public var rawContentHash: String
    public var lastCommonRevisionHash: String?
    public var mergeBaseContent: Data?
    public var tags: [String]
    public var legacyMetadata: [String: Data]
    public var createdAt: Date
    public var modifiedAt: Date
    public var isPinned: Bool
    public var isPrivate: Bool
    public var isTombstone: Bool

    public init(
        noteID: NoteID,
        currentRelativePath: String,
        recentRelativePaths: [String] = [],
        rawContentHash: String,
        lastCommonRevisionHash: String? = nil,
        mergeBaseContent: Data? = nil,
        tags: [String] = [],
        legacyMetadata: [String: Data] = [:],
        createdAt: Date,
        modifiedAt: Date,
        isPinned: Bool = false,
        isPrivate: Bool = false,
        isTombstone: Bool = false
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.noteID = noteID
        self.currentRelativePath = currentRelativePath
        self.recentRelativePaths = Array(recentRelativePaths.prefix(Self.maximumRecentPaths))
        self.rawContentHash = rawContentHash
        self.lastCommonRevisionHash = lastCommonRevisionHash
        if let mergeBaseContent, mergeBaseContent.count <= Self.maximumMergeBaseBytes {
            self.mergeBaseContent = mergeBaseContent
        } else {
            self.mergeBaseContent = nil
        }
        self.tags = tags
        self.legacyMetadata = legacyMetadata
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
        self.isPrivate = isPrivate
        self.isTombstone = isTombstone
    }

    public mutating func move(to relativePath: String) {
        if currentRelativePath != relativePath {
            recentRelativePaths.removeAll { $0 == currentRelativePath || $0 == relativePath }
            recentRelativePaths.insert(currentRelativePath, at: 0)
            recentRelativePaths = Array(recentRelativePaths.prefix(Self.maximumRecentPaths))
            currentRelativePath = relativePath
        }
    }
}

public enum ReconciliationStoreError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case recordIdentityMismatch
    case unsafeRelativePath(String)
    case invalidRecordFile(String)
}

public struct ReconciliationStore: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func prepare() throws {
        if FileManager.default.fileExists(atPath: rootURL.path) {
            let values = try rootURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw ReconciliationStoreError.invalidRecordFile(rootURL.lastPathComponent)
            }
        } else {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    public func loadAll() throws -> [NoteID: ReconciliationRecord] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return [:] }
        var result: [NoteID: ReconciliationRecord] = [:]
        for url in try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) where url.pathExtension == "json" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw ReconciliationStoreError.invalidRecordFile(url.lastPathComponent)
            }
            let record = try JSONDecoder.spiral.decode(
                ReconciliationRecord.self,
                from: Data(contentsOf: url)
            )
            guard record.schemaVersion == ReconciliationRecord.currentSchemaVersion else {
                throw ReconciliationStoreError.unsupportedSchema(record.schemaVersion)
            }
            guard url.deletingPathExtension().lastPathComponent == record.noteID.description else {
                throw ReconciliationStoreError.recordIdentityMismatch
            }
            try Self.validate(relativePath: record.currentRelativePath)
            for path in record.recentRelativePaths { try Self.validate(relativePath: path) }
            result[record.noteID] = record
        }
        return result
    }

    public func save(_ record: ReconciliationRecord) throws {
        try prepare()
        try Self.validate(relativePath: record.currentRelativePath)
        for path in record.recentRelativePaths { try Self.validate(relativePath: path) }
        let url = rootURL.appendingPathComponent(record.noteID.description).appendingPathExtension("json")
        try JSONEncoder.spiral.encode(record).write(to: url, options: [.atomic])
    }

    public func remove(noteID: NoteID) throws {
        let url = rootURL.appendingPathComponent(noteID.description).appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func validate(relativePath: String) throws {
        let path = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !components.contains(".."),
              !components.contains("."),
              !components.contains("") else {
            throw ReconciliationStoreError.unsafeRelativePath(relativePath)
        }
    }
}

public enum ContentHash {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension JSONEncoder {
    fileprivate static var spiral: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var spiral: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
