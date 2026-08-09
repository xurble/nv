import Foundation

enum NotesMigrationChoice: String, Equatable {
    case keepCurrentLocation
    case copyToICloud

    static let defaultChoice: NotesMigrationChoice = .copyToICloud
}

enum NotesMigrationProgressText {
    static let connectingToICloud =
        "Spiral is waiting for iCloud Drive. Your current notes folder will not be changed."

    static func copyingNotes(for choice: NotesMigrationChoice) -> String {
        switch choice {
        case .copyToICloud:
            return "Spiral is copying and verifying your notes. The original folder will be kept."
        case .keepCurrentLocation:
            return "Your current notes folder will not be changed."
        }
    }
}

/// Arbitrates completion between a background operation and a deadline. Only
/// the first result is accepted so a late callback cannot affect later UI.
final class NotesMigrationOperationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<Value, Error>?

    @discardableResult
    func finish(with result: Result<Value, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storedResult == nil else { return false }
        storedResult = result
        return true
    }

    var result: Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }
}

enum NotesFolderClassification: Equatable {
    case empty
    case noteCollection
    case regularFolder
}

enum NotesStartupLocationDecision: Equatable {
    case useCurrentLocation
    case useICloudByDefault
    case offerLegacyNotesImport
}

struct NotesStartupLocationPolicy {
    static func decision(
        preferencesStartupState: SpiralPreferencesStartupState
    ) -> NotesStartupLocationDecision {
        switch preferencesStartupState {
        case .existingSpiralPreferences:
            return .useCurrentLocation
        case .legacyPreferencesFound:
            return .offerLegacyNotesImport
        case .freshInstall:
            return .useICloudByDefault
        }
    }
}

enum NotesDefaultLocationError: LocalizedError, Equatable {
    case destinationContainsUnrelatedData

    var errorDescription: String? {
        switch self {
        case .destinationContainsUnrelatedData:
            return "Spiral Notes in iCloud Drive contains unrelated files and cannot be used as the default notes folder."
        }
    }
}

struct NotesDefaultLocationService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepareDocumentsDirectory(in containerURL: URL) throws -> URL {
        let destinationURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        switch try NotesMigrationService(fileManager: fileManager).classifyFolder(at: destinationURL) {
        case .regularFolder:
            throw NotesDefaultLocationError.destinationContainsUnrelatedData
        case .empty:
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        case .noteCollection:
            break
        }
        return destinationURL
    }
}

struct NotesICloudContainerStatus {
    static func usesConfiguredDocumentsDirectory(
        currentURL: URL,
        containerURL: URL
    ) -> Bool {
        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        return NotesMigrationService().sameDirectory(currentURL, documentsURL)
    }
}

enum NotesMigrationError: LocalizedError {
    case sourceDoesNotExist
    case sourceIsNotDirectory
    case destinationContainsData
    case unsupportedItem(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceDoesNotExist:
            return "The current notes folder no longer exists."
        case .sourceIsNotDirectory:
            return "The current notes location is not a folder."
        case .destinationContainsData:
            return "Spiral Notes in iCloud Drive already contains files. No files were changed."
        case let .unsupportedItem(path):
            return "The notes folder contains an unsupported item at \(path)."
        case let .verificationFailed(path):
            return "The copy could not be verified at \(path). The original notes were not removed."
        }
    }
}

struct NotesMigrationService {
    private static let ignorableNames: Set<String> = [".DS_Store"]
    private static let collectionMarkerNames: Set<String> = [
        "Notes & Settings",
        "Interim Note-Changes",
        ".spiral-notes"
    ]
    private static let stagingPrefix = ".SpiralNotesMigration-"

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func containsNotes(at directoryURL: URL) -> Bool {
        guard let contents = try? significantContents(of: directoryURL) else {
            return false
        }
        return !contents.isEmpty
    }

    func classifyFolder(at directoryURL: URL) throws -> NotesFolderClassification {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            return .empty
        }
        guard isDirectory.boolValue else {
            throw NotesMigrationError.sourceIsNotDirectory
        }
        let contents = try significantContents(of: directoryURL)
        guard !contents.isEmpty else { return .empty }

        let names = Set(contents.map(\.lastPathComponent))
        if !names.isDisjoint(with: Self.collectionMarkerNames)
            || names.contains(where: { $0.hasPrefix("Notes & Settings (") }) {
            return .noteCollection
        }

