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

import SpiralCore
import SpiralFeature
import SwiftUI

@main
struct SpiralMobileApp: App {
    private let store: LocalNoteStore
    private let documentsURL: URL
    @StateObject private var model: SpiralFeatureModel
    @State private var prepared = false

    init() {
        let root = Self.collectionRoot()
        let documentsURL = root.appendingPathComponent("Documents", isDirectory: true)
        let store = LocalNoteStore(
            documentsURL: documentsURL,
            reconciliationURL: root.appendingPathComponent("Reconciliation", isDirectory: true),
            indexURL: root.appendingPathComponent("Index/notes.json", isDirectory: false)
        )
        self.store = store
        self.documentsURL = documentsURL
        _model = StateObject(wrappedValue: SpiralFeatureModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if prepared {
                    SpiralCollectionView(model: model)
                } else {
                    ProgressView("Opening collection…")
                        .accessibilityIdentifier("app.preparing")
                }
            }
            .task { await prepare() }
        }
    }

    @MainActor
    private func prepare() async {
        guard !prepared else { return }
        do {
            if ProcessInfo.processInfo.environment["SPIRAL_UI_TEST_MODE"] == "1" {
                try seedUITestFilesIfNeeded()
            }
            try await store.reloadFromDisk()
            prepared = true
        } catch {
            prepared = true
            model.setAvailability(.unavailable(message: String(describing: error)))
        }
    }

    private func seedUITestFilesIfNeeded() throws {
        try FileManager.default.createDirectory(
            at: documentsURL,
            withIntermediateDirectories: true
        )
        let welcomeURL = documentsURL.appendingPathComponent("Welcome.txt")
        guard !FileManager.default.fileExists(atPath: welcomeURL.path) else { return }
        try Data("Spiral mobile fixture collection".utf8).write(to: welcomeURL)
        for index in 1...120 {
            try Data("Body for fixture note \(index)".utf8).write(
                to: documentsURL.appendingPathComponent("Fixture Note \(index).txt")
            )
        }
    }

    private static func collectionRoot() -> URL {
        let environment = ProcessInfo.processInfo.environment
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        if environment["SPIRAL_UI_TEST_MODE"] == "1",
           let collectionID = environment["SPIRAL_UI_TEST_COLLECTION_ID"],
           UUID(uuidString: collectionID) != nil {
            return applicationSupport
                .appendingPathComponent("Spiral/Phase3UITests", isDirectory: true)
                .appendingPathComponent(collectionID, isDirectory: true)
        }
        return applicationSupport.appendingPathComponent("Spiral/Phase3Local", isDirectory: true)
    }
}
