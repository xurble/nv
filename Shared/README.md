# Shared Code

This directory is reserved for code intentionally shared by the macOS and iOS
applications.

The model and storage layers must expose platform-neutral interfaces and must
not import AppKit or UIKit. A shared UI package may use small, conditionally
compiled platform adapters at its editor-hosting boundary. Existing macOS code
remains in `Apps/macOS` until characterization tests protect its behavior and
platform dependencies have been removed behind an explicit boundary.

`SpiralCore` is the shared Swift package established in Phase 2 and extended
through the production-selected, live-verification-pending Phase 4 iCloud boundary. It contains the
note domain, deterministic clean-file codecs, per-note reconciliation records,
the actor-isolated local `NoteStore`, its disposable index, conflict values,
the platform-neutral side of the legacy migration boundary, OS 26 coordinated
document adapters, the production `CloudNoteStore`, deterministic reconciliation,
legacy-artifact retirement, and the durable copy-only publication journal. Run its disposable-directory and multi-device fault suite
with:

```sh
xcrun swift test --package-path Shared/SpiralCore
```

`SpiralFeature` is the Phase 3 SwiftUI vertical slice. It owns adaptive
collection navigation, list/search/editor workflows, settings and explicit
collection states against `NoteStore`. Its iOS editor adapter hosts
`UITextView`; its Mac adapter accepts an injected `NSTextView` factory so the
application can keep using `LinkingEditor` without exposing that legacy class
to iOS. Run its model suite with:

```sh
xcrun swift test --package-path Shared/SpiralFeature
```
