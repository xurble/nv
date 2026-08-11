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

            Link("Based on Notational Velocity", destination: URL(string: "https://notational.net/")!)
                .font(.callout)
                .padding(.top, 20)

            Text("Licensed under the GNU General Public License, version 3 or later.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Link("Source Code on Github", destination: URL(string: "https://github.com/xurble/nv/")!)
                .font(.callout)
                .padding(.vertical, 20)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 42)
        .padding(.bottom, 30)
        .background(.regularMaterial)
    }
}
