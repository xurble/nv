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

private final class NVLegacySnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: LegacyCollectionSnapshot?

    func record(_ snapshot: LegacyCollectionSnapshot) {
        lock.withLock { value = snapshot }
    }

    var snapshot: LegacyCollectionSnapshot? {
        lock.withLock { value }
    }
}

struct NVLegacyArchiveSource: @unchecked Sendable, LegacyCompatibilitySource {
    let collectionURL: URL
    let protection: LegacyCollectionProtection
    let passphraseData: Data?
    private let recorder: NVLegacySnapshotRecorder?

    init(
        collectionURL: URL,
        protection: LegacyCollectionProtection,
        passphraseData: Data? = nil
    ) {
        self.collectionURL = collectionURL
        self.protection = protection
        self.passphraseData = passphraseData
        recorder = nil
    }

    fileprivate init(
        collectionURL: URL,
        protection: LegacyCollectionProtection,
        passphraseData: Data?,
        recorder: NVLegacySnapshotRecorder
    ) {
        self.collectionURL = collectionURL
        self.protection = protection
        self.passphraseData = passphraseData
        self.recorder = recorder
    }

    func loadSnapshot(from verifiedWorkingCopyURL: URL) throws -> LegacyCollectionSnapshot {
        do {
            let preparation = try NVLegacyCollectionImporter.prepareWorkingCopy(
                at: verifiedWorkingCopyURL,
                passphraseData: passphraseData
            )
            let codec = NoteFileCodec()
            let notes = try preparation.noteSnapshots.map { value in
                guard let title = value["title"] as? String,
                      let representation = value["representation"] as? Data,
                      let formatValue = (value["format"] as? NSNumber)?.intValue,
                      let createdAt = value["createdAt"] as? Date,
                      let modifiedAt = value["modifiedAt"] as? Date else {
                    throw LegacyCompatibilityError.damagedArchive
                }
                let format: NoteFormat
                switch formatValue {
                case 1: format = .plainText
                case 2: format = .richText
                case 3: format = .html
                default: throw LegacyCompatibilityError.unsupportedItem("format \(formatValue)")
                }
                return LegacyNoteSnapshot(
                    title: title,
                    content: try codec.decode(representation, as: format),
                    tags: value["tags"] as? [String] ?? [],
                    legacyMetadata: value["legacyMetadata"] as? [String: Data] ?? [:],
                    createdAt: createdAt,
                    modifiedAt: modifiedAt
                )
            }
            let snapshot = LegacyCollectionSnapshot(
                sourceApplication: preparation.sourceApplication,
                sourceVersion: preparation.sourceVersion,
                notes: notes,
                collectionMetadata: preparation.collectionMetadata,
                recoveredWAL: preparation.recoveredWAL
            )
            recorder?.record(snapshot)
            return snapshot
        } catch let error as NSError {
            switch error.code {
            case 4: throw LegacyCompatibilityError.noNotes
            case 6: throw LegacyCompatibilityError.wrongPassphrase
            case 7: throw LegacyCompatibilityError.damagedArchive
            default:
                if error.localizedDescription.localizedCaseInsensitiveContains("cancel") {
                    throw LegacyCompatibilityError.passphraseCancelled
                }
                throw error
            }
        }
    }
}

private struct LegacyMigrationProbeReport: Codable {
    struct MigratedNote: Codable {
        let title: String
        let format: NoteFormat
        let text: String
        let tags: [String]
        let legacyMetadata: [String: Data]
        let createdAt: Date
        let modifiedAt: Date
    }

    let sourceFingerprint: LegacyCollectionFingerprint
    let backupFingerprint: LegacyCollectionFingerprint
    let sourceApplication: String
    let sourceVersion: String?
    let collectionMetadata: [String: Data]
    let recoveredWAL: Bool
    let notes: [MigratedNote]
}

private enum LegacyMigrationProbeError: Error {
    case fixtureMismatch(String)
}

