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

    func testStorageFormatIdentifiersRemainCompatibleWithNotationPrefs() {
        XCTAssertEqual(StorageFormat.supported.map(\.id), [0, 1, 2, 3])
    }
}
