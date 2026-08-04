# AGENTS.md

## Project Context

Notational Velocity is a mature Objective-C and C macOS application with long-lived user data, custom editor behaviour, legacy file formats, encryption compatibility, and synchronization code. Treat preservation of user data and established keyboard workflows as higher priority than cosmetic modernization.

Read `MIGRATION_STRATEGY.md` before making architectural, dependency, persistence, encryption, synchronization, or language-migration changes.

## Working Approach

- Prefer small, incremental upgrade wins that leave the app buildable and runnable.
- Modernize at a clear boundary: one API family, dependency, leaf class, or service at a time.
- Do not perform broad rewrites when a focused replacement will remove the immediate risk.
- Separate behaviour changes, API modernization, ARC conversion, and Swift migration whenever practical.
- Preserve existing Objective-C/C code when it is stable and no concrete benefit justifies replacing it.
- Use Swift for new code and for extracted components with well-tested, explicit boundaries; do not pursue a line-for-line Swift rewrite.
- Keep AppKit for text editing, responder-chain behaviour, menus, and keyboard handling unless a replacement has a demonstrated functional benefit.
- Use SwiftUI first for isolated auxiliary UI and embed it incrementally in AppKit.

## Tests Are Part of Every Change

- Add or update automated tests whenever behaviour changes or legacy code is refactored.
- When touching an untested subsystem, first add a focused characterization test that captures the behaviour being relied upon.
- Every bug fix should include a regression test that fails before the fix and passes afterward.
- Dependency or platform-API replacements must include compatibility tests, not just compilation checks.
- Persistence, encryption, WAL, import/export, filename, encoding, metadata, and sync changes require fixture-based tests using copies of disposable data.
- Never run migration or recovery experiments against a user's real notes directory.
- If automated coverage is temporarily impossible, keep the change narrow, document why, and record a repeatable manual verification procedure. This is an exception, not the default.

## Data Compatibility and Safety

- Treat existing note files, metadata, WAL data, preferences, archives, and encrypted databases as public compatibility formats.
- Add golden fixtures before modifying serialization, encryption, key derivation, filename mapping, encodings, or recovery behaviour.
- Do not silently rewrite user data merely because it was successfully read.
- Data-format changes require explicit versioning, backup, migration, failure handling, and rollback behaviour.
- Preserve the ability to read legacy encrypted formats even if new writes adopt a modern format.
- Validate paths and use temporary directories for destructive or failure-injection tests.

## Build and Dependency Hygiene

- Build the Development, Default, and Deployment configurations after changes that affect shared code or project settings.
- Do not add absolute paths to local package managers, SDKs, headers, or libraries.
- The built app must be self-contained and runnable on a clean machine within the declared support range.
- Prefer supported package-management and system-framework integration over checked-in opaque binaries.
- Do not introduce new warnings. Reduce existing warnings locally when doing so is safe and relevant.
- Keep deployment-target, architecture, `Info.plist`, signing, and distribution settings consistent.
- Preserve unrelated user changes and Xcode user data; do not commit `xcuserdata`.

## Objective-C, ARC, and Swift

- Add nullability and lightweight generics when improving Objective-C interfaces.
- Prefer typed protocols, blocks, and direct calls over new dynamic `performSelector:` usage.
- Migrate manual-memory-management code to ARC incrementally and verify ownership-sensitive paths.
- Introduce Swift through narrow interfaces that Objective-C can call safely.
- Avoid migrating the large central controllers or editor classes until their responsibilities have been split and characterized by tests.
- Stable C compatibility implementations may remain C when wrapping them is safer than translating them.

## Platform Modernization

- Prefer URL-based Foundation APIs over Carbon paths, `FSRef`, and raw path buffers.
- Preserve atomic-write, coordination, metadata, and crash-recovery semantics when replacing file APIs.
- Replace deprecated APIs with supported equivalents rather than suppressing warnings globally.
- Replace obsolete third-party frameworks only after tests capture the behaviour the application depends on.
- Treat signing, hardened runtime, notarization, and clean-machine launch as functional requirements.

## Verification Expectations

For an ordinary code change, perform the relevant subset of:

1. focused unit or regression tests;
2. the complete test suite;
3. a Development build;
4. release-configuration builds when project, linker, packaging, or shared code changes;
5. launch verification with a temporary clean data directory; and
6. compatibility verification with representative fixture data.

Report exactly what was tested, what remains untested, and any warnings or compatibility risks that remain.

## Scope Discipline

- Keep pull requests reviewable and centered on one modernization outcome.
- Do not mix formatting sweeps with functional work.
- Avoid speculative abstractions; extract a boundary because a current migration or test needs it.
- Remove an obsolete path after its replacement is verified instead of maintaining indefinite dual implementations.
- Update `MIGRATION_STRATEGY.md` when a decision changes the intended architecture, compatibility policy, supported macOS range, or migration order.
