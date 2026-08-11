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

public enum ReconciliationIdentityMatch: Equatable, Sendable {
    case matched(NoteID)
    case newIdentity(NoteID)
    case ambiguous([NoteID])
    case deferred
}

public struct ReconciliationIdentityResolver: Sendable {
    public init() {}

    /// Matches current path first, then bounded recent paths, then raw hashes.
    /// Any non-unique tier is surfaced instead of guessing at identity.
    public func resolve(
        _ item: CloudDocumentSnapshot,
        records: [ReconciliationRecord],
        claimedIDs: Set<NoteID> = []
    ) -> ReconciliationIdentityMatch {
        guard item.availability == .available else { return .deferred }
        let available = records.filter { !claimedIDs.contains($0.noteID) && !$0.isTombstone }
        let current = available.filter { $0.currentRelativePath == item.relativePath }
        if let result = uniqueOrAmbiguous(current) { return result }

        let recent = available.filter { $0.recentRelativePaths.contains(item.relativePath) }
        if let result = uniqueOrAmbiguous(recent) { return result }

        if let hash = item.contentHash {
            let hashes = available.filter { $0.rawContentHash == hash }
            if let result = uniqueOrAmbiguous(hashes) { return result }
        }
        return .newIdentity(deterministicIdentity(for: item))
    }

    private func uniqueOrAmbiguous(
        _ records: [ReconciliationRecord]
    ) -> ReconciliationIdentityMatch? {
        let ids = Array(Set(records.map(\.noteID))).sorted { $0.description < $1.description }
        if records.count > 1 { return .ambiguous(ids) }
        if ids.count == 1 { return .matched(ids[0]) }
        if ids.count > 1 { return .ambiguous(ids) }
        return nil
    }

    /// Two clients discovering the same previously unmanaged file at once must
    /// publish the same initial UUID rather than create competing records. The
    /// path participates so an unambiguous copy with identical bytes receives
    /// a distinct identity.
    private func deterministicIdentity(for item: CloudDocumentSnapshot) -> NoteID {
        let seed = item.relativePath + "\u{0}" + (item.contentHash ?? "")
        let hex = ContentHash.sha256(Data(seed.utf8))
        let first = String(hex.prefix(8))
        let second = String(hex.dropFirst(8).prefix(4))
        let third = "5" + String(hex.dropFirst(13).prefix(3))
        let fourth = "8" + String(hex.dropFirst(17).prefix(3))
        let fifth = String(hex.dropFirst(20).prefix(12))
        let uuidString = "\(first)-\(second)-\(third)-\(fourth)-\(fifth)"
        return NoteID(UUID(uuidString: uuidString)!)
    }
}

public enum NoteContentMergeResult: Equatable, Sendable {
    case resolved(Data)
    case conflict(NoteConflict)
}

public struct NoteContentMerger: Sendable {
    public init() {}

    /// Performs a conservative three-way merge. Rich text and HTML preserve
    /// both revisions whenever both changed. Plain text merges only validated
    /// UTF-8, line-aligned, non-overlapping edits.
    public func merge(
        noteID: NoteID,
        format: NoteFormat,
        base: NoteRevision?,
        local: NoteRevision,
        external: NoteRevision
    ) -> NoteContentMergeResult {
        if local.content == external.content { return .resolved(local.content) }
        if let base, local.content == base.content { return .resolved(external.content) }
        if let base, external.content == base.content { return .resolved(local.content) }

        guard format == .plainText,
              let base,
              let baseText = String(data: base.content, encoding: .utf8),
              let localText = String(data: local.content, encoding: .utf8),
              let externalText = String(data: external.content, encoding: .utf8),
              let merged = mergeAlignedLines(base: baseText, local: localText, external: externalText)
        else {
            return .conflict(
                NoteConflict(noteID: noteID, local: local, external: external, commonBase: base)
            )
        }
        return .resolved(Data(merged.utf8))
    }

    private func mergeAlignedLines(base: String, local: String, external: String) -> String? {
        let baseLines = base.components(separatedBy: "\n")
        let localLines = local.components(separatedBy: "\n")
        let externalLines = external.components(separatedBy: "\n")
        guard baseLines.count == localLines.count,
              baseLines.count == externalLines.count else { return nil }

        var merged = baseLines
        for index in baseLines.indices {
            let localChanged = localLines[index] != baseLines[index]
            let externalChanged = externalLines[index] != baseLines[index]
            switch (localChanged, externalChanged) {
            case (false, false): break
            case (true, false): merged[index] = localLines[index]
            case (false, true): merged[index] = externalLines[index]
            case (true, true):
                guard localLines[index] == externalLines[index] else { return nil }
                merged[index] = localLines[index]
            }
        }
        return merged.joined(separator: "\n")
    }
}

public struct CloudPendingEdit: Equatable, Sendable {
    public let data: Data
    public let modifiedAt: Date

    public init(data: Data, modifiedAt: Date = Date()) {
        self.data = data
        self.modifiedAt = modifiedAt
    }
}

