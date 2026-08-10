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

import SpiralCore
import SwiftUI

#if os(iOS)
import UIKit

public struct PlatformTextEditor: UIViewRepresentable {
    @Binding private var content: NoteContent

    public init(content: Binding<NoteContent>) {
        _content = content
    }

    public func makeCoordinator() -> Coordinator { Coordinator(content: $content) }

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
        view.isEditable = content.supportsFormatPreservingEditing
        view.attributedText = attributedString(for: content, baseFont: view.font!)
        context.coordinator.renderedContent = content
        return view
    }

    public func updateUIView(_ view: UITextView, context: Context) {
        view.isEditable = content.supportsFormatPreservingEditing
        guard context.coordinator.renderedContent != content else { return }
        let selection = view.selectedRange
        view.attributedText = attributedString(for: content, baseFont: .preferredFont(forTextStyle: .body))
        view.selectedRange = NSIntersectionRange(selection, NSRange(location: 0, length: view.text.utf16.count))
        context.coordinator.renderedContent = content
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        private var content: Binding<NoteContent>
        fileprivate var renderedContent: NoteContent?

        init(content: Binding<NoteContent>) { self.content = content }

        public func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            var changed = content.wrappedValue
            do {
                if var document = changed.formattedDocument {
                    try document.replaceText(
                        inUTF16: range.location..<NSMaxRange(range),
                        with: text
                    )
                    changed.formattedDocument = document
                    changed.text = document.text
                } else {
                    try changed.replaceTextPreservingFormat(
                        with: (textView.text as NSString).replacingCharacters(in: range, with: text)
                    )
                }
                content.wrappedValue = changed
                renderedContent = changed
                return true
            } catch {
                return false
            }
        }

        public func textViewDidChange(_ textView: UITextView) {
            guard textView.text != content.wrappedValue.text else { return }
            var changed = content.wrappedValue
            try? changed.replaceTextPreservingFormat(with: textView.text)
            content.wrappedValue = changed
            renderedContent = changed
        }
    }

    private func attributedString(for content: NoteContent, baseFont: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: content.text,
            attributes: [.font: baseFont]
        )
        for run in content.formattedDocument?.runs ?? [] {
            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.style.bold { traits.insert(.traitBold) }
            if run.style.italic { traits.insert(.traitItalic) }
            if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                result.addAttribute(
                    .font,
                    value: UIFont(descriptor: descriptor, size: baseFont.pointSize),
                    range: NSRange(location: run.range.lowerBound, length: run.range.count)
                )
            }
            if run.style.underline {
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                    range: NSRange(location: run.range.lowerBound, length: run.range.count))
            }
            if run.style.strikethrough {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                    range: NSRange(location: run.range.lowerBound, length: run.range.count))
            }
        }
        return result
    }
}

#elseif os(macOS)
import AppKit

public typealias MacTextViewFactory = @MainActor () -> NSTextView

/// Hosts the established AppKit editor inside the shared SwiftUI shell. The
/// legacy application injects `LinkingEditor`; previews and package clients can
/// use the default `NSTextView` without linking the legacy controller graph.
public struct PlatformTextEditor: NSViewRepresentable {
    @Binding private var content: NoteContent
    private let makeTextView: MacTextViewFactory

    public init(
        content: Binding<NoteContent>,
        makeTextView: @escaping MacTextViewFactory = { NSTextView() }
    ) {
        _content = content
        self.makeTextView = makeTextView
    }

    public func makeCoordinator() -> Coordinator { Coordinator(content: $content) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let editor = makeTextView()
        editor.delegate = context.coordinator
        editor.isEditable = content.supportsFormatPreservingEditing
        editor.isRichText = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textStorage?.setAttributedString(attributedString(for: content, baseFont: editor.font ?? .systemFont(ofSize: 13)))
        context.coordinator.renderedContent = content
        editor.setAccessibilityIdentifier("note.editor")
        editor.setAccessibilityLabel("Note body")
        scrollView.hasVerticalScroller = true
        scrollView.documentView = editor
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let editor = scrollView.documentView as? NSTextView else { return }
        editor.isEditable = content.supportsFormatPreservingEditing
        guard context.coordinator.renderedContent != content else { return }
        let selection = editor.selectedRange()
        editor.textStorage?.setAttributedString(
            attributedString(for: content, baseFont: editor.font ?? .systemFont(ofSize: 13))
        )
        editor.setSelectedRange(NSIntersectionRange(selection, NSRange(location: 0, length: editor.string.utf16.count)))
        context.coordinator.renderedContent = content
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        private var content: Binding<NoteContent>
        fileprivate var renderedContent: NoteContent?

        init(content: Binding<NoteContent>) { self.content = content }

        public func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            var changed = content.wrappedValue
            do {
                if var document = changed.formattedDocument {
                    try document.replaceText(
                        inUTF16: affectedCharRange.location..<NSMaxRange(affectedCharRange),
                        with: replacementString ?? ""
                    )
                    changed.formattedDocument = document
                    changed.text = document.text
                } else {
                    try changed.replaceTextPreservingFormat(
                        with: (textView.string as NSString).replacingCharacters(
                            in: affectedCharRange,
                            with: replacementString ?? ""
                        )
                    )
                }
                content.wrappedValue = changed
                renderedContent = changed
                return true
            } catch {
                return false
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            guard editor.string != content.wrappedValue.text else { return }
            var changed = content.wrappedValue
            try? changed.replaceTextPreservingFormat(with: editor.string)
            content.wrappedValue = changed
            renderedContent = changed
        }
    }

    private func attributedString(for content: NoteContent, baseFont: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: content.text,
            attributes: [.font: baseFont]
        )
        let manager = NSFontManager.shared
        for run in content.formattedDocument?.runs ?? [] {
            var font = baseFont
            if run.style.bold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
            if run.style.italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
            let range = NSRange(location: run.range.lowerBound, length: run.range.count)
            result.addAttribute(.font, value: font, range: range)
            if run.style.underline {
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            if run.style.strikethrough {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        return result
    }
}
#endif
