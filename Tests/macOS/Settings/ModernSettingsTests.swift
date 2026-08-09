import Foundation
import AppKit
import XCTest

final class ModernSettingsTests: XCTestCase {
    func testLegacyPreferencePaneNamesMapToModernSidebar() {
        XCTAssertEqual(SettingsPane(legacyValue: "General"), .general)
        XCTAssertEqual(SettingsPane(legacyValue: "Notes"), .notes)
        XCTAssertEqual(SettingsPane(legacyValue: "Editing"), .editing)
        XCTAssertEqual(SettingsPane(legacyValue: "Fonts & Colors"), .appearance)
    }

    func testUnknownPreferencePaneFallsBackToGeneral() {
        XCTAssertEqual(SettingsPane(legacyValue: nil), .general)
        XCTAssertEqual(SettingsPane(legacyValue: "Removed Pane"), .general)
        XCTAssertEqual(SettingsPane(legacyValue: "Sync"), .general)
    }

    func testSettingsSidebarDoesNotExposeRetiredSyncIntegration() {
        XCTAssertEqual(SettingsPane.allCases, [.general, .notes, .editing, .appearance])
    }

    func testLegacyPreferencesNibsDoNotRetainRetiredSyncActions() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resourceRoot = repositoryRoot
            .appendingPathComponent("Apps/macOS/Resources")
        let localizations = ["en", "de", "fr", "it", "pt", "Spanish", "zh_CN"]
        let retiredSelectors = [
            "visitSimplenoteSite:",
            "syncFrequencyChange:",
            "toggledSyncing:"
        ]

