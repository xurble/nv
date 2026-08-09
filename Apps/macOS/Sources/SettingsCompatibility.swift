import AppKit

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case notes
    case editing
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .notes: return String(localized: "Notes")
        case .editing: return String(localized: "Editing")
        case .appearance: return String(localized: "Appearance")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .notes: return "doc.text"
        case .editing: return "pencil.and.outline"
        case .appearance: return "paintpalette"
        }
    }

    init(legacyValue: String?) {
        switch legacyValue?.lowercased() {
        case "notes": self = .notes
        case "editing": self = .editing
        case "fonts & colors", "appearance": self = .appearance
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

enum MigrationChoiceModalResponse {
    private static let keepCurrentLocation = NSApplication.ModalResponse(rawValue: 2001)
    private static let copyToICloud = NSApplication.ModalResponse(rawValue: 2002)

    static func response(for choice: NotesMigrationChoice) -> NSApplication.ModalResponse {
        switch choice {
        case .keepCurrentLocation: return keepCurrentLocation
        case .copyToICloud: return copyToICloud
        }
    }

    static func choice(for response: NSApplication.ModalResponse) -> NotesMigrationChoice {
        switch response {
        case copyToICloud: return .copyToICloud
        default: return .keepCurrentLocation
        }
    }
}

@objc(SpiralLegacyNoteFormattingDetector)
final class SpiralLegacyNoteFormattingDetector: NSObject {
    @objc(containsSignificantFormattingInContents:baseAttributes:)
    static func containsSignificantFormatting(
        in contents: [NSAttributedString],
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> Bool {
        contents.contains { content in
            guard content.length > 0 else { return false }
            var foundFormatting = false
            content.enumerateAttributes(
                in: NSRange(location: 0, length: content.length),
                options: []
            ) { attributes, _, stop in
                if attributesAreSignificantlyFormatted(attributes, baseAttributes: baseAttributes) {
                    foundFormatting = true
                    stop.pointee = true
                }
            }
            return foundFormatting
        }
    }

    private static func attributesAreSignificantlyFormatted(
        _ attributes: [NSAttributedString.Key: Any],
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> Bool {
        var remaining = attributes

        let hasSyntheticHeading = remaining[NSAttributedString.Key("NVHeadingTag")] != nil
        let hasSyntheticDoneStyle = remaining[NSAttributedString.Key("NVDoneTag")] != nil
        remaining = remaining.filter { !$0.key.rawValue.hasPrefix("NV") }

        if hasSyntheticHeading {
            remaining.removeValue(forKey: .underlineStyle)
        }
        if hasSyntheticDoneStyle {
            remaining.removeValue(forKey: .strikethroughStyle)
        }

        // These are display or editor annotations that plain-text notes can
        // regenerate without changing their user-authored content.
        remaining.removeValue(forKey: .foregroundColor)
        remaining.removeValue(forKey: .link)
        remaining.removeValue(forKey: .cursor)
        remaining.removeValue(forKey: .toolTip)

        for (key, baseValue) in baseAttributes {
            guard let value = remaining[key] else { continue }
            if valuesEqual(value, baseValue) {
                remaining.removeValue(forKey: key)
            }
        }

        return !remaining.isEmpty
    }

    private static func valuesEqual(_ first: Any, _ second: Any) -> Bool {
        guard let firstObject = first as? NSObject,
              let secondObject = second as? NSObject else {
            return false
        }
        return firstObject == secondObject
    }
}

@MainActor
enum ApplicationModalWindowRunner {
    static func run(_ window: NSWindow) -> NSApplication.ModalResponse {
        window.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)
        window.close()
        return response
    }
}

@MainActor
enum ApplicationSheetWindowPresenter {
    static func begin(
        _ sheet: NSWindow,
        for parentWindow: NSWindow,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        parentWindow.beginSheet(sheet) { response in
            sheet.orderOut(nil)
            sheet.close()
            completion(response)
        }
    }
}

@MainActor
enum MigrationProgressWindow {
    static func make(title: String, informativeText: String) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 142),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "Spiral"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.setAccessibilityIdentifier("icloudMigration.progressWindow")

        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .regular
        indicator.startAnimation(nil)
        indicator.setAccessibilityIdentifier("icloudMigration.progressIndicator")

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.setAccessibilityIdentifier("icloudMigration.progressTitle")

        let informativeLabel = NSTextField(wrappingLabelWithString: informativeText)
        informativeLabel.textColor = .secondaryLabelColor
        informativeLabel.maximumNumberOfLines = 0
        informativeLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        informativeLabel.setAccessibilityIdentifier("icloudMigration.progressMessage")

        let textStack = NSStackView(views: [titleLabel, informativeLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8

        let contentStack = NSStackView(views: [indicator, textStack])
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(contentStack)
        panel.contentView = contentView

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            contentStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])

        return panel
    }
}
