# Notational Velocity Migration Strategy

## Purpose

Modernize Notational Velocity into a reliable, maintainable macOS application and prepare a future universal iPhone and iPad application, without losing the Mac's keyboard-driven workflow, changing existing note formats unexpectedly, or putting user data at risk. The macOS and iOS applications should use iCloud Drive as their shared data store while remaining usable offline and interoperable with existing local note collections.

The objective is not to rewrite the application for its own sake. Success means that the modernized product family:

- builds reproducibly with current Xcode, macOS, and iOS SDKs as the corresponding targets are introduced;
- is self-contained, signed, hardened, and notarizable;
- preserves existing notes, encrypted data, metadata, and recovery behaviour;
- exposes a tested, platform-neutral storage boundary that both the macOS and future iOS applications can use;
- can place a user-approved note collection in iCloud Drive without silently moving, rewriting, duplicating, or losing existing data;
- handles delayed downloads, offline edits, coordinated writes, external changes, and file conflicts explicitly;
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
- **NoteStore:** a platform-neutral storage contract covering URL-based file access, atomic writes, metadata, change observation, WAL recovery, conflict representation, and migration coordination. It should support both a local directory and an iCloud Drive container without exposing AppKit or UIKit;
- **LegacyCrypto:** a small, thoroughly tested compatibility layer for reading and writing existing encrypted formats;
- **Legacy Sync Compatibility:** retain the ability to read historical per-note and account metadata without activating a remote service; any future synchronization provider should be introduced as a new, separately tested module;
- **Shared iCloud Drive Storage:** platform-specific adapters should locate and coordinate access to the shared ubiquity container while `NoteStore` owns file-format and recovery semantics. Treat iCloud Drive as a coordinated, eventually available filesystem rather than as an immediately consistent database;
- **Application UI:** the AppKit editor and window shell, with SwiftUI used selectively for new auxiliary views; and
- **Update and Distribution:** current Sparkle integration, signing, hardened runtime, notarization, and release automation.

Objective-C and Swift can coexist in the application target. C should remain where it provides a small, stable compatibility implementation. Boundaries between these areas should use explicit types and errors rather than dynamic selector dispatch.

## Repository Layout and Future iOS Application

The repository is organized around explicit product and sharing boundaries:

- `Apps/macOS` contains the existing AppKit application, including its sources, resources, supporting files, and macOS-only dependencies;
- `Apps/iOS` is reserved for a future universal iPhone and iPad application with a platform-appropriate user interface;
- `Shared` is reserved for deliberately extracted, tested code that has no AppKit or UIKit dependency, including the storage contract, compatibility models, and conflict rules shared by the two applications; and
- `Tests/macOS` contains the existing macOS XCTest and characterization suites. Future shared and iOS tests should be placed beside it at the equivalent boundary.

The existing application must not be treated as a multiplatform target merely because an iOS application is planned. Keep separate macOS and iOS app targets while their UI frameworks, life cycles, resources, and platform integrations differ substantially. Share code through narrow core, persistence, compatibility, and service boundaries only after those boundaries are characterized by tests.

The future iOS application should normally use one universal target for both iPhone and iPad. Device-specific layouts may differ, but separate application targets should only be introduced if the products genuinely require different identities, capabilities, or release lifecycles. The macOS and iOS targets should use the same versioned note formats and shared `NoteStore` behavior, while each target owns its iCloud container access, lifecycle integration, user interface, and platform-specific capabilities.

Moving an existing local collection into iCloud Drive must be an explicit, reversible migration with a preflight check, backup, progress reporting, failure recovery, and a documented rollback path. Tests and development builds must use temporary local directories and controlled coordination doubles rather than a developer's or user's live iCloud Drive data.

