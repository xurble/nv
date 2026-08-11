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
