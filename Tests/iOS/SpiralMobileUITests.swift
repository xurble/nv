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
