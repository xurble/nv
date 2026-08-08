import AppKit
import SwiftUI

@MainActor
struct NotesFolderPathControl: NSViewRepresentable {
    let url: URL?
    let accessibilityIdentifier: String

    init(
        url: URL?,
        accessibilityIdentifier: String = "settings.notes.folderPath"
    ) {
        self.url = url
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    func makeNSView(context: Context) -> NSPathControl {
        Self.makePathControl(
            url: url,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    func updateNSView(_ control: NSPathControl, context: Context) {
        Self.configure(
            control,
            url: url,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    static func makePathControl(
        url: URL?,
        accessibilityIdentifier: String = "settings.notes.folderPath"
    ) -> NSPathControl {
        let control = NSPathControl(frame: .zero)
        control.pathStyle = .standard
        control.isEditable = false
        control.focusRingType = .none
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configure(
            control,
            url: url,
            accessibilityIdentifier: accessibilityIdentifier
        )
        return control
    }

    private static func configure(
        _ control: NSPathControl,
        url: URL?,
        accessibilityIdentifier: String
    ) {
        control.url = url
        control.toolTip = url?.path
        control.setAccessibilityIdentifier(accessibilityIdentifier)
        control.setAccessibilityLabel(String(localized: "Notes folder"))
        control.setAccessibilityValue(url?.path)
    }
}
