import AppKit
import SwiftUI

@objc(ModernAboutWindowController)
@MainActor
final class ModernAboutWindowController: NSObject, NSWindowDelegate {
    private var aboutWindowController: NSWindowController?

    @objc(showWindow:)
    func showWindow(_ sender: Any?) {
        if aboutWindowController == nil {
            let information = AboutInformation(infoDictionary: Bundle.main.infoDictionary ?? [:])
            let rootView = ModernAboutView(
                information: information,
                applicationIcon: NSApp.applicationIconImage
            )
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "About \(information.applicationName)"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 420, height: 390))
            window.center()
            window.delegate = self
            aboutWindowController = NSWindowController(window: window)
        }

        aboutWindowController?.showWindow(sender)
        aboutWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct ModernAboutView: View {
    let information: AboutInformation
    let applicationIcon: NSImage

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: applicationIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .accessibilityLabel("\(information.applicationName) application icon")
                .padding(.bottom, 18)

            Text(information.applicationName)
                .font(.system(size: 28, weight: .semibold))
                .lineLimit(1)

            if !information.versionDescription.isEmpty {
                Text(information.versionDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            VStack(spacing: 4) {
                ForEach(AboutInformation.credits, id: \.self) { credit in
                    Text(credit)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(.top, 24)

            Link("Original Notational Velocity", destination: URL(string: "https://notational.net/")!)
                .font(.callout)
                .padding(.top, 20)

            Text("Licensed under the GNU General Public License, version 3 or later.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 42)
        .padding(.bottom, 30)
        .background(.regularMaterial)
    }
}
