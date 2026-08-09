import Foundation
import XCTest
import Darwin

final class TemporaryCollectionIntegrationTests: XCTestCase {
    func testMigrationUsesOnlyDisposableDirectoriesAndPreservesSourceBytes() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpiralIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let source = temporaryRoot.appendingPathComponent("Source", isDirectory: true)
        let destination = temporaryRoot.appendingPathComponent("Container/Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let database = source.appendingPathComponent("Notes & Settings")
        let note = source.appendingPathComponent("Unicode.txt")
        try Data("archive fixture".utf8).write(to: database)
        try Data("café 日本".utf8).write(to: note)
        let databaseBefore = try Data(contentsOf: database)
        let noteBefore = try Data(contentsOf: note)

        try NotesMigrationService().copyAndVerifyCollection(from: source, to: destination)

        XCTAssertEqual(try Data(contentsOf: database), databaseBefore)
        XCTAssertEqual(try Data(contentsOf: note), noteBefore)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Notes & Settings")), databaseBefore)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Unicode.txt")), noteBefore)
        XCTAssertTrue(source.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    func testSymlinkAndNestedMetadataAreVerifiedWithoutFollowingOutsideCollection() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpiralIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let source = temporaryRoot.appendingPathComponent("Source", isDirectory: true)
        let nested = source.appendingPathComponent("Metadata", isDirectory: true)
        let destination = temporaryRoot.appendingPathComponent("Container/Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("archive fixture".utf8).write(to: source.appendingPathComponent("Notes & Settings"))
        try Data("labels".utf8).write(to: nested.appendingPathComponent("labels.plist"))
        try FileManager.default.createSymbolicLink(
            atPath: source.appendingPathComponent("metadata-link").path,
            withDestinationPath: "Metadata/labels.plist"
        )

        try NotesMigrationService().copyAndVerifyCollection(from: source, to: destination)

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("metadata-link").path),
            "Metadata/labels.plist"
        )
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("Metadata/labels.plist")),
            Data("labels".utf8)
        )
    }

    func testExtendedMetadataSurvivesVerifiedMigration() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpiralIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let source = temporaryRoot.appendingPathComponent("Source", isDirectory: true)
        let destination = temporaryRoot.appendingPathComponent("Container/Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let note = source.appendingPathComponent("Metadata.txt")
        try Data("metadata fixture".utf8).write(to: note)

        let attributeName = "com.notational.velocity.phase1-fixture"
        let attribute = Data("project,important".utf8)
        let writeResult = attribute.withUnsafeBytes { bytes in
            setxattr(note.path, attributeName, bytes.baseAddress, bytes.count, 0, 0)
        }
        XCTAssertEqual(writeResult, 0, "fixture extended metadata should be writable")

        try NotesMigrationService().copyAndVerifyCollection(from: source, to: destination)

        let copiedNote = destination.appendingPathComponent("Metadata.txt")
        let length = getxattr(copiedNote.path, attributeName, nil, 0, 0, 0)
        XCTAssertEqual(length, attribute.count)
        var copiedAttribute = Data(count: max(length, 0))
        let readResult = copiedAttribute.withUnsafeMutableBytes { bytes in
            getxattr(copiedNote.path, attributeName, bytes.baseAddress, bytes.count, 0, 0)
        }
        XCTAssertEqual(readResult, attribute.count)
        XCTAssertEqual(copiedAttribute, attribute)
    }
}