        for localization in localizations {
            let nibURL = resourceRoot
                .appendingPathComponent("\(localization).lproj")
                .appendingPathComponent("NotationPrefsView.nib")
            let designableContents = try String(
                contentsOf: nibURL.appendingPathComponent("designable.nib"),
                encoding: .utf8
            )
            let keyedData = try Data(contentsOf: nibURL.appendingPathComponent("keyedobjects.nib"))
            let keyedArchive = try PropertyListSerialization.propertyList(from: keyedData, format: nil)

            for selector in retiredSelectors {
                XCTAssertFalse(
                    designableContents.contains(selector),
                    "\(localization) designable nib still contains \(selector)"
                )
                XCTAssertFalse(
                    propertyList(keyedArchive, contains: selector),
                    "\(localization) runtime nib still contains \(selector)"
                )
            }
        }
    }

    func testStorageFormatIdentifiersRemainCompatibleWithNotationPrefs() {
        XCTAssertEqual(StorageFormat.supported.map(\.id), [0, 1, 2, 3])
    }

    func testICloudContainerConfigurationMatchesEntitlements() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let supportingFiles = repositoryRoot.appendingPathComponent("Apps/macOS/SupportingFiles")
        let info = try propertyListDictionary(at: supportingFiles.appendingPathComponent("Info.plist"))
        let entitlements = try propertyListDictionary(at: supportingFiles.appendingPathComponent("Spiral.entitlements"))

        let identifier = try XCTUnwrap(info["SpiralICloudContainerIdentifier"] as? String)
        let containers = try XCTUnwrap(info["NSUbiquitousContainers"] as? [String: Any])
        let cloudContainers = try XCTUnwrap(entitlements["com.apple.developer.icloud-container-identifiers"] as? [String])
        let ubiquityContainers = try XCTUnwrap(entitlements["com.apple.developer.ubiquity-container-identifiers"] as? [String])

        XCTAssertEqual(identifier, "$(SPIRAL_ICLOUD_CONTAINER_IDENTIFIER)")
        let releaseIdentifier = "iCloud.farm.poplar.spiral"
        XCTAssertNotNil(containers[releaseIdentifier])
        XCTAssertTrue(cloudContainers.contains(releaseIdentifier))
        XCTAssertTrue(ubiquityContainers.contains(releaseIdentifier))
        XCTAssertEqual(
            info["SpiralDefaultNotesDirectoryName"] as? String,
            "$(SPIRAL_DEFAULT_NOTES_DIRECTORY_NAME)"
        )
        XCTAssertEqual(
            info["SpiralDefaultNotesParentDirectory"] as? String,
            "$(SPIRAL_DEFAULT_NOTES_PARENT_DIRECTORY)"
        )
        XCTAssertEqual(info["SpiralWindowTitle"] as? String, "$(SPIRAL_WINDOW_TITLE)")
    }

    func testDebugAndReleaseKeepPreferencesAndDefaultNotesSeparate() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Notation.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let sharedConfiguration = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Config/Xcode/Spiral.xcconfig"),
            encoding: .utf8
        )
        let debugStart = try XCTUnwrap(project.range(of: "212B842409780B5000F3597F /* Debug */ = {"))
        let releaseStart = try XCTUnwrap(project.range(of: "212B842509780B5000F3597F /* Release */ = {"))
        let projectSettingsStart = try XCTUnwrap(project.range(of: "212B842809780B5000F3597F /* Debug */ = {"))
        let debugSettings = project[debugStart.lowerBound..<releaseStart.lowerBound]
        let releaseSettings = project[releaseStart.lowerBound..<projectSettingsStart.lowerBound]

        XCTAssertTrue(debugSettings.contains("PRODUCT_BUNDLE_IDENTIFIER = farm.poplar.spiral.debug;"))
        XCTAssertTrue(debugSettings.contains("PRODUCT_NAME = SpiralDebug;"))
        XCTAssertTrue(debugSettings.contains("SPIRAL_DEFAULT_NOTES_DIRECTORY_NAME = \"Spiral Debug Notes\";"))
        XCTAssertTrue(debugSettings.contains("SPIRAL_DEFAULT_NOTES_PARENT_DIRECTORY = Documents;"))
        XCTAssertTrue(debugSettings.contains("SPIRAL_ICLOUD_CONTAINER_IDENTIFIER = \"\";"))
        XCTAssertTrue(debugSettings.contains("SPIRAL_WINDOW_TITLE = \"Spiral (Debug)\";"))
        XCTAssertTrue(debugSettings.contains("SWIFT_OBJC_INTERFACE_HEADER_NAME = \"Spiral-Swift.h\";"))
        XCTAssertTrue(releaseSettings.contains("PRODUCT_BUNDLE_IDENTIFIER = farm.poplar.spiral;"))
        XCTAssertTrue(releaseSettings.contains("PRODUCT_NAME = Spiral;"))
        XCTAssertTrue(releaseSettings.contains("SPIRAL_DEFAULT_NOTES_DIRECTORY_NAME = \"Spiral Notes\";"))
        XCTAssertTrue(releaseSettings.contains("SPIRAL_DEFAULT_NOTES_PARENT_DIRECTORY = Documents;"))
        XCTAssertTrue(releaseSettings.contains("SPIRAL_ICLOUD_CONTAINER_IDENTIFIER = iCloud.farm.poplar.spiral;"))
        XCTAssertTrue(releaseSettings.contains("SPIRAL_WINDOW_TITLE = Spiral;"))
        XCTAssertFalse(project.contains("name = Development;"))
        XCTAssertFalse(project.contains("name = Deployment;"))
        XCTAssertFalse(project.contains("name = Default;"))
        XCTAssertFalse(project.contains("DEVELOPMENT_TEAM ="))
        XCTAssertTrue(sharedConfiguration.contains("#include? \"Local.xcconfig\""))
    }

    @MainActor
    func testNotesFolderUsesReadOnlyStandardPathControl() {
        let url = URL(fileURLWithPath: "/Users/example/Documents/Spiral Notes", isDirectory: true)
        let control = NotesFolderPathControl.makePathControl(url: url)

        XCTAssertEqual(control.url, url)
        XCTAssertEqual(control.pathStyle, .standard)
        XCTAssertFalse(control.isEditable)
        XCTAssertEqual(control.toolTip, url.path)
        XCTAssertEqual(control.accessibilityIdentifier(), "settings.notes.folderPath")
        XCTAssertEqual(control.accessibilityValue() as? String, url.path)
    }

    @MainActor
    func testConsecutiveApplicationModalWindowsReturnIndependentResponses() {
        let expectedResponses = [
            NSApplication.ModalResponse(rawValue: 2101),
            NSApplication.ModalResponse(rawValue: 2102)
        ]

        for expectedResponse in expectedResponses {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            DispatchQueue.main.async {
                NSApp.stopModal(withCode: expectedResponse)
            }

            XCTAssertEqual(ApplicationModalWindowRunner.run(window), expectedResponse)
            XCTAssertFalse(window.isVisible)
        }
    }

    @MainActor
    func testApplicationSheetUsesParentWindowAndReturnsResponse() {
        let parentWindow = SheetPresentingWindowSpy()
        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.isReleasedWhenClosed = false
        let expectedResponse = NSApplication.ModalResponse(rawValue: 2201)
        var receivedResponse: NSApplication.ModalResponse?

        ApplicationSheetWindowPresenter.begin(sheetWindow, for: parentWindow) { response in
            receivedResponse = response
        }
        XCTAssertEqual(parentWindow.presentedSheet, sheetWindow)

        parentWindow.completeSheet(with: expectedResponse)

        XCTAssertEqual(receivedResponse, expectedResponse)
        XCTAssertNil(parentWindow.presentedSheet)
        XCTAssertFalse(sheetWindow.isVisible)
    }

    @MainActor
    func testICloudProgressWindowIsButtonlessAndPreservesItsMessage() throws {
        let title = "Connecting to iCloud Drive…"
        let message = NotesMigrationProgressText.connectingToICloud
        let panel = MigrationProgressWindow.make(title: title, informativeText: message)
        defer { panel.close() }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let views = allSubviews(of: contentView)
        let titleLabel = try XCTUnwrap(
            views.first { $0.accessibilityIdentifier() == "icloudMigration.progressTitle" }
                as? NSTextField
        )
        let messageLabel = try XCTUnwrap(
            views.first { $0.accessibilityIdentifier() == "icloudMigration.progressMessage" }
                as? NSTextField
        )

        XCTAssertTrue(views.compactMap { $0 as? NSButton }.isEmpty)
        XCTAssertNotNil(views.first { $0 is NSProgressIndicator })
        XCTAssertEqual(titleLabel.stringValue, title)
        XCTAssertEqual(messageLabel.stringValue, message)
        XCTAssertEqual(titleLabel.maximumNumberOfLines, 0)
        XCTAssertEqual(messageLabel.maximumNumberOfLines, 0)
        XCTAssertFalse(panel.styleMask.contains(.closable))
        XCTAssertFalse(panel.isReleasedWhenClosed)
    }

    private func propertyList(_ value: Any, contains target: String) -> Bool {
        if let string = value as? String {
            return string == target
        }
        if let array = value as? [Any] {
            return array.contains { propertyList($0, contains: target) }
        }
        if let dictionary = value as? [AnyHashable: Any] {
            return dictionary.contains {
                propertyList($0.key, contains: target) || propertyList($0.value, contains: target)
            }
        }
        return false
    }

    private func propertyListDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }
}

@MainActor
private final class SheetPresentingWindowSpy: NSWindow {
    private var sheetCompletion: ((NSApplication.ModalResponse) -> Void)?
    private(set) var presentedSheet: NSWindow?

    override func beginSheet(
        _ sheetWindow: NSWindow,
        completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil
    ) {
        presentedSheet = sheetWindow
        sheetCompletion = handler
    }

    func completeSheet(with response: NSApplication.ModalResponse) {
        presentedSheet = nil
        let completion = sheetCompletion
        sheetCompletion = nil
        completion?(response)
    }
}
