import Foundation
import XCTest

final class NotesMigrationTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpiralNotesMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
    }

    func testMoveToICloudIsTheDefaultChoice() {
        XCTAssertEqual(NotesMigrationChoice.defaultChoice, .moveToICloud)
    }

    func testMigrationChoiceModalResponsesRoundTrip() {
        let choices: [NotesMigrationChoice] = [
            .keepCurrentLocation,
            .copyToICloud,
            .moveToICloud
        ]

        for choice in choices {
            XCTAssertEqual(
                MigrationChoiceModalResponse.choice(
                    for: MigrationChoiceModalResponse.response(for: choice)
                ),
                choice
            )
        }
    }

    func testCopyProgressPromisesToKeepOriginalFolder() {
        let message = NotesMigrationProgressText.copyingNotes(for: .copyToICloud)

        XCTAssertEqual(
            message,
            "Spiral is copying and verifying your notes. The original folder will be kept."
        )
        XCTAssertFalse(message.localizedCaseInsensitiveContains("delete"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("remove"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("trash"))
    }

    func testLateOperationCompletionCannotReplaceTimeout() throws {
        let gate = NotesMigrationOperationGate<Int>()
        let timeout = NSError(domain: "NotesMigrationTests", code: 1)

        XCTAssertTrue(gate.finish(with: .failure(timeout)))
        XCTAssertFalse(gate.finish(with: .success(42)))

        guard case .failure(let storedError)? = gate.result else {
            return XCTFail("Expected the timeout to remain the terminal result")
        }
        XCTAssertEqual((storedError as NSError).domain, timeout.domain)
        XCTAssertEqual((storedError as NSError).code, timeout.code)
    }

    func testOperationCompletionCannotBeReplacedByLaterTimeout() throws {
        let gate = NotesMigrationOperationGate<Int>()
        let timeout = NSError(domain: "NotesMigrationTests", code: 2)

        XCTAssertTrue(gate.finish(with: .success(42)))
        XCTAssertFalse(gate.finish(with: .failure(timeout)))

        XCTAssertEqual(try gate.result?.get(), 42)
    }

    func testFreshInstallUsesICloudByDefault() {
        XCTAssertEqual(
            NotesStartupLocationPolicy.decision(
                preferencesStartupState: .freshInstall
            ),
            .useICloudByDefault
        )
    }

    func testExistingSpiralPreferencesUseTheirCurrentLocation() {
        XCTAssertEqual(
            NotesStartupLocationPolicy.decision(
                preferencesStartupState: .existingSpiralPreferences
            ),
            .useCurrentLocation
        )
    }

    func testImportedLegacyPreferencesReceiveMigrationOffer() {
        XCTAssertEqual(
            NotesStartupLocationPolicy.decision(
                preferencesStartupState: .importedLegacyPreferences
            ),
            .offerICloudMigration
        )
    }

    func testFreshContainerCreatesDocumentsDirectory() throws {
        let container = temporaryRoot.appendingPathComponent("Fresh Container", isDirectory: true)

        let destination = try NotesDefaultLocationService()
            .prepareDocumentsDirectory(in: container)

        XCTAssertEqual(destination, container.appendingPathComponent("Documents", isDirectory: true))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testExistingICloudCollectionIsAdoptedWithoutModification() throws {
        let container = temporaryRoot.appendingPathComponent("Existing Container", isDirectory: true)
        let destination = container.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let database = destination.appendingPathComponent("Notes & Settings")
        try Data("existing iCloud database".utf8).write(to: database)

        let prepared = try NotesDefaultLocationService()
            .prepareDocumentsDirectory(in: container)

        XCTAssertEqual(prepared, destination)
        XCTAssertEqual(try Data(contentsOf: database), Data("existing iCloud database".utf8))
    }

    func testUnrelatedICloudDataIsRefusedWithoutModification() throws {
        let container = temporaryRoot.appendingPathComponent("Unrelated Container", isDirectory: true)
        let destination = container.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let unrelatedFile = destination.appendingPathComponent("Budget.txt")
        try Data("keep me".utf8).write(to: unrelatedFile)

        XCTAssertThrowsError(
            try NotesDefaultLocationService().prepareDocumentsDirectory(in: container)
        ) { error in
            XCTAssertEqual(error as? NotesDefaultLocationError, .destinationContainsUnrelatedData)
        }
        XCTAssertEqual(try Data(contentsOf: unrelatedFile), Data("keep me".utf8))
    }

    func testConfiguredContainerStatusRequiresExactDocumentsDirectory() {
        let container = URL(fileURLWithPath: "/Users/example/Library/Mobile Documents/iCloud~farm~poplar~spiral", isDirectory: true)
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        let otherICloudFolder = URL(fileURLWithPath: "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/Notes", isDirectory: true)

        XCTAssertTrue(
            NotesICloudContainerStatus.usesConfiguredDocumentsDirectory(
                currentURL: documents,
                containerURL: container
            )
        )
        XCTAssertFalse(
            NotesICloudContainerStatus.usesConfiguredDocumentsDirectory(
                currentURL: otherICloudFolder,
                containerURL: container
            )
        )
    }

    func testEmptyCollectionDoesNotTriggerOffer() throws {
        let source = temporaryRoot.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)

        XCTAssertFalse(NotesMigrationService().containsNotes(at: source))
        XCTAssertEqual(try NotesMigrationService().classifyFolder(at: source), .empty)
    }

    func testFinderMetadataDoesNotMakeFolderNonEmpty() throws {
        let folder = temporaryRoot.appendingPathComponent("Finder Metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("metadata".utf8).write(to: folder.appendingPathComponent(".DS_Store"))

        XCTAssertEqual(try NotesMigrationService().classifyFolder(at: folder), .empty)
    }

    func testCanonicalDatabaseIdentifiesExistingNoteCollection() throws {
        let folder = temporaryRoot.appendingPathComponent("Existing Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("database fixture".utf8).write(to: folder.appendingPathComponent("Notes & Settings"))
        try Data("note".utf8).write(to: folder.appendingPathComponent("Welcome.txt"))

        XCTAssertEqual(try NotesMigrationService().classifyFolder(at: folder), .noteCollection)
    }

    func testJournalIdentifiesExistingNoteCollection() throws {
        let folder = temporaryRoot.appendingPathComponent("Recoverable Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("journal fixture".utf8).write(to: folder.appendingPathComponent("Interim Note-Changes"))

        XCTAssertEqual(try NotesMigrationService().classifyFolder(at: folder), .noteCollection)
    }

    func testUnrelatedNonemptyFolderIsRegularFolder() throws {
        let folder = temporaryRoot.appendingPathComponent("Regular Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("unrelated".utf8).write(to: folder.appendingPathComponent("Budget.txt"))

        XCTAssertEqual(try NotesMigrationService().classifyFolder(at: folder), .regularFolder)
    }

    func testCopyPublishesVerifiedCollectionAndPreservesSource() throws {
        let source = try makeFixtureCollection()
        let container = temporaryRoot.appendingPathComponent("Container", isDirectory: true)
        let destination = container.appendingPathComponent("Documents", isDirectory: true)

        try NotesMigrationService().copyAndVerifyCollection(from: source, to: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("Notes & Settings")),
            Data("database fixture".utf8)
        )
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("Notes/Welcome.txt"), encoding: .utf8),
            "Welcome to Spiral"
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: container.path).sorted(),
            ["Documents"]
        )
    }

    func testExistingICloudDataIsNeverOverwritten() throws {
        let source = try makeFixtureCollection()
        let destination = temporaryRoot.appendingPathComponent("Container/Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let existing = destination.appendingPathComponent("Existing.txt")
        try Data("existing iOS note".utf8).write(to: existing)

        XCTAssertThrowsError(
            try NotesMigrationService().copyAndVerifyCollection(from: source, to: destination)
        ) { error in
            guard case NotesMigrationError.destinationContainsData = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing iOS note".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func makeFixtureCollection() throws -> URL {
        let source = temporaryRoot.appendingPathComponent("Local Notes", isDirectory: true)
        let notes = source.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("database fixture".utf8).write(to: source.appendingPathComponent("Notes & Settings"))
        try Data("Welcome to Spiral".utf8).write(to: notes.appendingPathComponent("Welcome.txt"))
        try Data("ignored Finder metadata".utf8).write(to: source.appendingPathComponent(".DS_Store"))
        return source
    }
}
