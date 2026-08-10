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
