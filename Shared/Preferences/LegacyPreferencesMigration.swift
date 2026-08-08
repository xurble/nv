import Foundation

@objc enum SpiralPreferencesStartupState: Int {
    case existingSpiralPreferences
    case importedLegacyPreferences
    case freshInstall
}

enum LegacyPreferencesSource: String, Equatable {
    case notationalVelocity = "net.notational.velocity"
    case nvALT = "net.elasticthreads.nv"
}

struct SpiralPreferencesMigrationResult: Equatable {
    let startupState: SpiralPreferencesStartupState
    let importedSource: LegacyPreferencesSource?
}

protocol PreferencesDomainStoring: AnyObject {
    func persistentDomain(forName domainName: String) -> [String: Any]?
    func setPersistentDomain(_ domain: [String: Any], forName domainName: String)
}

extension UserDefaults: PreferencesDomainStoring {}

struct LegacyPreferencesMigrator {
    let spiralDomain: String

    private let legacyDomains: [LegacyPreferencesSource] = [
        .notationalVelocity,
        .nvALT
    ]

    func migrate(using store: PreferencesDomainStoring) -> SpiralPreferencesMigrationResult {
        if store.persistentDomain(forName: spiralDomain) != nil {
            return SpiralPreferencesMigrationResult(
                startupState: .existingSpiralPreferences,
                importedSource: nil
            )
        }

        for source in legacyDomains {
            guard let preferences = store.persistentDomain(forName: source.rawValue) else {
                continue
            }
            store.setPersistentDomain(preferences, forName: spiralDomain)
            return SpiralPreferencesMigrationResult(
                startupState: .importedLegacyPreferences,
                importedSource: source
            )
        }

        return SpiralPreferencesMigrationResult(
            startupState: .freshInstall,
            importedSource: nil
        )
    }
}

@objc(SpiralPreferencesMigrationController)
final class SpiralPreferencesMigrationController: NSObject {
    @objc private(set) static var startupState = SpiralPreferencesStartupState.freshInstall

    @objc static func migrateBeforeApplicationLaunch() {
        guard let spiralDomain = Bundle.main.bundleIdentifier else {
            startupState = .freshInstall
            return
        }

        let defaults = UserDefaults.standard
        let result = LegacyPreferencesMigrator(spiralDomain: spiralDomain).migrate(using: defaults)
        startupState = result.startupState

        // The migration precedes all UI so its result survives every choice
        // in the later iCloud migration dialog, including cancellation.
        if result.importedSource != nil {
            defaults.synchronize()
        }
    }
}
