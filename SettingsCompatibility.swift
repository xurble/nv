import Foundation

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case notes
    case editing
    case appearance
    case sync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .notes: return String(localized: "Notes")
        case .editing: return String(localized: "Editing")
        case .appearance: return String(localized: "Appearance")
        case .sync: return String(localized: "Sync")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .notes: return "doc.text"
        case .editing: return "pencil.and.outline"
        case .appearance: return "paintpalette"
        case .sync: return "arrow.triangle.2.circlepath"
        }
    }

    init(legacyValue: String?) {
        switch legacyValue?.lowercased() {
        case "notes": self = .notes
        case "editing": self = .editing
        case "fonts & colors", "appearance": self = .appearance
        case "sync": self = .sync
        default: self = .general
        }
    }
}

struct StorageFormat: Identifiable {
    let id: Int
    let title: String
    let detail: String

    static let supported = [
        StorageFormat(id: 0, title: String(localized: "Single Database"), detail: String(localized: "Required for encrypted notes")),
        StorageFormat(id: 1, title: String(localized: "Plain Text Files"), detail: String(localized: "One .txt file per note")),
        StorageFormat(id: 2, title: String(localized: "Rich Text Files"), detail: String(localized: "One .rtf file per note")),
        StorageFormat(id: 3, title: String(localized: "HTML Files"), detail: String(localized: "One .html file per note"))
    ]
}
