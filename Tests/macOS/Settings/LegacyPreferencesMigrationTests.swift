import Foundation
import XCTest

final class LegacyPreferencesMigrationTests: XCTestCase {
    private let spiralDomain = "farm.poplar.spiral"

    func testExistingSpiralPreferencesAlwaysWin() {
        let spiralPreferences: [String: Any] = ["DirectoryAlias": Data([1, 2, 3])]
        let store = InMemoryPreferencesDomainStore(domains: [
            spiralDomain: spiralPreferences,
            LegacyPreferencesSource.notationalVelocity.rawValue: ["Source": "Notational Velocity"],
            LegacyPreferencesSource.nvALT.rawValue: ["Source": "nvALT"]
        ])

        let result = LegacyPreferencesMigrator(spiralDomain: spiralDomain).migrate(using: store) { _ in
            XCTFail("Existing Spiral preferences must not prompt for a legacy import")
            return false
        }

        XCTAssertEqual(result.startupState, .existingSpiralPreferences)
        XCTAssertNil(result.importedSource)
        XCTAssertNil(result.declinedSource)
        XCTAssertEqual(store.stringValue(forKey: "DirectoryAlias", in: spiralDomain), nil)
        XCTAssertEqual(store.dataValue(forKey: "DirectoryAlias", in: spiralDomain), Data([1, 2, 3]))
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertEqual(
            result.consoleLogMessage(spiralDomain: spiralDomain),
            "Spiral preferences: loaded existing preferences from domain farm.poplar.spiral."
        )
    }

    func testNotationalVelocityPreferencesAreCopiedToSpiral() {
        let legacyPreferences: [String: Any] = [
            "DirectoryAlias": Data([4, 5, 6]),
            "HorizontalLayout": true
        ]
        let store = InMemoryPreferencesDomainStore(domains: [
            LegacyPreferencesSource.notationalVelocity.rawValue: legacyPreferences
        ])

        var offeredSource: LegacyPreferencesSource?
        let result = LegacyPreferencesMigrator(spiralDomain: spiralDomain).migrate(using: store) { source in
            offeredSource = source
            return true
        }

        XCTAssertEqual(result.startupState, .importedLegacyPreferences)
        XCTAssertEqual(result.importedSource, .notationalVelocity)
        XCTAssertNil(result.declinedSource)
        XCTAssertEqual(offeredSource, .notationalVelocity)
        XCTAssertEqual(store.dataValue(forKey: "DirectoryAlias", in: spiralDomain), Data([4, 5, 6]))
        XCTAssertEqual(store.boolValue(forKey: "HorizontalLayout", in: spiralDomain), true)
        XCTAssertEqual(store.writeCount, 1)
        XCTAssertEqual(
            result.consoleLogMessage(spiralDomain: spiralDomain),
            "Spiral preferences: loaded legacy preferences from domain net.notational.velocity and saved them to domain farm.poplar.spiral."
        )
    }

    func testNvALTPreferencesAreCopiedWhenNotationalVelocityIsAbsent() {
        let store = InMemoryPreferencesDomainStore(domains: [
            LegacyPreferencesSource.nvALT.rawValue: ["Source": "nvALT"]
        ])

        let result = LegacyPreferencesMigrator(spiralDomain: spiralDomain).migrate(using: store)

        XCTAssertEqual(result.startupState, .importedLegacyPreferences)
        XCTAssertEqual(result.importedSource, .nvALT)
        XCTAssertEqual(store.stringValue(forKey: "Source", in: spiralDomain), "nvALT")
    }

    func testNotationalVelocityIsPreferredWhenBothLegacyDomainsExist() {
        let store = InMemoryPreferencesDomainStore(domains: [
            LegacyPreferencesSource.notationalVelocity.rawValue: ["Source": "Notational Velocity"],
            LegacyPreferencesSource.nvALT.rawValue: ["Source": "nvALT"]
        ])

        let result = LegacyPreferencesMigrator(spiralDomain: spiralDomain).migrate(using: store)

        XCTAssertEqual(result.importedSource, .notationalVelocity)
        XCTAssertEqual(store.stringValue(forKey: "Source", in: spiralDomain), "Notational Velocity")
        XCTAssertEqual(store.writeCount, 1)
    }

    func testDecliningNotationalVelocityUsesDefaultsWithoutTryingNvALT() {
        let store = InMemoryPreferencesDomainStore(domains: [
            LegacyPreferencesSource.notationalVelocity.rawValue: ["Source": "Notational Velocity"],
            LegacyPreferencesSource.nvALT.rawValue: ["Source": "nvALT"]
        ])
        var offeredSources: [LegacyPreferencesSource] = []

        let result = LegacyPreferencesMigrator(spiralDomain: spiralDomain).migrate(using: store) { source in
            offeredSources.append(source)
            return false
        }

        XCTAssertEqual(offeredSources, [.notationalVelocity])
        XCTAssertEqual(result.startupState, .freshInstall)
        XCTAssertNil(result.importedSource)
        XCTAssertEqual(result.declinedSource, .notationalVelocity)
        XCTAssertNil(store.persistentDomain(forName: spiralDomain))
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertEqual(
            result.consoleLogMessage(spiralDomain: spiralDomain),
            "Spiral preferences: found legacy preferences in domain net.notational.velocity, but import was declined; using registered defaults for domain farm.poplar.spiral."
        )
    }

    func testNoPreferencesProducesFreshInstallWithoutWriting() {
        let store = InMemoryPreferencesDomainStore()

        let result = LegacyPreferencesMigrator(spiralDomain: spiralDomain).migrate(using: store)

        XCTAssertEqual(result.startupState, .freshInstall)
        XCTAssertNil(result.importedSource)
        XCTAssertNil(result.declinedSource)
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
