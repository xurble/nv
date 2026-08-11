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
    along with Spiral.  If not, see <http://www.gnu.org/licenses/>. */

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
