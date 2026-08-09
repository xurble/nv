import Foundation

@objc enum SpiralPreferencesStartupState: Int {
    case existingSpiralPreferences
    case legacyPreferencesFound
    case freshInstall
}

enum LegacyPreferencesSource: String, Equatable {
    case notationalVelocity = "net.notational.velocity"
    case nvALT = "net.elasticthreads.nv"

    var displayName: String {
        switch self {
        case .notationalVelocity:
            return "Notational Velocity"
        case .nvALT:
            return "nvALT"
        }
    }
}

struct SpiralPreferencesDetectionResult: Equatable {
    let startupState: SpiralPreferencesStartupState
    let detectedSource: LegacyPreferencesSource?

    func consoleLogMessage(spiralDomain: String) -> String {
        switch startupState {
        case .existingSpiralPreferences:
            return "Spiral preferences: loaded existing preferences from domain \(spiralDomain)."

        case .legacyPreferencesFound:
            let sourceDomain = detectedSource?.rawValue ?? "an unknown legacy domain"
            return "Spiral preferences: found legacy preferences in domain \(sourceDomain); the user will be offered a notes import."

        case .freshInstall:
            return "Spiral preferences: no persistent Spiral or legacy preferences found; using registered defaults for domain \(spiralDomain)."
        }
    }
}

protocol PreferencesDomainStoring: AnyObject {
    func persistentDomain(forName domainName: String) -> [String: Any]?
}

extension UserDefaults: PreferencesDomainStoring {}

struct LegacyPreferencesDetector {
    let spiralDomain: String

    private let legacyDomains: [LegacyPreferencesSource] = [
        .notationalVelocity,
        .nvALT
    ]

    func detect(using store: PreferencesDomainStoring) -> SpiralPreferencesDetectionResult {
        if store.persistentDomain(forName: spiralDomain) != nil {
            return SpiralPreferencesDetectionResult(
                startupState: .existingSpiralPreferences,
                detectedSource: nil
            )
        }

        for source in legacyDomains {
            guard store.persistentDomain(forName: source.rawValue) != nil else {
                continue
            }
            return SpiralPreferencesDetectionResult(
                startupState: .legacyPreferencesFound,
                detectedSource: source
            )
        }

        return SpiralPreferencesDetectionResult(
            startupState: .freshInstall,
            detectedSource: nil
        )
    }
}

@objc(SpiralPreferencesMigrationController)
final class SpiralPreferencesMigrationController: NSObject {
    @objc private(set) static var startupState = SpiralPreferencesStartupState.freshInstall
    static private(set) var detectedLegacySource: LegacyPreferencesSource?

    @objc static func migrateBeforeApplicationLaunch() {
        guard let spiralDomain = Bundle.main.bundleIdentifier else {
            startupState = .freshInstall
            NSLog("Spiral preferences: bundle identifier unavailable; using registered defaults.")
            return
        }

        let result = LegacyPreferencesDetector(spiralDomain: spiralDomain).detect(
            using: UserDefaults.standard
        )
        startupState = result.startupState
        detectedLegacySource = result.detectedSource
        NSLog("%@", result.consoleLogMessage(spiralDomain: spiralDomain))
    }
}