@objc(SpiralLegacyMigrationProbe)
final class SpiralLegacyMigrationProbe: NSObject {
    @objc(runWithSourceURL:destinationRootURL:reportURL:encrypted:passphraseData:failureAfterImportedNoteCount:completion:)
    static func run(
        sourceURL: URL,
        destinationRootURL: URL,
        reportURL: URL,
        encrypted: Bool,
        passphraseData: Data?,
        failureAfterImportedNoteCount: NSNumber?,
        completion: @escaping (Int32, String?) -> Void
    ) {
        Task {
            do {
                let recorder = NVLegacySnapshotRecorder()
                let source = NVLegacyArchiveSource(
                    collectionURL: sourceURL,
                    protection: encrypted ? .legacyApplicationEncryption : .plaintext,
                    passphraseData: passphraseData,
                    recorder: recorder
                )
                let destination = LegacyMigrationDestination(
                    documentsURL: destinationRootURL.appendingPathComponent("Documents", isDirectory: true),
                    reconciliationURL: destinationRootURL.appendingPathComponent("Private/Reconciliation", isDirectory: true),
            indexURL: destinationRootURL.appendingPathComponent("Cache/Catalog.sqlite"),
                    retainedBackupURL: destinationRootURL.appendingPathComponent("Retained Legacy Backup", isDirectory: true)
                )
                let result = try await LegacyMigrationService().migrate(
                    source: source,
                    to: destination,
                    confirmsPlaintextDestination: encrypted,
                    failureAfterImportedNoteCount: failureAfterImportedNoteCount?.intValue
                )
                guard let snapshot = recorder.snapshot else {
                    throw LegacyCompatibilityError.damagedArchive
                }
                let notes = await result.store.allNotes().sorted { $0.title < $1.title }.map {
                    LegacyMigrationProbeReport.MigratedNote(
                        title: $0.title,
                        format: $0.content.format,
                        text: $0.content.text,
                        tags: $0.tags,
                        legacyMetadata: $0.legacyMetadata,
                        createdAt: $0.createdAt,
                        modifiedAt: $0.modifiedAt
                    )
                }
                let report = LegacyMigrationProbeReport(
                    sourceFingerprint: result.sourceFingerprint,
                    backupFingerprint: try LegacyCollectionVerifier.fingerprint(at: result.retainedBackupURL),
                    sourceApplication: snapshot.sourceApplication,
                    sourceVersion: snapshot.sourceVersion,
                    collectionMetadata: snapshot.collectionMetadata,
                    recoveredWAL: result.recoveredWAL,
                    notes: notes
                )
                try validate(report: report, fixtureAt: sourceURL)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try FileManager.default.createDirectory(
                    at: reportURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try encoder.encode(report).write(to: reportURL, options: .atomic)
                completion(0, nil)
            } catch {
                completion(1, String(describing: error))
            }
        }
    }

    private static func validate(report: LegacyMigrationProbeReport, fixtureAt sourceURL: URL) throws {
        guard report.sourceFingerprint == report.backupFingerprint else {
            throw LegacyMigrationProbeError.fixtureMismatch("retained backup differs from source")
        }
        let manifestURL = sourceURL.appendingPathComponent("LegacyFixtureManifest.plist")
        let manifestData = try Data(contentsOf: manifestURL)
        guard let manifest = try PropertyListSerialization.propertyList(
            from: manifestData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw LegacyMigrationProbeError.fixtureMismatch("fixture manifest is missing")
        }
        guard report.sourceApplication == manifest["sourceApplication"] as? String,
              report.sourceVersion == manifest["sourceVersion"] as? String,
              report.recoveredWAL == (manifest["recoveredWAL"] as? Bool) else {
            throw LegacyMigrationProbeError.fixtureMismatch("collection identity or WAL state differs")
        }
        let expectedIterations = (manifest["hashIterationCount"] as? NSNumber)?.intValue
        let iterationData = report.collectionMetadata["legacy.hashIterationCount"]
        let actualIterations = try iterationData.flatMap {
            try PropertyListSerialization.propertyList(from: $0, format: nil) as? NSNumber
        }?.intValue
        guard actualIterations == expectedIterations else {
            throw LegacyMigrationProbeError.fixtureMismatch("KDF iteration metadata differs")
        }
        if manifest["encrypted"] as? Bool == true {
            let keychainData = report.collectionMetadata["legacy.keychainDatabaseIdentifier"]
            let keychainIdentifier = try keychainData.flatMap {
                try PropertyListSerialization.propertyList(from: $0, format: nil) as? String
            }
            guard keychainIdentifier == "sanitized-fixture-keychain-id" else {
                throw LegacyMigrationProbeError.fixtureMismatch("Keychain identifier was not preserved")
            }
        }
        let expectedNotes = (manifest["expectedNotes"] as? [[String: Any]] ?? [])
            .sorted { ($0["title"] as? String ?? "") < ($1["title"] as? String ?? "") }
        guard expectedNotes.count == report.notes.count else {
            throw LegacyMigrationProbeError.fixtureMismatch("note count differs")
        }
        for (expected, actual) in zip(expectedNotes, report.notes) {
            guard actual.title == expected["title"] as? String,
                  actual.text == expected["text"] as? String,
                  actual.format.rawValue == expected["format"] as? String,
                  actual.tags == expected["tags"] as? [String] else {
                throw LegacyMigrationProbeError.fixtureMismatch(
                    "note values differ: expected \(expected), actual title=\(actual.title.debugDescription), " +
                    "text=\(actual.text.debugDescription), format=\(actual.format.rawValue), tags=\(actual.tags)"
                )
            }
            let requiredMetadata = [
                "legacy.uniqueNoteIDBytes", "legacy.syncServicesMD",
                "legacy.filename", "legacy.fileEncoding"
            ]
            guard requiredMetadata.allSatisfy({ actual.legacyMetadata[$0] != nil }) else {
                throw LegacyMigrationProbeError.fixtureMismatch("legacy metadata differs for \(actual.title)")
            }
        }
    }
}