public struct CloudReconciliationReport: Equatable, Sendable {
    public var createdIdentities: [NoteID] = []
    public var matchedIdentities: [NoteID] = []
    public var mergedIdentities: [NoteID] = []
    public var tombstonedIdentities: [NoteID] = []
    public var deferredPaths: [String] = []
    public var awaitingDeletionConfirmation: [NoteID] = []
    public var ambiguousPaths: [String] = []
    public var duplicateRecordIdentities: [NoteID] = []
    public var conflicts: [NoteConflict] = []
    public var preservedConflictPaths: [String] = []

    public init() {}
}

/// Reconciles one device's pending edits with the coordinated iCloud document
/// view and the private, synchronized reconciliation-record directory. The
/// public `Documents` directory remains clean note files only.
public actor CloudCollectionReconciler {
    private let documents: any CloudDocumentAccess
    private let records: any CloudDocumentAccess
    private let identityResolver = ReconciliationIdentityResolver()
    private let merger = NoteContentMerger()

    public init(
        documents: any CloudDocumentAccess,
        reconciliationRecords: any CloudDocumentAccess
    ) {
        self.documents = documents
        records = reconciliationRecords
    }

    public func reconcile(
        pendingLocalEdits: [NoteID: CloudPendingEdit] = [:],
        confirmedDeletions: Set<NoteID> = []
    ) throws -> CloudReconciliationReport {
        var report = CloudReconciliationReport()
        var loadedRecords = try loadRecords(report: &report)
        var claimed = Set<NoteID>()
        let snapshots = try documents.listDocuments().filter {
            NoteFormat.format(forPathExtension: ($0.relativePath as NSString).pathExtension) != nil
        }
        let observedPaths = Set(snapshots.map(\.relativePath))

        for snapshot in snapshots {
            guard snapshot.availability == .available else {
                report.deferredPaths.append(snapshot.relativePath)
                for record in loadedRecords.values.flatMap({ $0 })
                    where record.currentRelativePath == snapshot.relativePath {
                    claimed.insert(record.noteID)
                }
                continue
            }

            let match = identityResolver.resolve(
                snapshot,
                records: Array(loadedRecords.values.flatMap { $0 }),
                claimedIDs: claimed
            )
            switch match {
            case .deferred:
                report.deferredPaths.append(snapshot.relativePath)

            case let .ambiguous(ids):
                report.ambiguousPaths.append(snapshot.relativePath)
                report.duplicateRecordIdentities.append(contentsOf: ids)

            case let .newIdentity(noteID):
                let data = try documents.read(relativePath: snapshot.relativePath)
                let now = snapshot.modifiedAt ?? Date()
                let record = ReconciliationRecord(
                    noteID: noteID,
                    currentRelativePath: snapshot.relativePath,
                    rawContentHash: ContentHash.sha256(data),
                    lastCommonRevisionHash: ContentHash.sha256(data),
                    mergeBaseContent: data,
                    createdAt: now,
                    modifiedAt: now
                )
                try save(record)
                loadedRecords[noteID] = [record]
                claimed.insert(noteID)
                report.createdIdentities.append(noteID)

            case let .matched(noteID):
                guard var record = loadedRecords[noteID]?.first else {
                    report.ambiguousPaths.append(snapshot.relativePath)
                    continue
                }
                claimed.insert(noteID)
                let externalData = try documents.read(relativePath: snapshot.relativePath)
                let external = revision(
                    data: externalData,
                    modifiedAt: snapshot.modifiedAt ?? record.modifiedAt
                )

                if snapshot.hasUnresolvedConflicts {
                    let versions = try documents.unresolvedConflictVersions(
                        relativePath: snapshot.relativePath
                    )
                    for version in versions {
                        report.conflicts.append(
                            NoteConflict(
                                noteID: noteID,
                                local: external,
                                external: revision(data: version.data, modifiedAt: version.modifiedAt),
                                commonBase: baseRevision(for: record)
                            )
                        )
                    }
                    if !versions.isEmpty {
                        report.matchedIdentities.append(noteID)
                        continue
                    }
                }

                if let pending = pendingLocalEdits[noteID] {
                    let local = revision(data: pending.data, modifiedAt: pending.modifiedAt)
                    switch merger.merge(
                        noteID: noteID,
                        format: format(for: snapshot.relativePath),
                        base: baseRevision(for: record),
                        local: local,
                        external: external
                    ) {
                    case let .resolved(data):
                        try documents.write(data, relativePath: snapshot.relativePath)
                        update(&record, path: snapshot.relativePath, data: data, modifiedAt: max(local.modifiedAt, external.modifiedAt))
                        report.mergedIdentities.append(noteID)

                    case let .conflict(conflict):
                        report.conflicts.append(conflict)
                        try documents.write(local.content, relativePath: snapshot.relativePath)
                        update(&record, path: snapshot.relativePath, data: local.content, modifiedAt: local.modifiedAt)
                        let conflictPath = availableConflictPath(
                            for: snapshot.relativePath,
                            occupiedPaths: observedPaths.union(report.preservedConflictPaths)
                        )
                        try documents.write(external.content, relativePath: conflictPath)
                        let conflictID = NoteID()
                        let conflictRecord = ReconciliationRecord(
                            noteID: conflictID,
                            currentRelativePath: conflictPath,
                            rawContentHash: external.contentHash,
                            lastCommonRevisionHash: external.contentHash,
                            mergeBaseContent: external.content,
                            createdAt: external.modifiedAt,
                            modifiedAt: external.modifiedAt
                        )
                        try save(conflictRecord)
                        loadedRecords[conflictID] = [conflictRecord]
                        report.preservedConflictPaths.append(conflictPath)
                    }
                } else {
                    update(
                        &record,
                        path: snapshot.relativePath,
                        data: externalData,
                        modifiedAt: external.modifiedAt
                    )
                    report.matchedIdentities.append(noteID)
                }
                try save(record)
                loadedRecords[noteID] = [record]
            }
        }

        for (noteID, candidates) in loadedRecords where !claimed.contains(noteID) {
            guard var record = candidates.first, !record.isTombstone else { continue }
            if confirmedDeletions.contains(noteID) {
                record.isTombstone = true
                record.mergeBaseContent = nil
                try save(record)
                report.tombstonedIdentities.append(noteID)
            } else if let pending = pendingLocalEdits[noteID] {
                try documents.write(pending.data, relativePath: record.currentRelativePath)
                update(
                    &record,
                    path: record.currentRelativePath,
                    data: pending.data,
                    modifiedAt: pending.modifiedAt
                )
                try save(record)
                report.mergedIdentities.append(noteID)
            } else if !observedPaths.contains(record.currentRelativePath) {
                report.awaitingDeletionConfirmation.append(noteID)
            }
        }

        report.duplicateRecordIdentities = Array(Set(report.duplicateRecordIdentities))
            .sorted { $0.description < $1.description }
        return report
    }

    private func loadRecords(
        report: inout CloudReconciliationReport
    ) throws -> [NoteID: [ReconciliationRecord]] {
        var loaded: [NoteID: [ReconciliationRecord]] = [:]
        for snapshot in try records.listDocuments() where snapshot.relativePath.hasSuffix(".json") {
            guard snapshot.availability == .available else {
                report.deferredPaths.append("records/\(snapshot.relativePath)")
                if snapshot.availability == .unavailable {
                    try records.requestDownload(relativePath: snapshot.relativePath)
                }
                continue
            }
            let record = try Self.decoder.decode(
                ReconciliationRecord.self,
                from: records.read(relativePath: snapshot.relativePath)
            )
            guard record.schemaVersion == ReconciliationRecord.currentSchemaVersion else {
                throw ReconciliationStoreError.unsupportedSchema(record.schemaVersion)
            }
            try ReconciliationStore.validate(relativePath: record.currentRelativePath)
            loaded[record.noteID, default: []].append(record)
        }
        for (id, candidates) in loaded where candidates.count > 1 {
            report.duplicateRecordIdentities.append(id)
        }
        return loaded
    }

    private func save(_ record: ReconciliationRecord) throws {
        try records.write(
            Self.encoder.encode(record),
            relativePath: record.noteID.description + ".json"
        )
    }

    private func update(
        _ record: inout ReconciliationRecord,
        path: String,
        data: Data,
        modifiedAt: Date
    ) {
        record.move(to: path)
        record.rawContentHash = ContentHash.sha256(data)
        record.lastCommonRevisionHash = record.rawContentHash
        record.mergeBaseContent = data.count <= ReconciliationRecord.maximumMergeBaseBytes ? data : nil
        record.modifiedAt = modifiedAt
        record.isTombstone = false
    }

    private func revision(data: Data, modifiedAt: Date) -> NoteRevision {
        NoteRevision(
            contentHash: ContentHash.sha256(data),
            content: data,
            modifiedAt: modifiedAt
        )
    }

    private func baseRevision(for record: ReconciliationRecord) -> NoteRevision? {
        guard let data = record.mergeBaseContent else { return nil }
        return NoteRevision(
            contentHash: record.lastCommonRevisionHash ?? ContentHash.sha256(data),
            content: data,
            modifiedAt: record.modifiedAt
        )
    }

    private func format(for relativePath: String) -> NoteFormat {
        NoteFormat.format(forPathExtension: (relativePath as NSString).pathExtension) ?? .plainText
    }

    private func availableConflictPath(
        for relativePath: String,
        occupiedPaths: Set<String>
    ) -> String {
        let path = relativePath as NSString
        let folder = path.deletingLastPathComponent
        let ext = path.pathExtension
        let base = path.deletingPathExtension
        let occupied = Set(occupiedPaths.map { $0.lowercased() })
        var counter = 1
        while true {
            let suffix = counter == 1 ? " (Conflict)" : " (Conflict \(counter))"
            let filename = (base as NSString).lastPathComponent + suffix + (ext.isEmpty ? "" : ".\(ext)")
            let candidate = folder == "." || folder.isEmpty ? filename : "\(folder)/\(filename)"
            if !occupied.contains(candidate.lowercased()) { return candidate }
            counter += 1
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
