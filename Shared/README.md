# Shared Code

This directory is reserved for code intentionally shared by the macOS and
future iOS applications.

Shared code must expose platform-neutral interfaces and must not import AppKit
or UIKit. Existing macOS code remains in `Apps/macOS` until characterization
tests protect its behavior and platform dependencies have been removed behind
an explicit boundary.

`SpiralCore` is the shared Swift package established in Phase 2. It contains
the note domain, deterministic clean-file codecs, per-note reconciliation
records, the actor-isolated local `NoteStore`, its disposable index, conflict
values, and the platform-neutral side of the legacy migration boundary. Run
its disposable-directory suite with:

```sh
xcrun swift test --package-path Shared/SpiralCore
```
