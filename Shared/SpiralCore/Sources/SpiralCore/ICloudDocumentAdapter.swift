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

public enum CloudItemAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case downloadPending
}

public struct CloudDocumentSnapshot: Equatable, Sendable {
    public let relativePath: String
    public let contentHash: String?
    public let modifiedAt: Date?
    public let availability: CloudItemAvailability
    public let hasUnresolvedConflicts: Bool

    public init(
        relativePath: String,
        contentHash: String?,
        modifiedAt: Date?,
        availability: CloudItemAvailability,
        hasUnresolvedConflicts: Bool = false
    ) {
        self.relativePath = relativePath
        self.contentHash = contentHash
        self.modifiedAt = modifiedAt
        self.availability = availability
        self.hasUnresolvedConflicts = hasUnresolvedConflicts
    }
}

public struct CloudDocumentConflictVersion: Equatable, Sendable {
    public let data: Data
    public let modifiedAt: Date
    public let deviceName: String?

    public init(data: Data, modifiedAt: Date, deviceName: String? = nil) {
        self.data = data
        self.modifiedAt = modifiedAt
        self.deviceName = deviceName
    }
}

public enum CloudDocumentAdapterError: Error, Equatable, Sendable {
    case unsafeRelativePath(String)
    case rootIsNotDirectory
    case symbolicLink(String)
    case unavailable(String)
    case coordinationFailed(String)
}

/// OS 26-compatible document boundary. Production uses Foundation file
/// coordination; fault tests provide deterministic in-memory implementations.
public protocol CloudDocumentAccess: Sendable {
    var identifier: String { get }
    func listDocuments() throws -> [CloudDocumentSnapshot]
    func read(relativePath: String) throws -> Data
    func write(_ data: Data, relativePath: String) throws
    func move(from sourcePath: String, to destinationPath: String) throws
    func delete(relativePath: String) throws
    func requestDownload(relativePath: String) throws
    func unresolvedConflictVersions(relativePath: String) throws -> [CloudDocumentConflictVersion]
}

public struct UbiquityContainerLocator: Sendable {
    public init() {}

    public func containerURL(identifier: String?) -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: identifier)
    }
}

/// Foundation implementation for macOS 26, iOS 26, and iPadOS 26. All reads,
/// writes, moves, and deletes pass through `NSFileCoordinator`; unavailable
/// ubiquitous items are requested rather than interpreted as deletions.
public final class FoundationCloudDocumentAdapter: CloudDocumentAccess, @unchecked Sendable {
    public let identifier: String
    public let rootURL: URL

    private let fileManager: FileManager

    public init(
        rootURL: URL,
        identifier: String? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.identifier = identifier ?? self.rootURL.path
        self.fileManager = fileManager
        if fileManager.fileExists(atPath: self.rootURL.path) {
            let values = try self.rootURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true else { throw CloudDocumentAdapterError.rootIsNotDirectory }
            guard values.isSymbolicLink != true else {
                throw CloudDocumentAdapterError.symbolicLink(self.rootURL.lastPathComponent)
            }
        } else {
            try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        }
    }

