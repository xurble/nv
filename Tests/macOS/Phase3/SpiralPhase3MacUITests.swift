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

import XCTest

final class SpiralPhase3MacUITests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SpiralPhase3MacUITests-\(UUID().uuidString)", isDirectory: true)
        let documents = rootURL.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data("Spiral mobile fixture collection".utf8).write(to: documents.appendingPathComponent("Welcome.txt"))
        for index in 1...120 {
            try Data("Body for fixture note \(index)".utf8)
                .write(to: documents.appendingPathComponent("Fixture Note \(index).txt"))
        }
    }

    func testKeyboardFirstCreateSearchAndEditWithLegacyEditor() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 8))

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["note.title"].waitForExistence(timeout: 3))
        app.textFields["note.title"].click()
        app.typeText("Mac Keyboard Note")
        app.typeKey(.return, modifierFlags: [])

        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.label, "Note body")
        editor.click()
        app.typeText("Edited by the LinkingEditor bridge")

        app.typeKey("f", modifierFlags: .command)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("Welcome")
        XCTAssertTrue(app.staticTexts["Welcome"].exists)
    }

    func testLargeCollectionResizesAndExposesAccessibleCommands() {
        let app = launch()
        XCTAssertTrue(app.buttons["command.new"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["command.pin"].exists)
        XCTAssertTrue(app.buttons["command.delete"].exists)
        XCTAssertTrue(app.buttons["command.settings"].exists)

        app.windows.firstMatch.buttons[XCUIIdentifierZoomWindow].click()
        XCTAssertTrue(app.staticTexts["Fixture Note 120"].exists || app.staticTexts["Fixture Note 1"].exists)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SPIRAL_PHASE3_UI_TEST_MODE"] = "1"
        app.launchEnvironment["SPIRAL_PHASE3_DOCUMENTS"] = rootURL.appendingPathComponent("Documents").path
        app.launchEnvironment["SPIRAL_PHASE3_RECONCILIATION"] = rootURL.appendingPathComponent("Reconciliation").path
        app.launchEnvironment["SPIRAL_PHASE3_INDEX"] = rootURL.appendingPathComponent("Index/notes.json").path
        app.launch()
        return app
    }
}
