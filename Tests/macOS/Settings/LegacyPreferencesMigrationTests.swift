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
import XCTest

final class LegacyPreferencesMigrationTests: XCTestCase {
    private let spiralDomain = "farm.poplar.spiral"

    func testExistingSpiralPreferencesSuppressLegacyImportOffer() {
        let spiralPreferences: [String: Any] = ["DirectoryAlias": Data([1, 2, 3])]
        let store = InMemoryPreferencesDomainStore(domains: [
            spiralDomain: spiralPreferences,
            LegacyPreferencesSource.notationalVelocity.rawValue: ["Source": "Notational Velocity"],
            LegacyPreferencesSource.nvALT.rawValue: ["Source": "nvALT"]
        ])

        let result = LegacyPreferencesDetector(spiralDomain: spiralDomain).detect(using: store)

        XCTAssertEqual(result.startupState, .existingSpiralPreferences)
        XCTAssertNil(result.detectedSource)
        XCTAssertEqual(store.stringValue(forKey: "DirectoryAlias", in: spiralDomain), nil)
        XCTAssertEqual(store.dataValue(forKey: "DirectoryAlias", in: spiralDomain), Data([1, 2, 3]))
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertEqual(
            result.consoleLogMessage(spiralDomain: spiralDomain),
            "Spiral preferences: loaded existing preferences from domain farm.poplar.spiral."
        )
    }

    func testNotationalVelocityPreferencesTriggerNotesImportOfferWithoutBeingCopied() {
        let legacyPreferences: [String: Any] = [
            "DirectoryAlias": Data([4, 5, 6]),
            "HorizontalLayout": true
        ]
        let store = InMemoryPreferencesDomainStore(domains: [
            LegacyPreferencesSource.notationalVelocity.rawValue: legacyPreferences
        ])

        let result = LegacyPreferencesDetector(spiralDomain: spiralDomain).detect(using: store)

        XCTAssertEqual(result.startupState, .legacyPreferencesFound)
        XCTAssertEqual(result.detectedSource, .notationalVelocity)
        XCTAssertNil(store.persistentDomain(forName: spiralDomain))
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertEqual(
            result.consoleLogMessage(spiralDomain: spiralDomain),
            "Spiral preferences: found legacy preferences in domain net.notational.velocity; the user will be offered a notes import."
        )
    }

    func testNvALTPreferencesTriggerOfferWhenNotationalVelocityIsAbsent() {
        let store = InMemoryPreferencesDomainStore(domains: [
            LegacyPreferencesSource.nvALT.rawValue: ["Source": "nvALT"]
        ])

        let result = LegacyPreferencesDetector(spiralDomain: spiralDomain).detect(using: store)

        XCTAssertEqual(result.startupState, .legacyPreferencesFound)
        XCTAssertEqual(result.detectedSource, .nvALT)
        XCTAssertNil(store.persistentDomain(forName: spiralDomain))
    }

    func testNotationalVelocityIsPreferredWhenBothLegacyDomainsExist() {
        let store = InMemoryPreferencesDomainStore(domains: [
            LegacyPreferencesSource.notationalVelocity.rawValue: ["Source": "Notational Velocity"],
            LegacyPreferencesSource.nvALT.rawValue: ["Source": "nvALT"]
        ])

        let result = LegacyPreferencesDetector(spiralDomain: spiralDomain).detect(using: store)

        XCTAssertEqual(result.detectedSource, .notationalVelocity)
        XCTAssertNil(store.persistentDomain(forName: spiralDomain))
        XCTAssertEqual(store.writeCount, 0)
    }

    func testNoPreferencesProducesFreshInstallWithoutWriting() {
        let store = InMemoryPreferencesDomainStore()

        let result = LegacyPreferencesDetector(spiralDomain: spiralDomain).detect(using: store)

        XCTAssertEqual(result.startupState, .freshInstall)
        XCTAssertNil(result.detectedSource)
        XCTAssertNil(store.persistentDomain(forName: spiralDomain))
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertEqual(
            result.consoleLogMessage(spiralDomain: spiralDomain),
            "Spiral preferences: no persistent Spiral or legacy preferences found; using registered defaults for domain farm.poplar.spiral."
        )
    }
}

private final class InMemoryPreferencesDomainStore: PreferencesDomainStoring {
    private var domains: [String: [String: Any]]
    private(set) var writeCount = 0

    init(domains: [String: [String: Any]] = [:]) {
        self.domains = domains
    }

    func persistentDomain(forName domainName: String) -> [String: Any]? {
        domains[domainName]
    }

    func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        domains[domainName] = domain
        writeCount += 1
    }

    func stringValue(forKey key: String, in domain: String) -> String? {
        domains[domain]?[key] as? String
    }

    func dataValue(forKey key: String, in domain: String) -> Data? {
        domains[domain]?[key] as? Data
    }

    func boolValue(forKey key: String, in domain: String) -> Bool? {
        domains[domain]?[key] as? Bool
    }
}