    public func listDocuments() throws -> [CloudDocumentSnapshot] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var snapshots: [CloudDocumentSnapshot] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(Self.resourceKeys))
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            let relativePath = try relativePath(for: url)
            let availability = availability(for: values)
            let hash: String?
            if availability == .available {
                hash = try coordinatedRead(at: url) { ContentHash.sha256(try Data(contentsOf: $0)) }
            } else {
                hash = nil
            }
            snapshots.append(
                CloudDocumentSnapshot(
                    relativePath: relativePath,
                    contentHash: hash,
                    modifiedAt: values.contentModificationDate,
                    availability: availability,
                    hasUnresolvedConflicts: values.ubiquitousItemHasUnresolvedConflicts == true
                )
            )
        }
        return snapshots.sorted { $0.relativePath < $1.relativePath }
    }

    public func read(relativePath: String) throws -> Data {
        let url = try validatedURL(for: relativePath)
        let values = try url.resourceValues(forKeys: Set(Self.resourceKeys))
        guard availability(for: values) == .available else {
            throw CloudDocumentAdapterError.unavailable(relativePath)
        }
        return try coordinatedRead(at: url) { try Data(contentsOf: $0) }
    }

    public func write(_ data: Data, relativePath: String) throws {
        let url = try validatedURL(for: relativePath)
        try validateParents(of: url)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                operationError = error
            }
        }
        try throwIfNeeded(coordinationError: coordinationError, operationError: operationError)
    }

    public func move(from sourcePath: String, to destinationPath: String) throws {
        let sourceURL = try validatedURL(for: sourcePath)
        let destinationURL = try validatedURL(for: destinationPath)
        try validateParents(of: destinationURL)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: sourceURL,
            options: .forMoving,
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedSource, coordinatedDestination in
            do {
                if self.fileManager.fileExists(atPath: coordinatedDestination.path) {
                    try self.fileManager.removeItem(at: coordinatedDestination)
                }
                try self.fileManager.moveItem(at: coordinatedSource, to: coordinatedDestination)
            } catch {
                operationError = error
            }
        }
        try throwIfNeeded(coordinationError: coordinationError, operationError: operationError)
    }

    public func delete(relativePath: String) throws {
        let url = try validatedURL(for: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try self.fileManager.removeItem(at: coordinatedURL)
            } catch {
                operationError = error
            }
        }
        try throwIfNeeded(coordinationError: coordinationError, operationError: operationError)
    }

    public func requestDownload(relativePath: String) throws {
        try fileManager.startDownloadingUbiquitousItem(at: validatedURL(for: relativePath))
    }

    public func unresolvedConflictVersions(
        relativePath: String
    ) throws -> [CloudDocumentConflictVersion] {
        let url = try validatedURL(for: relativePath)
        return try (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map { version in
            return CloudDocumentConflictVersion(
                data: try Data(contentsOf: version.url),
                modifiedAt: version.modificationDate ?? .distantPast,
                deviceName: version.localizedNameOfSavingComputer
            )
        }
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemHasUnresolvedConflictsKey,
        .contentModificationDateKey
    ]

    private func availability(for values: URLResourceValues) -> CloudItemAvailability {
        guard values.isUbiquitousItem == true else { return .available }
        if values.ubiquitousItemIsDownloading == true { return .downloadPending }
        switch values.ubiquitousItemDownloadingStatus {
        case .current?, .downloaded?: return .available
        case .notDownloaded?: return .unavailable
        default: return .downloadPending
        }
    }

    private func validatedURL(for relativePath: String) throws -> URL {
        do {
            try ReconciliationStore.validate(relativePath: relativePath)
        } catch {
            throw CloudDocumentAdapterError.unsafeRelativePath(relativePath)
        }
        let url = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(rootURL.path + "/") else {
            throw CloudDocumentAdapterError.unsafeRelativePath(relativePath)
        }
        return url
    }

    private func relativePath(for url: URL) throws -> String {
        let standardized = url.standardizedFileURL
        guard standardized.path.hasPrefix(rootURL.path + "/") else {
            throw CloudDocumentAdapterError.unsafeRelativePath(standardized.path)
        }
        let relativePath = String(standardized.path.dropFirst(rootURL.path.count + 1))
        try ReconciliationStore.validate(relativePath: relativePath)
        return relativePath
    }

    private func validateParents(of url: URL) throws {
        var current = url.deletingLastPathComponent()
        while current.path.hasPrefix(rootURL.path + "/") {
            if fileManager.fileExists(atPath: current.path) {
                let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true else {
                    throw CloudDocumentAdapterError.rootIsNotDirectory
                }
                guard values.isSymbolicLink != true else {
                    throw CloudDocumentAdapterError.symbolicLink(current.lastPathComponent)
                }
            }
            current.deleteLastPathComponent()
        }
    }

    private func coordinatedRead<T>(at url: URL, operation: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try operation(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else {
            throw CloudDocumentAdapterError.coordinationFailed(url.lastPathComponent)
        }
        return try result.get()
    }

    private func throwIfNeeded(coordinationError: NSError?, operationError: Error?) throws {
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }
}

/// File-presentation bridge used by the apps to schedule a full reconciliation
/// scan after coordinated or external changes.
public final class CloudDocumentPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    public let presentedItemURL: URL?
    public let presentedItemOperationQueue: OperationQueue

    private let changeHandler: @Sendable () -> Void

    public init(rootURL: URL, changeHandler: @escaping @Sendable () -> Void) {
        presentedItemURL = rootURL
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        self.changeHandler = changeHandler
        super.init()
    }

    public func presentedSubitemDidAppear(at url: URL) { changeHandler() }
    public func presentedSubitemDidChange(at url: URL) { changeHandler() }
    public func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changeHandler() }
    public func accommodatePresentedSubitemDeletion(
        at url: URL,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        changeHandler()
        completionHandler(nil)
    }
}

/// Metadata-query bridge for ubiquitous download/conflict state changes. The
/// query is a signal only; authoritative reconciliation still performs a full
/// coordinated scan.
public final class CloudMetadataMonitor: NSObject, @unchecked Sendable {
    private let rootURL: URL
    private let query = NSMetadataQuery()
    private let changeHandler: @Sendable () -> Void
    private var isStarted = false

    public init(rootURL: URL, changeHandler: @escaping @Sendable () -> Void) {
        self.rootURL = rootURL
        self.changeHandler = changeHandler
        super.init()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        query.searchScopes = [rootURL]
        query.predicate = NSPredicate(value: true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryChanged),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryChanged),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        query.start()
    }

    public func stop() {
        guard isStarted else { return }
        query.stop()
        NotificationCenter.default.removeObserver(self)
        isStarted = false
    }

    @objc private func queryChanged() { changeHandler() }

    deinit { stop() }
}

/// Retains and starts both Foundation change-signal bridges for an app-owned
/// CloudNoteStore. Signals are coalesced by the store's full reconciliation;
/// they never carry authoritative file state themselves.
public final class CloudCollectionObserver: @unchecked Sendable {
    private let presenter: CloudDocumentPresenter
    private let metadataMonitor: CloudMetadataMonitor
    private let lock = NSLock()
    private var isStarted = false

    public init(
        rootURL: URL,
        changeHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let signal: @Sendable () -> Void = {
            Task { @MainActor in changeHandler() }
        }
        presenter = CloudDocumentPresenter(rootURL: rootURL, changeHandler: signal)
        metadataMonitor = CloudMetadataMonitor(rootURL: rootURL, changeHandler: signal)
    }

    public func start() {
        let shouldStart = lock.withLock {
            guard !isStarted else { return false }
            isStarted = true
            return true
        }
        guard shouldStart else { return }
        NSFileCoordinator.addFilePresenter(presenter)
        metadataMonitor.start()
    }

    public func stop() {
        let shouldStop = lock.withLock {
            guard isStarted else { return false }
            isStarted = false
            return true
        }
        guard shouldStop else { return }
        metadataMonitor.stop()
        NSFileCoordinator.removeFilePresenter(presenter)
    }

    deinit { stop() }
}