On a fresh installation with no persisted notes location and no local notes, Spiral should use the entitled iCloud Drive container's `Documents` directory by default, adopting an existing Spiral collection there when present and falling back to the local Application Support directory when iCloud Drive is unavailable. On the first launch of an iCloud-capable version with an existing local collection, offer three explicit choices: **Move to iCloud** (the default), **Copy to iCloud**, or **Keep Current Location**. Both iCloud choices switch Spiral to the verified iCloud copy. Move retires the original only after the copy verifies and the new location is persisted; Copy preserves the original as a local backup. Any destination change must accept an empty folder, refuse a non-empty unrelated folder without modifying it, and offer **Merge** or **Cancel** when the destination contains an identifiable Notational Velocity or Spiral collection. A merge must preserve divergent versions rather than silently overwriting either collection.

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
- old encrypted databases and known plaintext/ciphertext pairs;
- simulated iCloud Drive states including unavailable files, delayed downloads, concurrent edits, conflicts, and interrupted migration; and
- launching against a temporary, disposable notes directory.

Add a shared scheme and continuous integration that builds and tests Development and release configurations. Record the current warning baseline and reject newly introduced warnings.

**Exit criterion:** Critical file formats and behaviours can be changed with automated regression detection.

**Progress as of August 2026:** A shared scheme, a small XCTest target, and five focused characterization executables are in place and passing. Temporary-directory tests now cover the initial iCloud migration default, verified copying, source preservation, destination classification, operation-specific progress text, and timeout/result arbitration for iCloud container discovery. Coverage does not yet protect the critical persistence, WAL, encryption, import/export, encoding, filename, historical synchronization, live legacy-model merge transaction, ongoing iCloud coordination/conflict behavior, or interrupted post-copy commit recovery, and no CI or warning-baseline enforcement is present.

### Phase 2: Make the Product Reproducible and Distributable

- Decide and document the minimum supported macOS version.
- Reconcile the deployment target with `Info.plist`; remove PowerPC, i386, and macOS 10.4-era metadata.
- Move hand-maintained build settings into `.xcconfig` files and reduce configuration-specific drift.
- Remove machine-specific header and library search paths.
- Verify Debug, Release, Archive, and clean-machine launch workflows.
- Add Developer ID signing, hardened runtime, archive validation, and notarization.
- Document the shared iCloud Drive container identifiers, capabilities, and signing requirements for both applications. Keep the guarded first-run copy-and-verify migration separate from the ongoing storage path, which must not be considered production-ready until the storage contract and recovery tests exist.
- Evaluate App Sandbox separately; do not enable it until user-selected folders, security-scoped bookmarks, external editors, and Apple Events have an explicit design.

**Exit criterion:** A release archive runs on a clean supported Mac without Homebrew or developer tools.

**Progress as of August 2026:** The application builds with the current Xcode and macOS SDK, and the macOS target now declares the shared `iCloud.farm.poplar.spiral` Documents container with the Finder name “Spiral Notes.” Fresh installations default to this container when it is available, while existing local collections retain the guarded migration choice. The container identifier still needs registration and verification with the intended Apple Developer team. Deployment metadata remains inconsistent, build settings still contain Homebrew OpenSSL paths, and broader `.xcconfig` extraction, hardened-runtime, signing, notarization, archive, clean-machine, and live-container verification work remains outstanding.

### Phase 3: Replace Obsolete Dependencies

#### OpenSSL and encryption

The built executable currently refers to a Homebrew `libcrypto.3.dylib`. Remove that runtime dependency.

Before replacing it, add golden fixtures for PBKDF2, AES-CBC, MD5-derived identifiers, base64, and legacy IDEA data. Preserve legacy decryption even if a modern authenticated encryption format is introduced for newly written data. Any new format requires an explicit version marker, backup, migration path, and rollback strategy.

#### AutoHyperlinks

Replace the dynamically loaded AutoHyperlinks framework with Foundation text checking, such as `NSDataDetector`, plus compatibility tests for URLs currently recognized by the editor.

#### Sparkle

Replace the bundled legacy Sparkle framework with the current supported release through Swift Package Manager. Move from the old `SUUpdater` path to the current updater controller and adopt HTTPS, modern update signatures, code signing, and notarized update archives.

**Exit criterion:** The application contains no unsupported architecture slices, obsolete executable frameworks, or host-specific dynamic-library references.

