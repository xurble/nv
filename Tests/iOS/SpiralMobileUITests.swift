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

final class SpiralMobileUITests: XCTestCase {
    private var collectionID: String!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        collectionID = UUID().uuidString
    }

    func testCompactCreateSearchEditAndStateRestoration() {
        let app = launch()
        XCTAssertTrue(app.buttons["command.new"].waitForExistence(timeout: 12))

        app.buttons["command.new"].tap()
        XCTAssertTrue(app.textFields["note.title"].waitForExistence(timeout: 3))
        let title = app.textFields["note.title"]
        title.tap()
        app.typeKey("a", modifierFlags: .command)
        title.typeText("Compact Workflow\n")
        XCTAssertTrue(app.navigationBars["Compact Workflow"].waitForExistence(timeout: 5))

        app.terminate()
        let restored = launch()
        XCTAssertTrue(restored.textFields["note.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(restored.textFields["note.title"].value as? String, "Compact Workflow")
    }

    func testAdaptiveLargeCollectionAndSettingsAreAccessible() {
        let app = launch()
        XCTAssertTrue(app.textFields["note.title"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["command.settings"].waitForExistence(timeout: 3))

        if app.buttons["BackButton"].exists {
            app.buttons["BackButton"].tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["note.list"].waitForExistence(timeout: 3))
        XCTAssertGreaterThan(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Fixture Note'")).count, 0)

        app.buttons["command.settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["Show note previews"].exists)
    }

    func testKeyboardDynamicTypeAndVoiceOverSemantics() {
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }

        let app = launch(dynamicType: true)
        XCTAssertTrue(app.textFields["note.title"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.textViews["note.editor"].label, "Note body")

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["note.title"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["command.settings"].isHittable)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.textViews["note.editor"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textViews["note.editor"].label, "Note body")
    }

    private func launch(dynamicType: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SPIRAL_UI_TEST_MODE"] = "1"
        app.launchEnvironment["SPIRAL_UI_TEST_COLLECTION_ID"] = collectionID
        if dynamicType {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
            ]
        }
        app.launch()
        return app
    }
}
