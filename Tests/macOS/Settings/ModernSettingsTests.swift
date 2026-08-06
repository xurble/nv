import Foundation
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
}
