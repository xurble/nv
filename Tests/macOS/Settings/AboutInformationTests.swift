import XCTest

final class AboutInformationTests: XCTestCase {
    func testCreditsPreserveOriginalAuthorBeforeCurrentMaintainer() {
        XCTAssertEqual(
            AboutInformation.credits,
            [
                "Copyright © 2011 Zachary Schneirov",
                "Copyright © 2026 Gareth Simpson"
            ]
        )
    }

    func testVersionDescriptionIncludesVersionAndBuild() {
        let information = AboutInformation(infoDictionary: [
            "CFBundleDisplayName": "Spiral",
            "CFBundleShortVersionString": "2.0",
            "CFBundleVersion": "10"
        ])

        XCTAssertEqual(information.applicationName, "Spiral")
        XCTAssertEqual(information.versionDescription, "Version 2.0 (10)")
    }

    func testMissingBundleValuesUseSafeFallbacks() {
        let information = AboutInformation(infoDictionary: [:])

        XCTAssertEqual(information.applicationName, "Spiral")
        XCTAssertEqual(information.versionDescription, "")
    }
}
