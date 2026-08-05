# Notational Velocity Migration Strategy

## Purpose

Modernize Notational Velocity into a reliable, maintainable macOS application without losing its keyboard-driven workflow, changing existing note formats unexpectedly, or putting user data at risk.

The objective is not to rewrite the application for its own sake. Success means that the app:

- builds reproducibly with a current Xcode and macOS SDK;
- is self-contained, signed, hardened, and notarizable;
- preserves existing notes, encrypted data, metadata, and recovery behaviour;
- no longer depends on unsupported Carbon APIs or obsolete binary frameworks;
- has automated coverage for important behaviour and compatibility formats; and
- uses Swift for new and substantially refactored code where Swift improves safety and clarity.

## Current Assessment

The project contains approximately 40,000 lines of Objective-C and C. Its largest and most interconnected classes include `NoteObject`, `AppController`, `NotationController`, `LinkingEditor`, and `NotesTableView`. There is currently no automated test target.

The main modernization risks are not caused by Objective-C itself. They are:

- manual reference counting throughout the application;
- Carbon and `FSRef`-based file handling;
- extensive dynamic selector use and weakly typed interfaces;
- deprecated synchronous AppKit panels and alerts;
- old archive, WebKit, Launch Services, and notification APIs;
- pre-Apple-Silicon Sparkle and AutoHyperlinks frameworks;
- an executable dependency on a Homebrew OpenSSL installation;
- legacy encryption and recovery formats that must remain readable; and
- inconsistent deployment metadata and build settings inherited from much older macOS releases.

Changing the SDK used to build the app and changing its minimum supported macOS version are separate decisions. The project should use the current SDK while setting `MACOSX_DEPLOYMENT_TARGET` to the oldest release the product intentionally supports. `Info.plist`, Xcode settings, embedded frameworks, and release documentation must agree on that choice.

## Guiding Principles

1. **Protect user data first.** Add compatibility fixtures before changing persistence, encryption, filenames, metadata, recovery, or synchronization.
2. **Prefer incremental replacements.** Replace one dependency, API boundary, or leaf component at a time and keep the application runnable between changes.
3. **Test behaviour, not implementation details.** Characterize legacy behaviour before refactoring it.
4. **Keep changes reversible.** Avoid combining a language migration, architecture change, and behaviour change in one pull request.
5. **Use modern platform APIs.** Remove compatibility code for operating systems outside the declared support range.
6. **Treat warnings as migration inventory.** Establish a warning baseline, prevent new warnings, and reduce the existing set by subsystem.
7. **Do not equate modernization with a complete Swift or SwiftUI rewrite.** Language and UI migrations should follow stable boundaries and tests.

## Recommended Target Architecture

The near-term architecture should remain a native AppKit application, retaining `NSTextView` and established command handling for the core editing experience.

New and refactored functionality should move behind explicit modules or service boundaries:

- **NoteCore:** typed note values, labels, search rules, filename rules, and format-independent transformations;
- **NoteStore:** URL-based file access, atomic writes, metadata, change observation, WAL recovery, and migration coordination;
- **LegacyCrypto:** a small, thoroughly tested compatibility layer for reading and writing existing encrypted formats;
- **Legacy Sync Compatibility:** retain the ability to read historical per-note and account metadata without activating a remote service; any future synchronization provider should be introduced as a new, separately tested module;
- **Application UI:** the AppKit editor and window shell, with SwiftUI used selectively for new auxiliary views; and
- **Update and Distribution:** current Sparkle integration, signing, hardened runtime, notarization, and release automation.

Objective-C and Swift can coexist in the application target. C should remain where it provides a small, stable compatibility implementation. Boundaries between these areas should use explicit types and errors rather than dynamic selector dispatch.

## Phased Plan

### Phase 1: Establish a Safety Net

Create XCTest unit and integration test targets before undertaking structural migrations.

Add fixtures and characterization tests for:

- loading and saving every supported note format and encoding;
- filename generation, collision handling, and reserved characters;
- labels and extended metadata;
- WAL replay, interrupted writes, and recovery after a simulated crash;
- search matching, ordering, and highlighting;
- import and export paths;
- loading archives containing historical synchronization metadata without starting a remote service or rewriting that metadata;
- old encrypted databases and known plaintext/ciphertext pairs; and
- launching against a temporary, disposable notes directory.

Add a shared scheme and continuous integration that builds and tests Development and release configurations. Record the current warning baseline and reject newly introduced warnings.

**Exit criterion:** Critical file formats and behaviours can be changed with automated regression detection.

### Phase 2: Make the Product Reproducible and Distributable

- Decide and document the minimum supported macOS version.
- Reconcile the deployment target with `Info.plist`; remove PowerPC, i386, and macOS 10.4-era metadata.
- Move hand-maintained build settings into `.xcconfig` files and reduce configuration-specific drift.
- Remove machine-specific header and library search paths.
- Verify Debug, Release, Archive, and clean-machine launch workflows.
- Add Developer ID signing, hardened runtime, archive validation, and notarization.
- Evaluate App Sandbox separately; do not enable it until user-selected folders, security-scoped bookmarks, external editors, and Apple Events have an explicit design.

**Exit criterion:** A release archive runs on a clean supported Mac without Homebrew or developer tools.

### Phase 3: Replace Obsolete Dependencies

#### OpenSSL and encryption

The built executable currently refers to a Homebrew `libcrypto.3.dylib`. Remove that runtime dependency.

Before replacing it, add golden fixtures for PBKDF2, AES-CBC, MD5-derived identifiers, base64, and legacy IDEA data. Preserve legacy decryption even if a modern authenticated encryption format is introduced for newly written data. Any new format requires an explicit version marker, backup, migration path, and rollback strategy.

#### AutoHyperlinks

Replace the dynamically loaded AutoHyperlinks framework with Foundation text checking, such as `NSDataDetector`, plus compatibility tests for URLs currently recognized by the editor.

#### Sparkle

Replace the bundled legacy Sparkle framework with the current supported release through Swift Package Manager. Move from the old `SUUpdater` path to the current updater controller and adopt HTTPS, modern update signatures, code signing, and notarized update archives.

**Exit criterion:** The application contains no unsupported architecture slices, obsolete executable frameworks, or host-specific dynamic-library references.

### Phase 4: Replace Deprecated Platform APIs

Modernize one subsystem at a time:

- replace `FSRef`, Carbon fork access, and path buffers with `NSURL`/`URL` and `NSFileManager`/`FileManager`;
- preserve atomic-write and recovery guarantees while replacing file primitives;
- replace deprecated Launch Services calls with workspace and URL resource APIs;
- replace synchronous and delegate-selector panels with completion-handler APIs;
- replace `NSArchiver` with a versioned, secure archive or an explicitly modeled format;
- replace legacy WebKit views with `WKWebView`, or remove them if the feature is obsolete;
- replace deprecated file notification mechanisms with an appropriate modern observer; and
- replace `RBSplitView` with `NSSplitViewController` rather than porting the custom implementation.

Each replacement should include tests and land independently where practical.

**Exit criterion:** Normal application paths do not call unsupported Carbon or deprecated framework APIs.

### Phase 5: Adopt ARC and Stronger Objective-C Interfaces

- Add nullability annotations and lightweight generics to headers at subsystem boundaries.
- Replace avoidable `performSelector:` calls with protocols, blocks, or direct typed calls.
- Convert isolated leaf classes to ARC first.
- Progressively enable ARC, temporarily compiling resistant legacy files with `-fno-objc-arc` if necessary.
- Run the static analyzer and memory diagnostics on persistence, synchronization, and editor workflows.

ARC migration should be separate from Swift migration so memory-management regressions are easier to identify.

**Exit criterion:** Most application code uses ARC and exposes sufficiently typed interfaces for safe Swift interoperability.

### Phase 6: Introduce Swift Incrementally

Swift is the preferred language for new code and for refactored components with clear boundaries. Good early candidates include:

- typed networking for any newly introduced remote service;
- typed request and response models using `Codable`;
- preference models and new settings UI;
- import/export helpers and format-independent transformations;
- filename and search utilities;
- updater integration;
- structured error reporting; and
- concurrency-isolated storage coordination behind an Objective-C-compatible façade.

Poor initial migration candidates include:

- `NoteObject`;
- `NotationController` and `AppController`;
- `LinkingEditor` and the central editor command path;
- controllers tightly coupled to old nibs and dynamic selectors; and
- stable C compatibility algorithms.

Migrate one class or component at a time. Do not rewrite an Objective-C class and redesign its behaviour in the same change.

**Exit criterion:** New non-legacy functionality is normally written in Swift, while remaining Objective-C exists intentionally.

### Phase 7: Modernize the Interface Selectively

Retain AppKit for the main window, text system, menus, responder chain, and advanced keyboard handling until there is a demonstrated reason to replace them.

Use SwiftUI first for low-risk, self-contained areas:

- preferences;
- onboarding and migration status;
- empty and error states;
- inspectors and informational panels; and
- update UI.

Embed SwiftUI in the existing AppKit hierarchy with `NSHostingView` or `NSHostingController`. Reassess a broader SwiftUI lifecycle migration only after storage, commands, application state, and window ownership have clear boundaries.

**Exit criterion:** Modern UI components coexist cleanly with the editor, without degrading keyboard behaviour, accessibility, or native text handling.

### Phase 8: Reassess the Legacy Core

Once tests, ARC, and service boundaries are established, review the large core classes. Split responsibilities before deciding whether to migrate them to Swift. A smaller Objective-C façade over tested Swift services may be safer than translating a large class line for line.

Delete old compatibility paths, nibs, frameworks, and source files only after their replacements have shipped and migration compatibility has been verified.

## Swift Decision

There is meaningful value in Swift, particularly from:

- null safety and stronger value types;
- typed errors and serialization;
- structured concurrency;
- easier use of current Apple frameworks and Swift packages;
- improved testability when code is moved into small services; and
- a clearer path for future contributors.

A wholesale Swift rewrite is not recommended. It would create substantial regression and data-loss risk while leaving the actual platform, dependency, packaging, and test problems to be solved separately. The preferred approach is to make Swift the destination for new and deliberately extracted code while allowing proven Objective-C and C code to remain until replacing it has a measurable benefit.

## Suggested Initial Backlog

1. Add shared schemes, XCTest targets, and CI builds.
2. Create golden note-directory, WAL, encoding, and encrypted-data fixtures.
3. Decide the supported macOS range and correct deployment metadata.
4. Remove the Homebrew OpenSSL runtime dependency without breaking old encrypted data.
5. Replace AutoHyperlinks with Foundation text detection.
6. Upgrade Sparkle and establish signed, notarized release archives.
7. Introduce URL-based file APIs behind the existing storage interface.
8. Add nullability and generics at the first Swift boundary.
9. Implement one low-coupling service in Swift to validate the mixed-language toolchain.
10. Begin replacing deprecated panels and leaf UI with modern AppKit or embedded SwiftUI.

## Definition of Done for Modernization Changes

A modernization change is complete when:

- existing user data and compatibility formats remain readable;
- new or changed behaviour is covered by automated tests;
- all configurations build without new warnings;
- the application launches against both representative fixtures and a clean data directory;
- release packaging remains self-contained and signable;
- migration and rollback behaviour is documented where data changes are involved; and
- obsolete code or dependencies replaced by the change are removed rather than left as an untested parallel path.

## References

- [Apple: Migrating Objective-C Code to Swift](https://developer.apple.com/documentation/swift/migrating-your-objective-c-code-to-swift)
- [Apple: Importing Objective-C into Swift](https://developer.apple.com/documentation/swift/importing-objective-c-into-swift)
- [Apple: AppKit integration with SwiftUI](https://developer.apple.com/documentation/swiftui/appkit-integration)
- [Apple: Configuring the Hardened Runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime/)
- [Sparkle documentation](https://sparkle-project.org/documentation/)
- [Sparkle upgrade guidance](https://sparkle-project.org/documentation/upgrading/)
