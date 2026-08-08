import Foundation

struct AboutInformation: Equatable {
    static let credits = [
        "Copyright © 2011 Zachary Schneirov",
        "Copyright © 2026 Gareth Simpson"
    ]

    let applicationName: String
    let version: String
    let build: String

    init(infoDictionary: [String: Any]) {
        applicationName = Self.firstNonemptyString(
            in: infoDictionary,
            keys: ["CFBundleDisplayName", "CFBundleName", "CFBundleExecutable"]
        ) ?? "Spiral"
        version = Self.firstNonemptyString(
            in: infoDictionary,
            keys: ["CFBundleShortVersionString"]
        ) ?? ""
        build = Self.firstNonemptyString(
            in: infoDictionary,
            keys: ["CFBundleVersion"]
        ) ?? ""
    }

    var versionDescription: String {
        switch (version.isEmpty, build.isEmpty) {
        case (false, false):
            return "Version \(version) (\(build))"
        case (false, true):
            return "Version \(version)"
        case (true, false):
            return "Build \(build)"
        case (true, true):
            return ""
        }
    }

    private static func firstNonemptyString(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
