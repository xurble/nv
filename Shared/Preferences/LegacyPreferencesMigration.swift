import AppKit

@objc enum SpiralPreferencesStartupState: Int {
    case existingSpiralPreferences
    case importedLegacyPreferences
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

struct SpiralPreferencesMigrationResult: Equatable {
    let startupState: SpiralPreferencesStartupState
    let importedSource: LegacyPreferencesSource?
    let declinedSource: LegacyPreferencesSource?

    func consoleLogMessage(spiralDomain: String) -> String {
        switch startupState {
        case .existingSpiralPreferences:
            return "Spiral preferences: loaded existing preferences from domain \(spiralDomain)."

        case .importedLegacyPreferences:
            let sourceDomain = importedSource?.rawValue ?? "an unknown legacy domain"
            return "Spiral preferences: loaded legacy preferences from domain \(sourceDomain) and saved them to domain \(spiralDomain)."

        case .freshInstall:
            if let declinedSource {
                return "Spiral preferences: found legacy preferences in domain \(declinedSource.rawValue), but import was declined; using registered defaults for domain \(spiralDomain)."
            }
            return "Spiral preferences: no persistent Spiral or legacy preferences found; using registered defaults for domain \(spiralDomain)."
        }
    }
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

    func migrate(
        using store: PreferencesDomainStoring,
        shouldImport: (LegacyPreferencesSource) -> Bool = { _ in true }
    ) -> SpiralPreferencesMigrationResult {
        if store.persistentDomain(forName: spiralDomain) != nil {
            return SpiralPreferencesMigrationResult(
                startupState: .existingSpiralPreferences,
                importedSource: nil,
                declinedSource: nil
            )
        }

        for source in legacyDomains {
            guard let preferences = store.persistentDomain(forName: source.rawValue) else {
                continue
            }
            guard shouldImport(source) else {
                return SpiralPreferencesMigrationResult(
                    startupState: .freshInstall,
                    importedSource: nil,
                    declinedSource: source
                )
            }
            store.setPersistentDomain(preferences, forName: spiralDomain)
            return SpiralPreferencesMigrationResult(
                startupState: .importedLegacyPreferences,
                importedSource: source,
                declinedSource: nil
            )
        }

        return SpiralPreferencesMigrationResult(
            startupState: .freshInstall,
            importedSource: nil,
            declinedSource: nil
        )
    }
}

@objc(SpiralPreferencesMigrationController)
final class SpiralPreferencesMigrationController: NSObject {
    @objc private(set) static var startupState = SpiralPreferencesStartupState.freshInstall

    @objc static func migrateBeforeApplicationLaunch() {
        guard let spiralDomain = Bundle.main.bundleIdentifier else {
            startupState = .freshInstall
            NSLog("Spiral preferences: bundle identifier unavailable; using registered defaults.")
            return
        }

        let defaults = UserDefaults.standard
        let result = LegacyPreferencesMigrator(spiralDomain: spiralDomain).migrate(
            using: defaults,
            shouldImport: confirmLegacyPreferencesImport
        )
        startupState = result.startupState
        NSLog("%@", result.consoleLogMessage(spiralDomain: spiralDomain))

        // The migration precedes all UI so its result survives every choice
        // in the later iCloud migration dialog, including cancellation.
        if result.importedSource != nil {
            defaults.synchronize()
        }
    }

    private static func confirmLegacyPreferencesImport(
        from source: LegacyPreferencesSource
    ) -> Bool {
        _ = NSApplication.shared

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Import \(source.displayName) settings?"
        alert.informativeText = "Spiral found existing \(source.displayName) preferences. Import them into Spiral? The original preferences will not be changed."
        alert.addButton(withTitle: "Import Settings")
        let defaultsButton = alert.addButton(withTitle: "Use Spiral Defaults")
        defaultsButton.keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