**Progress as of August 2026:** Editor URL detection now uses `NSDataDetector` with characterization coverage, and AutoHyperlinks is no longer referenced by the Xcode project, although its framework files remain in the repository. Legacy Sparkle is still bundled, and the executable still links to Homebrew's `libcrypto.3.dylib`.

### Phase 4: Replace Deprecated Platform APIs

Modernize one subsystem at a time:

- replace `FSRef`, Carbon fork access, and path buffers with `NSURL`/`URL` and `NSFileManager`/`FileManager` behind a platform-neutral storage interface that supports both local and iCloud Drive roots;
- preserve atomic-write and recovery guarantees while replacing file primitives;
- replace deprecated Launch Services calls with workspace and URL resource APIs;
- replace synchronous and delegate-selector panels with completion-handler APIs;
- replace `NSArchiver` with a versioned, secure archive or an explicitly modeled format;
- replace legacy WebKit views with `WKWebView`, or remove them if the feature is obsolete;
- replace deprecated file notification mechanisms with an appropriate modern observer; and
- replace `RBSplitView` with `NSSplitViewController` rather than porting the custom implementation.

Each replacement should include tests and land independently where practical.

**Exit criterion:** Normal application paths do not call unsupported Carbon or deprecated framework APIs.

**Progress as of August 2026:** A few isolated UI and text-detection paths have been modernized, but the main file, persistence, import, and application-control paths still use Carbon, `FSRef`, legacy archive/WebKit APIs, and extensive dynamic selector dispatch. The phase remains largely outstanding.

### Phase 5: Adopt ARC and Stronger Objective-C Interfaces

- Add nullability annotations and lightweight generics to headers at subsystem boundaries.
- Replace avoidable `performSelector:` calls with protocols, blocks, or direct typed calls.
- Convert isolated leaf classes to ARC first.
- Progressively enable ARC, temporarily compiling resistant legacy files with `-fno-objc-arc` if necessary.
- Run the static analyzer and memory diagnostics on persistence, synchronization, and editor workflows.

ARC migration should be separate from Swift migration so memory-management regressions are easier to identify.

**Exit criterion:** Most application code uses ARC and exposes sufficiently typed interfaces for safe Swift interoperability.

**Progress as of August 2026:** A narrow Objective-C bridge supports the new Swift settings code, demonstrating basic interoperability. The wider application remains predominantly manual-memory-managed Objective-C, and systematic ARC conversion, nullability, generics, static analysis, and interface strengthening have not begun.

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

**Progress as of August 2026:** The modern settings model and interface provide the first successful Swift component inside the existing application target. A small Foundation-only migration service is now shared at the repository boundary and performs staged, coordinated, verified collection copies. This validates another mixed-language boundary, but no complete cross-platform `NoteStore`, ongoing iCloud Drive adapter, import/export, updater, or concurrency-isolated storage service exists yet.

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

**Progress as of August 2026:** Preferences, the About window, and the first-run iCloud migration choice are implemented as SwiftUI interfaces while the AppKit application shell and editor remain intact. Characterization tests cover settings compatibility and selected keyboard/UI behavior, but broader accessibility, launch, migration-window UI automation, and workflow regression coverage is still needed.

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
2. Create golden note-directory, WAL, encoding, encrypted-data, and simulated iCloud Drive coordination/conflict fixtures.
3. Decide the supported macOS range and correct deployment metadata.
4. Remove the Homebrew OpenSSL runtime dependency without breaking old encrypted data.
5. Replace AutoHyperlinks with Foundation text detection.
6. Upgrade Sparkle and establish signed, notarized release archives.
7. Introduce a platform-neutral, URL-based `NoteStore`; preserve the local-directory implementation first, then add iCloud Drive behind the same contract.
8. Add nullability and generics at the first Swift boundary.
9. Implement one low-coupling service in Swift to validate the mixed-language toolchain.
10. Begin replacing deprecated panels and leaf UI with modern AppKit or embedded SwiftUI.

## Definition of Done for Modernization Changes

A modernization change is complete when:

- existing user data and compatibility formats remain readable;
- local and iCloud Drive-backed collections preserve offline, coordination, conflict, and recovery behavior without silent migration or rewriting;
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