        return .regularFolder
    }

    func sameDirectory(_ firstURL: URL, _ secondURL: URL) -> Bool {
        let first = firstURL.resolvingSymlinksInPath().standardizedFileURL
        let second = secondURL.resolvingSymlinksInPath().standardizedFileURL
        return first == second
    }

    /// Copies a complete note collection through a private staging directory,
    /// verifies every copied item, then publishes it as the container's
    /// Documents directory. The source is never modified by this operation.
    func copyAndVerifyCollection(from sourceURL: URL, to destinationURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw NotesMigrationError.sourceDoesNotExist
        }
        guard isDirectory.boolValue else {
            throw NotesMigrationError.sourceIsNotDirectory
        }
        guard !sameDirectory(sourceURL, destinationURL) else {
            return
        }

        let destinationParent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var migrationError: Error?

        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: .withoutChanges,
            writingItemAt: destinationParent,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedSource, coordinatedParent in
            do {
                let coordinatedDestination = coordinatedParent
                    .appendingPathComponent(destinationURL.lastPathComponent, isDirectory: true)
                try copyAndVerifyWithoutCoordination(
                    from: coordinatedSource,
                    to: coordinatedDestination,
                    stagingParent: coordinatedParent
                )
            } catch {
                migrationError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let migrationError {
            throw migrationError
        }
    }

    private func copyAndVerifyWithoutCoordination(
        from sourceURL: URL,
        to destinationURL: URL,
        stagingParent: URL
    ) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            guard try significantContents(of: destinationURL).isEmpty else {
                throw NotesMigrationError.destinationContainsData
            }
        } else {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)
        }

        let stagingURL = stagingParent.appendingPathComponent(
            Self.stagingPrefix + UUID().uuidString,
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: stagingURL) }

        for itemURL in try significantContents(of: sourceURL) {
            try fileManager.copyItem(
                at: itemURL,
                to: stagingURL.appendingPathComponent(itemURL.lastPathComponent)
            )
        }

        try verifyCollection(at: stagingURL, matches: sourceURL)

        try fileManager.removeItem(at: destinationURL)
        do {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        } catch {
            try? fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            throw error
        }

        try verifyCollection(at: destinationURL, matches: sourceURL)
    }

    private func significantContents(of directoryURL: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ).filter { !Self.ignorableNames.contains($0.lastPathComponent) }
    }

    private func verifyCollection(at copyURL: URL, matches sourceURL: URL) throws {
        let sourcePaths = try relativePaths(in: sourceURL)
        let copiedPaths = try relativePaths(in: copyURL)
        guard sourcePaths == copiedPaths else {
            throw NotesMigrationError.verificationFailed("the collection contents")
        }

        for relativePath in sourcePaths {
            let sourceItem = sourceURL.appendingPathComponent(relativePath)
            let copiedItem = copyURL.appendingPathComponent(relativePath)
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            let sourceValues = try sourceItem.resourceValues(forKeys: keys)
            let copiedValues = try copiedItem.resourceValues(forKeys: keys)

            guard sourceValues.isDirectory == copiedValues.isDirectory,
                  sourceValues.isRegularFile == copiedValues.isRegularFile,
                  sourceValues.isSymbolicLink == copiedValues.isSymbolicLink else {
                throw NotesMigrationError.verificationFailed(relativePath)
            }

            if sourceValues.isRegularFile == true {
                guard sourceValues.fileSize == copiedValues.fileSize,
                      try filesHaveEqualContents(sourceItem, copiedItem) else {
                    throw NotesMigrationError.verificationFailed(relativePath)
                }
            } else if sourceValues.isSymbolicLink == true {
                let sourceTarget = try fileManager.destinationOfSymbolicLink(atPath: sourceItem.path)
                let copiedTarget = try fileManager.destinationOfSymbolicLink(atPath: copiedItem.path)
                guard sourceTarget == copiedTarget else {
                    throw NotesMigrationError.verificationFailed(relativePath)
                }
            } else if sourceValues.isDirectory != true {
                throw NotesMigrationError.unsupportedItem(relativePath)
            }
        }
    }

    private func relativePaths(in rootURL: URL) throws -> [String] {
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            return []
        }

        let rootPath = rootURL.standardizedFileURL.path
        var paths: [String] = []
        for case let itemURL as URL in enumerator {
            let relativePath = String(itemURL.standardizedFileURL.path.dropFirst(rootPath.count + 1))
            if relativePath.split(separator: "/").contains(where: { Self.ignorableNames.contains(String($0)) }) {
                continue
            }
            paths.append(relativePath)
        }
        if let enumerationError {
            throw enumerationError
        }
        return paths.sorted()
    }

    private func filesHaveEqualContents(_ firstURL: URL, _ secondURL: URL) throws -> Bool {
        let firstHandle = try FileHandle(forReadingFrom: firstURL)
        let secondHandle = try FileHandle(forReadingFrom: secondURL)
        defer {
            try? firstHandle.close()
            try? secondHandle.close()
        }

        let chunkSize = 1024 * 1024
        while true {
            let firstChunk = try firstHandle.read(upToCount: chunkSize) ?? Data()
            let secondChunk = try secondHandle.read(upToCount: chunkSize) ?? Data()
            guard firstChunk == secondChunk else { return false }
            if firstChunk.isEmpty { return true }
        }
    }
}
