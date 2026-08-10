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
    along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */

import SwiftUI

#if os(iOS)
import UIKit

public struct PlatformTextEditor: UIViewRepresentable {
    @Binding private var text: String
    private let isEditable: Bool

    public init(text: Binding<String>, isEditable: Bool = true) {
        _text = text
        self.isEditable = isEditable
    }

    public func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    public func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.adjustsFontForContentSizeCategory = true
        view.font = .preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        view.isScrollEnabled = true
        view.keyboardDismissMode = .interactive
        view.accessibilityIdentifier = "note.editor"
        view.accessibilityLabel = "Note body"
        view.isEditable = isEditable
        view.text = text
        return view
    }

    public func updateUIView(_ view: UITextView, context: Context) {
        view.isEditable = isEditable
        guard view.text != text else { return }
        let selection = view.selectedRange
        view.text = text
        view.selectedRange = NSIntersectionRange(selection, NSRange(location: 0, length: view.text.utf16.count))
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        public func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}

#elseif os(macOS)
import AppKit

public typealias MacTextViewFactory = @MainActor () -> NSTextView

/// Hosts the established AppKit editor inside the shared SwiftUI shell. The
/// legacy application injects `LinkingEditor`; previews and package clients can
/// use the default `NSTextView` without linking the legacy controller graph.
public struct PlatformTextEditor: NSViewRepresentable {
    @Binding private var text: String
    private let isEditable: Bool
    private let makeTextView: MacTextViewFactory

    public init(
        text: Binding<String>,
        isEditable: Bool = true,
        makeTextView: @escaping MacTextViewFactory = { NSTextView() }
    ) {
        _text = text
        self.isEditable = isEditable
        self.makeTextView = makeTextView
    }

    public func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let editor = makeTextView()
        editor.delegate = context.coordinator
        editor.isEditable = isEditable
        editor.isRichText = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.string = text
        editor.setAccessibilityIdentifier("note.editor")
        editor.setAccessibilityLabel("Note body")
        scrollView.hasVerticalScroller = true
        scrollView.documentView = editor
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let editor = scrollView.documentView as? NSTextView else { return }
        editor.isEditable = isEditable
        guard editor.string != text else { return }
        let selection = editor.selectedRange()
        editor.string = text
        editor.setSelectedRange(NSIntersectionRange(selection, NSRange(location: 0, length: editor.string.utf16.count)))
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        public func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            text.wrappedValue = editor.string
        }
    }
}
#endif
