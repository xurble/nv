import SwiftUI

#if os(iOS)
import UIKit

public struct PlatformTextEditor: UIViewRepresentable {
    @Binding private var text: String

    public init(text: Binding<String>) {
        _text = text
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
        view.text = text
        return view
    }

    public func updateUIView(_ view: UITextView, context: Context) {
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
    private let makeTextView: MacTextViewFactory

    public init(
        text: Binding<String>,
        makeTextView: @escaping MacTextViewFactory = { NSTextView() }
    ) {
        _text = text
        self.makeTextView = makeTextView
    }

    public func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let editor = makeTextView()
        editor.delegate = context.coordinator
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
        guard let editor = scrollView.documentView as? NSTextView, editor.string != text else { return }
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
