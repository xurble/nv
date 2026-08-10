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
        XCTAssertEqual(StorageFormat.supported.map(\.id), [1, 2, 3])
        XCTAssertFalse(StorageFormat.supported.contains { $0.title.localizedCaseInsensitiveContains("database") })
    }

    func testFreshCollectionsDefaultToPerNoteFilesAndImporterAllowsMixedFamilies() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let preferencesSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Apps/macOS/Sources/NotationPrefs.m"),
            encoding: .utf8
        )
        let importerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Apps/macOS/Sources/SettingsBridge.m"),
            encoding: .utf8
        )

        XCTAssertTrue(preferencesSource.contains("notesStorageFormat = PlainTextFormat;"))
        XCTAssertTrue(preferencesSource.contains("appendFileExtensionToNewNotes = YES;"))
        XCTAssertTrue(preferencesSource.contains("![decoder containsValueForKey:VAR_STR(appendFileExtensionToNewNotes)]"))
        XCTAssertTrue(preferencesSource.contains("@\"md\", @\"markdown\""))
        XCTAssertFalse(importerSource.contains("mixture of note file formats"))
        XCTAssertTrue(importerSource.contains("[formats containsObject:@(PlainTextFormat)]"))
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

    func testDebugAndReleaseSharePreferencesAndDefaultNotesLocation() throws {
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

        XCTAssertTrue(debugSettings.contains("PRODUCT_BUNDLE_IDENTIFIER = farm.poplar.spiral;"))
        XCTAssertTrue(debugSettings.contains("PRODUCT_NAME = Spiral;"))
        XCTAssertTrue(debugSettings.contains("CODE_SIGN_ENTITLEMENTS = Apps/macOS/SupportingFiles/Spiral.entitlements;"))
        XCTAssertTrue(debugSettings.contains("SPIRAL_DEFAULT_NOTES_DIRECTORY_NAME = \"Spiral Notes\";"))
        XCTAssertTrue(debugSettings.contains("SPIRAL_DEFAULT_NOTES_PARENT_DIRECTORY = Documents;"))
        XCTAssertTrue(debugSettings.contains("SPIRAL_ICLOUD_CONTAINER_IDENTIFIER = iCloud.farm.poplar.spiral;"))
        XCTAssertTrue(debugSettings.contains("SPIRAL_WINDOW_TITLE = Spiral;"))
        XCTAssertTrue(debugSettings.contains("SWIFT_OBJC_INTERFACE_HEADER_NAME = \"Spiral-Swift.h\";"))
        XCTAssertTrue(releaseSettings.contains("PRODUCT_BUNDLE_IDENTIFIER = farm.poplar.spiral;"))
        XCTAssertTrue(releaseSettings.contains("PRODUCT_NAME = Spiral;"))
        XCTAssertTrue(releaseSettings.contains("CODE_SIGN_ENTITLEMENTS = Apps/macOS/SupportingFiles/Spiral.entitlements;"))
        XCTAssertTrue(releaseSettings.contains("SPIRAL_DEFAULT_NOTES_DIRECTORY_NAME = \"Spiral Notes\";"))
        XCTAssertTrue(releaseSettings.contains("SPIRAL_DEFAULT_NOTES_PARENT_DIRECTORY = Documents;"))
        XCTAssertTrue(releaseSettings.contains("SPIRAL_ICLOUD_CONTAINER_IDENTIFIER = iCloud.farm.poplar.spiral;"))
        XCTAssertTrue(releaseSettings.contains("SPIRAL_WINDOW_TITLE = Spiral;"))
        XCTAssertFalse(project.contains("SpiralDebug"))
        XCTAssertFalse(project.contains("Spiral-Debug.entitlements"))
        XCTAssertFalse(project.contains("name = Development;"))
        XCTAssertFalse(project.contains("name = Deployment;"))
        XCTAssertFalse(project.contains("name = Default;"))
        XCTAssertFalse(project.contains("DEVELOPMENT_TEAM ="))
        XCTAssertTrue(sharedConfiguration.contains("#include? \"Local.xcconfig\""))
    }

    func testMobileDebugAndReleaseShareProductIdentity() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Notation.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let scheme = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Notation.xcodeproj/xcshareddata/xcschemes/SpiralMobile.xcscheme"
            ),
            encoding: .utf8
        )
        let debugStart = try XCTUnwrap(project.range(of: "F30000000000000000000051 /* Debug */ = {"))
        let releaseStart = try XCTUnwrap(project.range(of: "F30000000000000000000052 /* Release */ = {"))
        let uiTestStart = try XCTUnwrap(project.range(of: "F30000000000000000000056 /* Debug */ = {"))
        let debugSettings = project[debugStart.lowerBound..<releaseStart.lowerBound]
        let releaseSettings = project[releaseStart.lowerBound..<uiTestStart.lowerBound]

        for settings in [debugSettings, releaseSettings] {
            XCTAssertTrue(
                settings.contains(
                    "baseConfigurationReference = B10000000000000000000011 /* Spiral.xcconfig */;"
                )
            )
            XCTAssertTrue(settings.contains("CODE_SIGN_STYLE = Automatic;"))
            XCTAssertFalse(settings.contains("CODE_SIGNING_ALLOWED = NO;"))
            XCTAssertTrue(settings.contains("PRODUCT_BUNDLE_IDENTIFIER = farm.poplar.spiral;"))
            XCTAssertTrue(settings.contains("PRODUCT_NAME = Spiral;"))
        }
        XCTAssertTrue(project.contains("F30000000000000000000012 /* Spiral.app */"))
        XCTAssertFalse(project.contains("PRODUCT_BUNDLE_IDENTIFIER = farm.poplar.spiral.mobile;"))
        XCTAssertFalse(project.contains("PRODUCT_BUNDLE_IDENTIFIER = farm.poplar.spiral.mobile.debug;"))
        XCTAssertFalse(project.contains("SpiralMobile.app"))
        XCTAssertTrue(scheme.contains("BuildableName = \"Spiral.app\""))
        XCTAssertFalse(scheme.contains("BuildableName = \"SpiralMobile.app\""))
    }

    func testMobileBuildsUseSharedSpiralIcon() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Notation.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let debugStart = try XCTUnwrap(project.range(of: "F30000000000000000000051 /* Debug */ = {"))
        let releaseStart = try XCTUnwrap(project.range(of: "F30000000000000000000052 /* Release */ = {"))
        let uiTestStart = try XCTUnwrap(project.range(of: "F30000000000000000000056 /* Debug */ = {"))
        let resourcesStart = try XCTUnwrap(
            project.range(of: "F30000000000000000000023 /* Resources */ = {")
        )
        let nextResourcesStart = try XCTUnwrap(
            project.range(of: "F30000000000000000000027 /* Resources */ = {")
        )
        let debugSettings = project[debugStart.lowerBound..<releaseStart.lowerBound]
        let releaseSettings = project[releaseStart.lowerBound..<uiTestStart.lowerBound]
        let mobileResources = project[resourcesStart.lowerBound..<nextResourcesStart.lowerBound]

        XCTAssertTrue(debugSettings.contains("ASSETCATALOG_COMPILER_APPICON_NAME = spiral;"))
        XCTAssertTrue(releaseSettings.contains("ASSETCATALOG_COMPILER_APPICON_NAME = spiral;"))
        XCTAssertTrue(
            project.contains(
                "A30000000000000000000003 /* spiral.icon in Resources */ = {isa = PBXBuildFile;"
            )
        )
        XCTAssertTrue(
            mobileResources.contains(
                "A30000000000000000000003 /* spiral.icon in Resources */"
            )
        )
    }

    func testNotesSettingsDoNotExposeLocationControls() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Apps/macOS/Sources/ModernSettings.swift"),
            encoding: .utf8
        )
        let launchController = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Apps/macOS/Sources/AppController.m"),
            encoding: .utf8
        )

        XCTAssertFalse(settings.contains("Notes folder"))
        XCTAssertFalse(settings.contains("Choose…"))
        XCTAssertFalse(settings.contains("Use iCloud…"))
        XCTAssertFalse(settings.contains("settings.notes.useICloud"))
        XCTAssertFalse(launchController.contains("getNewNotesRefFromOpenPanel"))
        XCTAssertFalse(launchController.contains("showOpenPanel"))
        XCTAssertTrue(launchController.contains("if (![preparedNotesDirectory isUsable])"))
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
