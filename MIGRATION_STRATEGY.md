# Notational Velocity Migration Strategy

## Purpose

Modernize Notational Velocity into a reliable, maintainable macOS application and develop the existing universal iPhone and iPad application, without losing the Mac's keyboard-driven workflow, changing existing note formats unexpectedly, or putting user data at risk. The macOS and iOS applications should use iCloud Drive as their shared data store while remaining usable offline and interoperable with existing local note collections.

The objective is not to rewrite the application for its own sake. Success means that the modernized product family:

- builds reproducibly with current Xcode, macOS, and iOS SDKs as the corresponding targets are introduced;
- is self-contained, signed, hardened, and notarizable;
- preserves existing notes, encrypted data, metadata, and recovery behaviour;
- exposes a tested, platform-neutral storage boundary that both the macOS and iOS applications can use;
- can place a user-approved note collection in iCloud Drive without unexpectedly moving, rewriting, duplicating, or losing existing data, subject to the documented automatic upgrade of an ordinary unencrypted legacy single-database collection;
- handles delayed downloads, offline edits, coordinated writes, external changes, and file conflicts explicitly;
- gives every app-managed note a stable, cross-device identity suitable for iCloud conflict handling, deep links, Spotlight, App Intents, and Siri, while preserving both files when an external rename-plus-edit makes identity ambiguous;
- exposes only user-approved note content to Spotlight, Apple Intelligence, and Siri, with unavailable legacy-encrypted content and privacy-excluded notes omitted by default;
- no longer depends on unsupported Carbon APIs or obsolete binary frameworks;
- has automated coverage for important behaviour and compatibility formats; and
- uses Swift for new and substantially refactored code where Swift improves safety and clarity.

## Current Assessment

The project contains approximately 40,000 lines of Objective-C and C. Its largest and most interconnected classes include `NoteObject`, `AppController`, `NotationController`, `LinkingEditor`, and `NotesTableView`. Phase 1 provides separate XCTest unit and disposable-directory integration targets plus focused characterization executables for critical legacy seams, and its complete Debug and Release safety-net runs are green below the recorded warning ceiling. Phase 2 has met its exit criterion: the shared storage boundary now exercises representative full Notational Velocity and nvAlt archives through the production compatibility reader and shared migration service, and its lossless token document permits format-preserving RTF/HTML editing. Phase 3 has added a universal mobile target and shared SwiftUI feature, but executed cross-platform UI tests remain required before that phase meets its exit criterion.

The main modernization risks are not caused by Objective-C itself. They are:

- manual reference counting throughout the application;
- Carbon and `FSRef`-based file handling;
- extensive dynamic selector use and weakly typed interfaces;
- deprecated synchronous AppKit panels and alerts;
- old archive, WebKit, Launch Services, and notification APIs;
- obsolete AutoHyperlinks framework files that are no longer part of the target;
- the deliberately bounded RTF/HTML parser and serializer, which must continue expanding fixture coverage as additional authored constructs are encountered;
- legacy cryptographic compatibility code that must remain isolated and fixture-tested;
- legacy encryption and recovery formats that must remain readable; and
- inconsistent deployment metadata and build settings inherited from much older macOS releases.

Changing the SDK used to build the app and changing its minimum supported operating-system version are separate decisions. Spiral's declared minimum is macOS 26, iOS 26, and iPadOS 26. The project should use the current SDK while setting every app and test target to those minimums. `Info.plist`, Xcode settings, embedded frameworks, and release documentation must agree; the current project still contains older project-level overrides and an iOS 17 UI-test target that must be corrected.

## Guiding Principles

1. **Protect user data first.** Add compatibility fixtures before changing persistence, encryption, filenames, metadata, recovery, or synchronization.
2. **Prefer incremental replacements.** Replace one dependency, API boundary, or leaf component at a time and keep the application runnable between changes.
3. **Test behaviour, not implementation details.** Characterize legacy behaviour before refactoring it.
4. **Keep changes reversible.** Avoid combining a language migration, architecture change, and behaviour change in one pull request.
5. **Use modern platform APIs.** Remove compatibility code for operating systems outside the declared support range.
6. **Treat warnings as migration inventory.** Establish a warning baseline, prevent new warnings, and reduce the existing set by subsystem.
7. **Do not equate modernization with a complete Swift or SwiftUI rewrite.** Language and UI migrations should follow stable boundaries and tests.
8. **Design identity before synchronization.** Titles and filenames are mutable presentation, not note identity. Assign a permanent UUID before iCloud, deep-link, or App Entity work.
9. **Keep cloud data and local indexes separate.** Rebuildable search indexes, thumbnails, caches, and local database accelerators must not be synchronized as user documents.
10. **Keep canonical note files clean.** New notes are ordinary attachment-free plain text, RTF, or HTML files. Do not embed Spiral UUIDs, revision records, tags, application state, or other private metadata in their content.

## Recommended Target Architecture

The product should become a shared Swift domain and storage system with separate SwiftUI application shells. Platform-specific text views and integrations remain behind narrow adapters:

- **NoteDomain (shared Swift package):** `Sendable` value types for notes, tags, folders, revisions, and conflicts. Attachments are not part of the product model. An app-managed note has a permanent UUID that does not change when its title, filename, or folder changes.
- **NoteFileCodec (shared Swift package):** deterministic, fixture-tested readers and writers for ordinary `.txt`, `.rtf`, and `.html` files. UTF-8 plain text is the preferred format for new notes. RTF is limited to textual rich formatting, and HTML must be self-contained textual markup with no linked assets, embedded media, or companion resource directories. Editing an existing RTF or HTML note must preserve its authored formatting or markup; a plain-string round trip is not sufficient. The canonical file contains only user content and the syntax required by its declared format; it contains no Spiral manifest or embedded application metadata. The legacy Notational Velocity/nvAlt collection database remains a migration input only, not a competing live store or a format for new exports.
- **ReconciliationStore (shared Swift package):** private, per-note reconciliation records stored outside the public `Documents` directory of Spiral's iCloud ubiquity container. Local-only collections use the equivalent private Application Support location and migrate their records when the collection explicitly moves to iCloud. A record maps a UUID to its current and recent relative paths, raw-content hash, last common revision, bounded merge-base snapshot, app-only metadata, and tombstone state. Use one independently replaceable record directory per note rather than one global manifest or database file. The visible note must remain usable if this state is unavailable; loss of reconciliation state may lose app-only metadata or require conservative identity recovery, but must never make note content unreadable.
- **NoteStore (shared Swift package):** an actor-isolated storage contract for enumeration, lookup by stable ID, search, create/update/delete, coordinated saves, change observation, conflict representation, migration, and index events. It must not expose `AppKit`, `UIKit`, SwiftUI scene state, or Objective-C model objects.
- **Document adapters:** because iOS and iPadOS 26 are supported, implement the Phase 4 document layer behind an OS 26-compatible adapter without exposing availability details to `NoteStore`. Phase 9 may replace or extend that adapter with the OS 27 SwiftUI `Document`/`ReadableDocument`/`WritableDocument` APIs, which provide async URL access, snapshots, progress, and a framework-provided file coordinator.
- **Local index:** a rebuildable local SQLite, SwiftData, or Core Spotlight index may accelerate collection search, but it lives in Application Support, never in iCloud Drive, and is never authoritative. If SwiftData-to-CloudKit synchronization is later used for app-only metadata, keep its store local and treat file delivery and CloudKit delivery as independent, asynchronously ordered channels.
- **SystemIntegration (shared Swift sources where possible):** `NoteEntity`, entity queries, App Intents, Spotlight donation, deep-link routing, and privacy policy. The Mac and iOS applications link the same entity and intent definitions.
- **Notational Velocity/nvAlt LegacyCompatibility:** permanently retained, fixture-tested support for opening the single-database archive, deriving and verifying its encryption keys, decrypting encrypted archives, replaying its WAL, and reading historic sync metadata, filenames, and encodings. This code exists specifically so people can migrate collections created by Notational Velocity or nvAlt. It is important compatibility code, not disposable technical debt, but it must not pull the AppKit-era object graph into the new store after migration.
- **Application UI:** SwiftUI owns navigation, search/list presentation, inspector/panels, settings, onboarding, migration, conflicts, and platform-adaptive layout. The Mac initially wraps its proven `NSTextView`/`LinkingEditor` behavior; iPhone and iPad use a SwiftUI editor or a wrapped `UITextView` where TextKit control is required.
- **macOSIntegration:** menus, commands, responder-chain behavior, services, global hotkey, external editor handoff, multiwindow behavior, and distribution remain Mac-only adapters.

Objective-C and Swift can coexist while the boundary is extracted. C should remain only for small, stable legacy compatibility algorithms. New boundaries use typed async APIs and errors rather than notifications, dynamic selectors, or shared controller state.

## Storage Decision: Per-Note Documents in iCloud Drive

The canonical iCloud Drive store should use one coordinated document per note, not one live collection database.

| Option | Decision | Reason |
| --- | --- | --- |
| One legacy archive/WAL in iCloud Drive | Do not use as the live shared store | Every edit changes the collection file, unrelated offline edits conflict at whole-library granularity, and the current archive/WAL implementation is not an iCloud document implementation. |
| One SQLite database file in iCloud Drive | Do not use | Apple's iCloud guidance explicitly says a SQLite store file must not be stored in iCloud document storage. WAL/SHM sidecars and cross-device conflict copies make it especially unsafe. |
| One collection document/package containing an internal database | Technically possible, not recommended | `Document`, `UIDocument`, or `NSDocument` can coordinate a single package and surface versions, but cross-device conflicts still concern the whole collection and require a custom record-level merge. It also increases download, recovery, and corruption blast radius. |
| Local database mirrored with CloudKit | Viable alternative if Finder-visible documents cease to be a requirement | `NSPersistentCloudKitContainer` or `CKSyncEngine` keeps a local database and syncs records, rather than copying the database file through iCloud Drive. This is a different product/storage decision and a much larger legacy migration. |
| One `.spiralnote` package per note | Do not use for the canonical store | There are no attachments, and a package would hide metadata inside what appears to be a note while reducing interoperability with external text editors. |
| One clean `.txt`, `.rtf`, or `.html` file per note, with private per-note reconciliation records | Recommended | Conflicts, download, repair, and history are scoped to one note; the visible files remain directly editable and portable; and app metadata does not contaminate their contents. |

The existing single-file format and its encryption implementation are legacy compatibility formats for people migrating from Notational Velocity or nvAlt. Retain the code required to identify, open, verify, decrypt, recover, and migrate those collections for as long as the product supports those users. Existing users must be able to migrate a verified copy to per-note documents without losing note content, metadata, or WAL-recoverable changes, while retaining an encrypted source backup until they deliberately remove it. Do not use the legacy format for newly created collections or continue writing it after migration. The current Mac compatibility runtime intentionally upgrades an ordinary unencrypted single-database collection to RTF files on launch as documented below; encrypted collections and first-run imports continue to use their guarded paths.

This compatibility promise includes encrypted collections, but the clean-file migration does not introduce a replacement application-encryption writer. Remove an old primitive only if an equivalent, fixture-verified implementation continues to read every supported Notational Velocity and nvAlt encryption variant. Any future encrypted modern mode would be a separate product and storage decision because a file cannot simultaneously be externally editable plaintext and application-encrypted content.

The clean-file store and its reconciliation layer need these properties:

- the canonical note is a single ordinary `.txt`, `.rtf`, or `.html` file with no embedded UUID, schema version, tags, pin state, revision token, or Spiral-specific metadata;
- the filename supplies the display title and the containing directories supply visible folder organization;
- app-only metadata and stable UUID mapping live in the private per-note reconciliation record outside the public `Documents` directory;
- app-produced serialization is deterministic so unchanged saves do not create noisy iCloud revisions, while externally produced valid files are preserved without gratuitous normalization;
- raw-byte content hashes and bounded merge-base snapshots support verification and three-way conflict handling;
- tombstones prevent an offline client from accidentally resurrecting a deleted note;
- `NSFileCoordinator`, `NSFilePresenter`, `NSMetadataQuery`, and `NSFileVersion` are used through platform adapters for coordinated access, discovery, and conflict inspection;
- discovery includes a full reconciliation scan at launch and foregrounding because uncoordinated external writes do not reliably generate file-presenter notifications;
- a locally absent iCloud file is not treated as deleted until metadata state distinguishes deletion from eviction or delayed download; and
- no identity depends on OpenMeta tags, extended attributes, HFS catalog IDs, volume UUIDs, or other metadata attached to the clean file.

Use a title-derived filename with collision handling. App-coordinated renames retain the UUID. For external changes, match the current path first, then use prior paths and content hashes to recognize safe rename and move cases. A new unmatched file receives a new UUID; an unambiguous copy receives a new UUID; and a missing file creates a tombstone only after deletion is confirmed. A rename combined with a content edit outside Spiral can be indistinguishable from delete-plus-create or copy-plus-edit because the file carries no stable identifier. When identity or a merge is ambiguous, preserve both versions and ask the user rather than silently assigning history or overwriting content.

The reconciliation history is not an unlimited second copy of the collection. Retain only the revision ancestry and bounded common-base content required for conflict recovery, define a deletion and retention policy, and ensure deleting a note also makes its private history eligible for deletion. A local SwiftData index may map UUIDs to current URLs and can regenerate from the clean files and reconciliation records; do not put its SQLite store file in iCloud Drive.

Clean files are necessarily readable plaintext at the application level. Migrating a legacy encrypted collection to the modern clean-file store must explicitly warn the user that the destination is no longer protected by Notational Velocity/nvAlt application-level encryption, retain the verified encrypted source backup until the user deliberately removes it, and never imply that iCloud account or device protection is equivalent to the legacy passphrase format. Legacy decryptors remain permanently supported for migration.

### Implemented Transitional First-Run Import

As of August 2026, the Mac application has a guarded first-run importer that establishes the intended user experience while reusing the existing legacy controller as a quarantined conversion engine:

1. Before application launch, Spiral checks for its own persistent preference domain. If Spiral preferences already exist, it uses the configured Spiral location and does not offer a legacy import. Otherwise it detects the Notational Velocity and nvAlt preference domains; when both exist, Notational Velocity currently takes precedence. Detection does not copy any legacy preference values into Spiral.
2. When a legacy domain is detected, Spiral asks whether to import the notes. Acceptance opens a directory-only selection panel; Spiral does not automatically follow the legacy `DirectoryAlias` or access a legacy notes directory without this explicit user selection.
3. Spiral resolves its entitled iCloud container and accepts an empty destination. It refuses a destination containing unrelated data. If a recognizable Spiral collection already exists there, Spiral adopts it without overwriting it and leaves the selected legacy collection untouched.
4. Spiral makes and byte-verifies a disposable local copy of the selected folder. All archive opening, WAL recovery, passphrase handling, decryption, storage-format changes, and note-file generation operate on that copy. The migration-specific legacy-controller initializer does not adopt the legacy collection's font or other presentation preferences into Spiral.
5. A collection with a `Notes & Settings` database uses the archived collection format as its first format signal. If that format is the single database, Spiral inspects every note's attributed content. Base styling, display colour, automatically detected links, and nvAlt's synthetic Markdown/task display attributes do not count as authored rich formatting. If any remaining formatting is present, the complete collection is exported as `.rtf`; otherwise it is exported as `.txt`. The exporter forces those standard extensions and verifies that every note has a corresponding regular file before publication.
6. A folder without the database is inferred from its visible note extensions. TXT-family extensions (`txt`, `text`, `utf8`, `taskpaper`, `md`, and `markdown`), RTF, and HTML-family extensions (`html` and `htm`) are recognized. A folder may mix these clean formats; the inferred collection preference only selects the default format for newly created notes. A folder with no recognized note files is rejected rather than guessed.
7. For an encrypted database, the retained compatibility code obtains the passphrase and decrypts only the disposable copy. The confirmation text warns that the destination files are ordinary unencrypted files. Disabling encryption in the working copy neither modifies the original archive nor removes its legacy Keychain item.
8. Spiral copies and byte-verifies the converted working collection into its iCloud `Documents` directory, switches to that verified destination, and deletes the disposable copy. The original selected folder is always retained. There is no move option. The manual “switch to iCloud” workflow is also copy-or-keep only.

This is a transitional bridge, not the Phase 4 production store. The current Mac runtime still requires `Notes & Settings` and may retain legacy journal or metadata state alongside the generated per-note files; it continues to use that compatibility database as part of its live object graph. Consequently, the present iCloud folder is not yet the clean, metadata-free canonical store and must not be opened concurrently by the iPhone/iPad client. Phase 2 has implemented the shared migration types and local store, but must still connect the production compatibility reader to that path with representative archives. Phase 4 must publish only canonical note files in the public `Documents` directory before multi-client iCloud use is enabled.

### Implemented Automatic Unencrypted Legacy Upgrade

Outside the guarded first-run import, opening an ordinary writable, unencrypted `SingleDatabaseFormat` collection in the Mac application now changes its storage preference to RTF and writes per-note RTF files during controller initialization. The migration-specific importer suppresses this path so it can inspect formatting and choose TXT or RTF on its disposable copy, and encrypted collections are not automatically converted. This launch-time upgrade is intentional current behavior. It is not the Phase 2 shared-store migration and does not by itself create reconciliation records or remove the compatibility database.

## UI Direction and Mac Retention Decisions

SwiftUI is on the critical path because the existing universal iPhone/iPad target and the Mac product need shared navigation, note list, search, selection, command models, sheets, and system-context annotations. Mobile development must not wait for a complete Objective-C or ARC migration.

The implemented vertical slice shows disposable fixture collections in a SwiftUI `NavigationSplitView` on iPad and Mac and a compact navigation stack on iPhone. It supports search, open, create, format-preserving text edit, save, rename, tag, pin, delete, and conflict display through `NoteStore`. The Mac shell can host its existing editor while iOS uses a `UITextView` adapter; both adapters render the shared RTF/HTML inline-style model and submit UTF-16 edit ranges without flattening the source representation.

Do not make a source-level SwiftUI view automatically shared just because it compiles on every platform. Share feature state, commands, and views where interaction is genuinely common; use platform-specific toolbars, menus, keyboard commands, windowing, and text-editor wrappers.

Apple's current TextKit guidance continues to recommend `NSTextView` and `UITextView` for convenient, powerful rich-text editors, including when they are wrapped in SwiftUI. SwiftUI `TextEditor` with `AttributedString` is a credible iOS editor candidate, but it must pass characterization tests for links, indentation, find, selection, undo, input methods, accessibility, large notes, and the Mac's command semantics before replacing the AppKit editor.

### Retain as behavior, but replace the implementation

- the Mac's keyboard-first search/create flow, menus, responder chain, selection behavior, and global activation shortcut;
- external-editor interoperability, if current users still rely on it;
- import/export for supported text and rich-text formats;
- mixed clean-file collections: each note retains its own TXT/Markdown, RTF, or HTML representation, while the collection preference selects only the format for newly created notes;
- the ability to read legacy archives, WAL records, encrypted collections, and historical sync metadata; and
- Mac-native multiwindow, Services, accessibility, printing, and update behavior where still used.

### Do not retain in the modern Mac runtime

- `SingleDatabaseFormat` as an active format for new or already-migrated collections; permanently retain its tested Notational Velocity/nvAlt identification, decryption, WAL recovery, verification, and migration implementation;
- `RBSplitView`; replace its UI with SwiftUI split navigation or supported AppKit split views, then remove the dependency and old split-view nib wiring;
- the old Simplenote/sync-service runtime (`NotationSyncServiceManager`, `SyncSessionController`, service plug-ins, bundled JSON/hashcash support) once fixtures prove historical metadata can be read without activating it;
- Carbon/`FSRef`, Finder notification, catalog-node, volume-UUID, resource-fork, Launch Services, and Carbon hotkey implementations;
- the removed legacy Sparkle updater path and the remaining AutoHyperlinks framework files;
- legacy crypto as the writer for new documents; the machine-specific OpenSSL linkage has been removed, while the legacy decryption behavior required for Notational Velocity/nvAlt migration remains;
- `NSArchiver`/unconstrained unarchiving as the current model format, legacy WebKit UI, synchronous alert/panel APIs, and selector-driven sheet callbacks;
- duplicate legacy preference/about/migration controllers and their nibs after the SwiftUI replacements cover behavior and accessibility; and
- AppKit model types (`NoteObject`, `NotationController`, `AppController`) as dependencies of the shared store, iOS target, App Intents, or Spotlight indexer.

Do not remove any of these paths until fixtures cover the data they read and the replacement has shipped through the relevant migration. The Notational Velocity/nvAlt single-file and encryption compatibility subsystem is an explicit exception to eventual removal: retain it as quarantined migration code instead of leaving two general-purpose writable implementations active indefinitely.

## OS 26 Spotlight Integration

Core Spotlight and `IndexedEntity` do not depend on the OS 27 Notes App Schema. Because OS 26 is the product minimum, ship first-class Spotlight search before the deferred OS 27 Siri work.

Implement the following in shared system-integration sources used by the Mac and iOS applications:

1. **Stable generic entity.** Define `NoteEntity` as an `IndexedEntity` without adopting the OS 27 Notes schema. Use the reconciliation record's permanent note UUID as its identifier; never use a title, filename, path, file-resource identifier, or legacy volume metadata as Spotlight identity.
2. **Entity resolution.** Implement an async entity query that resolves UUIDs through `NoteStore`. It must work without an AppKit controller, foreground window, or live legacy object graph.
3. **Protected semantic index.** Donate eligible note entities to a named, protected Core Spotlight index using indexing keys for title, textual content, tags, and created/modified dates. Associate the canonical file URL where appropriate. Update or delete entries after saves, renames, moves, deletes, conflict resolution, import, migration, and privacy or encryption-state changes.
4. **Opening and searching.** Add an `OpenIntent` and UUID-based deep links so selecting a result opens the exact note even after a rename or move. On macOS 26, expose focused App Intents such as Open Note and Search Notes for direct use from Spotlight; keep mutations out of this first milestone.
5. **Recovery.** Treat the Spotlight index as disposable. Support a full rebuild and system-requested reindexing through the OS 26 Core Spotlight reindexing delegate or index-extension path, while keeping the index out of iCloud Drive and out of the authoritative storage model.
6. **Privacy and native-file indexing.** Make Spiral's Spotlight donation an explicit collection-level setting with per-note exclusion, omit unavailable legacy-encrypted content, and never donate transient plaintext produced during migration. Because canonical `.txt`, `.rtf`, and `.html` files in Finder-visible or iCloud Drive locations may also be indexed independently by macOS, document that disabling Spiral's donation does not by itself guarantee removal of filesystem-generated Spotlight results. Characterize duplicate-result and exclusion behavior before promising complete Spotlight privacy.
7. **Testing.** Add disposable-collection coverage for initial indexing, incremental update and deletion, full rebuild, UUID deep links, rename and move behavior, locked legacy collections, privacy changes, unavailable iCloud files, conflicts, and possible duplication with filesystem-indexed canonical files. Verify results and actions manually in Spotlight on macOS 26.

This OS 26 work establishes the durable Spotlight entity, index, privacy policy, and navigation contract. The OS 27 work extends those same identities rather than replacing or reindexing them under a new identifier scheme.

## Repository Layout and iOS Application

The repository is organized around explicit product and sharing boundaries:

- `Apps/macOS` contains the existing AppKit application, including its sources, resources, supporting files, and macOS-only dependencies;
- `Apps/iOS` contains the universal iPhone and iPad application with a platform-appropriate user interface;
- `Shared/SpiralCore` contains deliberately extracted, tested code with no AppKit or UIKit dependency, including the storage contract, compatibility models, and conflict rules. `Shared/SpiralFeature` contains shared SwiftUI feature state and views plus narrowly isolated conditional `NSTextView`/`UITextView` adapters; and
- `Tests/macOS` contains the macOS XCTest, characterization, and Phase 3 UI suites; `Tests/iOS` contains the mobile UI suite; and shared package tests live beside their packages.

The existing Mac application must not be turned into a multiplatform target merely because an iOS application now exists. Keep separate macOS and iOS app targets while their UI frameworks, life cycles, resources, and platform integrations differ substantially. Share code through narrow core, persistence, compatibility, and service boundaries only after those boundaries are characterized by tests.

The iOS application uses one universal target for both iPhone and iPad. Device-specific layouts may differ, but separate application targets should only be introduced if the products genuinely require different identities, capabilities, or release lifecycles. The macOS and iOS targets should use the same clean note formats, versioned reconciliation-record schema, stable IDs, entity definitions, and `NoteStore` behavior, while each target owns its container access, lifecycle integration, editor adapter, commands, and platform-specific capabilities.

Moving an existing local collection into iCloud Drive is now a required, reversible startup migration with a preflight check, verified copy, retained source backup, progress reporting, and failure recovery. Both Debug and Release use the same application preference domain and entitled iCloud `Documents` directory. Tests must use temporary local directories and controlled coordination doubles rather than a developer's or user's live iCloud Drive data.

On a fresh installation with no persisted notes location and no local notes, Spiral should use the entitled iCloud Drive container's `Documents` directory, adopting an existing Spiral collection there when present. Existing Spiral preferences that name a local collection trigger a verified copy into that same iCloud directory at startup; the original local collection remains as a backup, and a pre-existing iCloud collection requires an explicit merge confirmation. The notes location is not user-configurable in Settings. If Notational Velocity or nvAlt preferences are present on first launch, offer to import that application's notes without copying its preferences. After consent, require the user to select the notes folder; never infer or access a legacy folder from a preference path without that explicit selection. Infer whether the selected collection is a single database or a mixed collection of separate TXT/Markdown, RTF, and HTML files. Import every recognized separate file without converting its representation; the inferred format is only the default for new notes. For a single database, inspect every note's attributed content: export the whole collection as RTF if any note has meaningful user-authored formatting, otherwise export it as TXT. Perform database recovery, decryption, inspection, and clean-file conversion only in a verified temporary copy. Copy and verify the converted collection into Spiral's iCloud container, retain the original legacy folder and its Keychain entry unchanged, clearly warn that an encrypted source becomes ordinary unencrypted files, and never offer a move option. Refuse a non-empty unrelated destination without modifying it; if an existing Spiral collection is already in the iCloud destination, adopt it without overwriting it and leave the selected legacy collection untouched. The current live legacy-controller merge makes a target backup, skips identical UUID matches, and preserves a divergent incoming version as a separate “Merged Copy”; it remains unverified until characterization and failure-recovery tests cover that path.

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

Add a shared scheme and continuous integration that builds and tests Debug and Release configurations. Record the current warning baseline and reject newly introduced warnings.

**Exit criterion:** Critical file formats and behaviours can be changed with automated regression detection.

**Status as of August 2026 — safety net green:** The shared `Notation` scheme contains distinct `NotationSettingsTests` unit and `NotationIntegrationTests` disposable-directory targets in Debug and Release. Golden fixtures and characterization tests protect TXT, RTF, HTML, every legacy encoding-menu entry, filename sanitization and collision handling, labels, extended attributes, search matching/order/highlighting, import/export round trips, historical synchronization metadata without service activation or fixture rewriting, the legacy encrypted-database KDF/compression/cipher envelope, known cipher vectors, and the production WAL's replay/torn-write/wrong-key behavior. Simulated iCloud policy tests distinguish unavailable and delayed files from deletion, preserve concurrent/conflicting edits, and exercise a durable copy transaction interrupted both before and after publication. A built-app smoke mode proves launch against an explicitly validated disposable temporary directory without opening real preferences or notes. GitHub Actions and the local scripts run the complete app build, smoke test, both XCTest targets, and all characterization executables in Debug and Release; the workflow watches the repository's `master` branch. Correcting the prototype of `CreateRandomizedFileName`, declaring the settings action through `AppController`, and replacing a folded constant array removed repeated compiler diagnostics. Clean composed runs now report 841 warnings in both Debug and Release, below the recorded ceiling of 875, and reach every downstream test. Representative full NV/nvAlt database archives are now exercised by the Phase 2 gate; ongoing coordinated multi-client iCloud behavior remains Phase 4 work.

### Phase 2: Establish the Shared Model, Clean Note Codecs, and Reconciliation Store

- Establish a permanent `LegacyCompatibility` boundary for Notational Velocity and nvAlt migration. Move or wrap the existing single-file archive, encryption, passphrase verification, and WAL recovery behavior without changing its accepted inputs.
- Add golden fixtures from representative Notational Velocity and nvAlt versions for unencrypted databases, encrypted databases, changed KDF iteration counts, legacy cipher variants, intact and interrupted WALs, wrong passphrases, damaged archives, separate-file formats, encodings, and historical metadata before extracting model values.
- Add end-to-end migration tests proving that each legacy fixture can be opened or recovered, converted to the new model, verified note-for-note and metadata-for-metadata, and rolled back without modifying the source collection.
- Characterize the transitional first-run importer with those fixtures, including preference isolation, folder-format inference, TXT-versus-RTF selection, per-note preservation in mixed clean-file collections, standard extension enforcement for database exports, source and Keychain preservation, cancellation, wrong passphrases, and failure before iCloud publication.
- Introduce stable UUID identity without changing existing filenames or embedding identity in note contents. During explicit, backed-up migration, create a private per-note reconciliation record outside the public `Documents` directory for each clean note file.
- Define `NoteDomain`, deterministic `.txt`/`.rtf`/`.html` codecs, the private per-note `ReconciliationStore`, conflict values, and the `NoteStore` contract in a shared Swift package. Do not introduce `.spiralnote` packages or an attachment model.
- Preserve authored RTF formatting and HTML markup through edits. Until a format-preserving attributed-text or markup adapter exists, prevent the shared plain-string editor and store from destructively editing those files or require an explicit user-approved conversion to plain text.
- Implement a local temporary-directory store first, with fixture-based import from both the single database and legacy separate files.
- Add local cache/index rebuilding and prove that deleting it loses no user data.
- Specify rollback: the migration retains a verified, byte-for-byte source backup and can export readable clean files without making legacy and modern stores active dual writers. For encrypted sources, require explicit confirmation that the clean destination is plaintext and retain the encrypted backup until the user deliberately removes it.

**Exit criterion:** The shared Swift package can import and, where necessary, WAL-recover all supported Notational Velocity and nvAlt fixtures; save clean per-note files and private reconciliation records; reopen them losslessly; rebuild its local index; and represent conflicts without linking AppKit or UIKit. The source fixtures remain byte-for-byte unchanged.

**Status as of August 2026 — exit criterion met:** `Shared/SpiralCore` provides the platform-neutral `Note` domain with permanent UUID identity, deterministic metadata-free TXT/RTF/HTML codecs, versioned independent reconciliation records, conflict and index-event values, an actor-isolated local `NoteStore`, a disposable rebuildable index, mixed separate-file import, and a copy-only legacy migration transaction with byte-verified retained backup and rollback. Valid source extensions such as `.md`, `.taskpaper`, and `.htm` are preserved through ordinary updates, renames, and moves; only an explicit format change selects the new format's preferred extension. The Mac's archive, encryption, passphrase, and WAL implementation is quarantined behind `LegacyCompatibility/NVLegacyCompatibility.h`. Its production reader now implements `LegacyCompatibilitySource` and feeds extracted note values directly to `LegacyMigrationService`; the shared layer never imports the legacy Objective-C graph.

Sanitized, generated full-archive fixtures cover Notational Velocity plaintext values with MacRoman metadata and reserved filename characters, nvAlt attributed RTF, AES-256 encrypted collections at default and alternate KDF iteration counts, intact and interrupted WAL recovery, wrong passphrases, and damaged archives. AES-256-CBC is the only cipher used by the NV/nvAlt `Notes & Settings` database; the separate older IDEA-CFB Blor input remains protected by an alternate-cipher vector. The built-app migration probe verifies note text, format, tags, dates, UUID bytes, historical synchronization metadata, filenames, encodings, collection/KDF identity, WAL state, and retained Keychain database identity. It also proves source/backup fingerprints match, wrong-passphrase and damaged inputs publish no modern data, and an injected failure after the first imported note removes every modern artifact while retaining the verified source backup. `Scripts/ci/run-phase2.sh` runs these production-reader cases in addition to the shared package and complete Phase 1 suite.

`FormattedTextDocument` tokenizes the textual portion of RTF and HTML while retaining untouched control words, source encodings, tags, attributes, and hidden structural content. It exposes UTF-16 ranges shared with `NSTextView` and `UITextView`, supports insertion, deletion, and inline bold/italic/underline/strikethrough edits, and serializes edits back into the original representation. The AppKit and UIKit adapters render those runs and submit range edits through `NoteContent`; the codec still refuses a bypassing plain-string mutation of a loaded rich file. RTF and HTML fixtures prove edits and formatting survive codec and `LocalNoteStore` save/reopen cycles while font/color tables and surrounding HTML structure remain intact.

### Phase 3: Build a Cross-Platform SwiftUI Vertical Slice

- Add the universal iPhone/iPad target and a SwiftUI feature package.
- Build adaptive collection navigation, search, note list, editor hosting, create/rename/tag/pin/delete, empty/error/download/conflict states, and settings against `NoteStore`.
- Reuse the same feature views in a new Mac shell where behavior is common. Wrap the existing Mac editor and its command bridge rather than translating `LinkingEditor` immediately.
- Use a `UITextView` adapter on iOS if SwiftUI rich-text editing cannot meet the formatting, selection, and performance tests.
- Add UI tests for iPhone compact navigation, iPad split navigation and keyboard use, Mac keyboard-first workflows, VoiceOver, Dynamic Type, multitasking/resizing, state restoration, and large collections.

**Exit criterion:** iPhone, iPad, and Mac can operate on the same disposable local fixture collection through the shared model and store, with no legacy controller dependency in the iOS target.

**Status as of August 2026 — implementation substantial, verification incomplete:** `Shared/SpiralFeature` supplies the common SwiftUI collection shell and `SpiralFeatureModel` over the Phase 2 `NoteStore`, including adaptive navigation/search, list and editor hosting, create/rename/tag/pin/delete, settings, and explicit loading/empty/download/error/conflict states. The universal `SpiralMobile` target supports iPhone and iPad and links only `SpiralCore` and `SpiralFeature`; its local Application Support collection is intentionally transitional until Phase 4. iOS editing uses a Dynamic Type-aware `UITextView` adapter with selection preservation. The opt-in disposable Mac shell reuses the same feature while injecting the established `LinkingEditor` through `NVSettingsBridge`, and never opens a legacy user collection in its test mode. Model tests exercise the complete plain-text mutation workflow and a 1,000-note collection.

RTF and HTML bodies are editable in both shared editor adapters through the format-preserving Phase 2 model. The model and codec retain a refusal guard against direct plain-string mutation, and tests cover the rich editing path separately. The UI-test sources describe compact and split navigation, keyboard commands, accessibility labels, accessibility-size Dynamic Type, rotation/resizing, restoration, and an identical 121-note disposable fixture on iPhone, iPad, and Mac. `Scripts/ci/run-phase3.sh`, however, only performs `build-for-testing` for the mobile and Mac UI targets; it does not execute either suite. Add explicit iPhone, iPad, and Mac test destinations and execute the UI suites before declaring Phase 3 complete.

### Phase 4: Make iCloud Drive the Production Store

- Implement platform adapters for ubiquity-container discovery, download state, coordinated access, file presentation, version conflicts, moves, and deletes.
- Implement the iPhone/iPad document layer through an OS 26-compatible adapter; keep availability-specific implementation out of `NoteStore` and defer adoption of OS 27-only `Document` APIs to Phase 9.
- Implement three-way per-note merges where safe. Plain text may use line-based merging after encoding validation; RTF and HTML require format-aware validation and should preserve both versions whenever an automatic merge could damage formatting or markup.
- Reconcile external edits through coordinated notifications plus full scans at launch and foregrounding. Match by current path first and then by recent paths and content hashes; preserve both when rename-plus-edit, copy-versus-move, or history assignment is ambiguous.
- Handle offline create/edit/delete, duplicate reconciliation UUIDs, external file renames and replacements, eviction, account changes, delayed downloads, note/reconciliation-record arrival in either order, interrupted saves, tombstones, and storage exhaustion.
- Run two-device and three-device fault tests with disposable collections, including edits performed by unrelated text editors and by direct uncoordinated file writes. Never test against the user's live notes directory.
- Replace the transitional publication of the compatibility database with guarded copy-only migration through `NoteStore`, clean per-note files, private per-note reconciliation records, and a durable transaction journal; do not add a move option.

**Exit criterion:** Multiple devices can edit different notes offline and converge, while same-note conflicts remain visible and recoverable and interrupted migration can resume or roll back.

**Progress as of August 2026:** The transitional migration service uses `NSFileCoordinator` for a staged, byte-verified copy, and policy tests model unavailable, delayed, conflicting, and confirmed-deletion states. The Mac also has a live legacy-controller collection merge that makes a target backup, skips identical UUID matches, and preserves a divergent incoming note as a separate “Merged Copy.” This merge is unverified partial progress: add characterization and regression tests for identical and divergent matches, collision behavior, successful publication, backup retention/removal, rollback, and failures before or during the merge. No production `NSFilePresenter`, `NSMetadataQuery`, `NSFileVersion`, multi-device reconciliation, or format-aware three-way merge exists yet.

### Phase 5: Ship OS 26 Spotlight Search

- Implement the OS 26 Spotlight plan above after the shared model and local store boundaries are stable; do not wait for the OS 27 Notes schema.
- Donate title, textual content, tags, and dates through a generic UUID-backed `NoteEntity` to a named, protected Core Spotlight index.
- Route Spotlight results and the Open Note action through UUID-based navigation, initially adapting the Mac's existing UUID-aware URL handling at the application boundary.
- Keep the index current through `NoteStore` index events and support deterministic full rebuilding without reading or writing authoritative note data outside normal coordinated access.
- Add an opt-in collection policy with per-note exclusion, omit locked or unmigrated legacy-encrypted content, and characterize duplicate and exclusion behavior for Finder-visible canonical files.
- Do not adopt the OS 27 Notes schema, `SyncableEntity`, Siri create/update intents, or OS 27-only reindexing APIs in this phase.

**Exit criterion:** On macOS 26, eligible notes from a disposable collection appear in Spotlight by title and content, selecting a result opens the same UUID after rename or move, update/delete/rebuild behavior is covered by automated tests, and the documented privacy policy matches observed Core Spotlight and filesystem-index behavior.

**Progress as of August 2026:** No Core Spotlight, `IndexedEntity`, `NoteEntity`, protected-index, UUID-opening, or Spotlight privacy implementation exists yet.

### Phase 6: Make the Products Reproducible and Distributable

- Enforce the documented macOS 26, iOS 26, and iPadOS 26 minimum across every app, framework/package integration, unit-test target, UI-test target, `Info.plist`, and release artifact.
- Reconcile the deployment target with `Info.plist`; remove PowerPC, i386, and macOS 10.4-era metadata.
- Move hand-maintained build settings into `.xcconfig` files and reduce configuration-specific drift.
- Remove machine-specific header and library search paths.
- Remove tracked `xcuserdata` and verify that developer-specific workspace and signing state remains ignored.
- Verify Debug, Release, Archive, and clean-machine launch workflows.
- Add Developer ID signing, hardened runtime, archive validation, and notarization for Mac, plus App Store/TestFlight signing and archive validation for iPhone and iPad.
- Document the shared iCloud Drive container identifiers, capabilities, and signing requirements for both applications. Keep the guarded first-run copy-and-verify migration separate from the ongoing storage path, which must not be considered production-ready until the storage contract and recovery tests exist.
- Evaluate App Sandbox separately; do not enable it until user-selected folders, security-scoped bookmarks, external editors, and Apple Events have an explicit design.

**Exit criterion:** Release archives install and run on clean supported Mac, iPhone, and iPad devices without Homebrew or developer tools.

**Progress as of August 2026:** The application builds with the current Xcode and macOS SDK, and the macOS target declares the shared `iCloud.farm.poplar.spiral` Documents container with the Finder name “Spiral Notes.” Fresh installations default to this container when it is available. A first run that detects Notational Velocity or nvAlt preferences offers the guarded, folder-selected, copy-only import described above; the manual switch workflow offers Copy or Keep and no longer offers Move. This behavior is provisional: the current Mac controller still publishes and writes its compatibility database alongside the generated note files. Production iCloud enablement must target the per-note store from Phase 4, and iPhone/iPad clients must not share the transitional collection. The container identifier still needs registration and verification with the intended Apple Developer team.

The Homebrew OpenSSL dependency is removed, and unsigned Release builds resolve to universal `arm64`/`x86_64`. The default Debug configuration currently resolves to the active `arm64` architecture only. Project-level `MACOSX_DEPLOYMENT_TARGET` 10.9, x86_64-specific 10.5, and `macosx10.5` SDK overrides remain despite the target-level macOS 26 setting; the mobile app uses iOS 26 while its UI-test target still uses iOS 17. `SpiralCore` still declares iOS 16/macOS 13 and `SpiralFeature` declares iOS 17/macOS 14 in their package manifests. Remove those legacy overrides, align every target and package to OS 26 or later, and make the intended Debug product universal. A developer-specific `Notation.xcodeproj/project.xcworkspace/xcuserdata/g.xcuserdatad/WorkspaceSettings.xcsettings` file is tracked and must be removed while retaining the ignore rule. Broader `.xcconfig` extraction, hardened-runtime, signing, notarization, archive, clean-machine, and live-container verification work remains outstanding.

### Phase 7: Replace Obsolete Dependencies and Deprecated Platform APIs

#### OpenSSL and encryption

The machine-specific Homebrew `libcrypto.3.dylib` dependency has been removed. Legacy AES-256-CBC and MD5 compatibility now use the system CommonCrypto implementation, while Base64 uses Foundation. The Notational Velocity/nvAlt encrypted database and WAL formats remain readable and writable by the quarantined compatibility subsystem.

Golden compatibility vectors now cover the replaced AES-CBC, MD5, and Base64 operations for both universal architectures. Add fixture coverage for complete encrypted databases, PBKDF2, WAL recovery, and legacy IDEA data before changing those paths. Preserve legacy key derivation, passphrase verification, database decryption, and WAL recovery as migration compatibility behavior. Treat this as a compatibility implementation that may be isolated or reimplemented behind tests, not deleted, and do not add a new encryption writer as part of the clean-file migration. Any future encrypted format requires a separate product decision, explicit version marker, backup, migration path, and rollback strategy.

#### AutoHyperlinks

Replace the dynamically loaded AutoHyperlinks framework with Foundation text checking, such as `NSDataDetector`, plus compatibility tests for URLs currently recognized by the editor.

#### Application updates

The bundled legacy Sparkle framework, update feed, signature key, startup loader, and Check for Updates command have been removed. The Mac App Store build must obtain updates exclusively through the Mac App Store. If direct distribution is introduced later, treat adding a separately configured, supported updater as a new distribution decision rather than restoring the legacy framework.

Also modernize one subsystem at a time:

- replace `FSRef`, Carbon fork access, and path buffers with `NSURL`/`URL` and `NSFileManager`/`FileManager` behind a platform-neutral storage interface that supports both local and iCloud Drive roots;
- preserve atomic-write and recovery guarantees while replacing file primitives;
- replace deprecated Launch Services calls with workspace and URL resource APIs;
- replace synchronous and delegate-selector panels with completion-handler APIs;
- replace `NSArchiver` with a versioned, secure archive or an explicitly modeled format;
- replace legacy WebKit views with `WKWebView`, or remove them if the feature is obsolete;
- replace deprecated file notification mechanisms with an appropriate modern observer; and
- replace `RBSplitView` through the cross-platform SwiftUI shell, using `NSSplitViewController` only where a Mac-specific AppKit split remains necessary;
- retain the global-hotkey behavior while replacing the Carbon `PTHotKeys` implementation with supported event APIs; and
- retain external-editor behavior while replacing the bundled ODBEditor implementation or quarantining it as Mac-only.

Each replacement should include tests and land independently where practical.

**Exit criterion:** The products contain no unsupported architecture slices, obsolete executable frameworks, host-specific dynamic-library references, or normal paths that call unsupported Carbon or deprecated framework APIs.

**Progress as of August 2026:** A few isolated UI and text-detection paths have been modernized, but the main file, persistence, import, and application-control paths still use Carbon, `FSRef`, legacy archive/WebKit APIs, and extensive dynamic selector dispatch. The phase remains largely outstanding.

Editor URL detection uses `NSDataDetector` with characterization coverage, and AutoHyperlinks is no longer referenced by the Xcode project, although its framework files remain in the repository. Legacy Sparkle, its update metadata, and its update command are removed. Homebrew OpenSSL linkage is removed, with universal compatibility vectors covering the substituted AES-CBC, MD5, and Base64 implementations. The direct Simplenote network implementation (`SimplenoteSession`, `SimplenoteEntryCollector`, and `SyncResponseFetcher`) is also removed, and service discovery returns no available remote services. Inactive `NotationSyncServiceManager`, `SyncSessionController`, `SyncServiceSessionProtocol`, bundled JSON/hashcash sources, and related call sites remain compiled; remove them only after compatibility tests continue to prove that historical synchronization metadata loads without activating a service.

### Phase 8: Quarantine and Shrink the Legacy Mac Core

- Add nullability annotations and lightweight generics to headers at subsystem boundaries.
- Replace avoidable `performSelector:` calls with protocols, blocks, or direct typed calls.
- Convert isolated leaf classes to ARC first.
- Progressively enable ARC, temporarily compiling resistant legacy files with `-fno-objc-arc` if necessary.
- Run the static analyzer and memory diagnostics on persistence, synchronization, and editor workflows.

ARC migration should be separate from Swift migration so memory-management regressions are easier to identify.

**Exit criterion:** Most application code uses ARC and exposes sufficiently typed interfaces for safe Swift interoperability.

**Progress as of August 2026:** SwiftUI Settings and About windows are active on Mac. The Settings window retains the legacy workflow view behind a narrow adapter so established behaviors continue while the visible UI is modernized. The Objective-C boundaries in `SettingsBridge`, `LegacyNotePolicies`, `NVLegacyCompatibility`, and `URLDetection` now use nullability, and selected collection-valued APIs use lightweight generics. This is meaningful incremental interface-strengthening progress. The wider application remains predominantly manual-memory-managed Objective-C; systematic ARC conversion, broad protocol/direct-call replacement, static analysis, memory diagnostics, and typed cleanup of the large legacy controllers remain outstanding.

Once tests, ARC, and service boundaries are established, review the large core classes. Split responsibilities before deciding whether to migrate them to Swift. A smaller Objective-C façade over tested Swift services may be safer than translating a large class line for line.

Delete obsolete compatibility paths, nibs, frameworks, and source files only after their replacements have shipped and migration compatibility has been verified. Do not delete the permanently supported Notational Velocity/nvAlt single-file, encryption, or WAL migration capability; only isolate or replace its implementation behind equivalent fixtures.

Do not port `NoteObject`, `NotationController`, `AppController`, or `LinkingEditor` to iOS. Their responsibilities must move into `NoteDomain`, `NoteStore`, feature state, and platform adapters. On Mac, retain only the thin behavior-specific pieces that remain valuable after the shared stack takes ownership.

**Exit criterion:** Remaining Objective-C/C exists intentionally as a Mac UI adapter or legacy compatibility reader, and the iOS application, shared store, Spotlight indexer, and App Intents have no dependency on it.

### Phase 9: Add OS 27 Document APIs, Notes Schema, App Intents, and Siri

- Revalidate the OS 27 APIs against the final SDK while retaining macOS 26, iOS 26, and iPadOS 26 compatibility.
- Extend or replace the OS 26 mobile document adapter with availability-isolated OS 27 `Document`/`ReadableDocument`/`WritableDocument` support without changing the `NoteStore` contract.
- Extend the Phase 5 `NoteEntity`, protected index, UUID navigation, and privacy policy according to the OS 27 plan below; do not create a parallel entity or change stable identifiers.
- Add `SyncableEntity` and the Notes schema, then schema create/update intents, onscreen awareness, and content transfer.
- Keep intents thin; all reads and mutations go through `NoteStore` authorization and conflict rules.
- Retain OS 26 Spotlight and document-adapter coverage as compatibility suites. Test that OS 27 additions do not duplicate entries, break existing result navigation, or change canonical note identity.

#### OS 27 system-integration plan

The OS 27 SDK adds a first-class Notes App Schema. Siri integration must build on the OS 26 `NoteEntity` and Spotlight index. Revalidate these APIs against the final SDK before shipping.

1. **Schema and cross-device identity.** Apply `@AppEntity(schema: .notes.note)` to the existing `NoteEntity` and conform it to `SyncableEntity`. Map the schema's name, attributed content, tags, pinned state, dates, and folder properties to the shared model; leave its optional attachment representation empty because Spiral has no attachment model. Preserve the UUID identifiers already donated on OS 26.
2. **Enhanced reindexing.** Add `IndexedEntityQuery` support for selected or complete entity reindexing while continuing to use the same protected Core Spotlight index and `NoteStore` resolution boundary.
3. **Navigation and onscreen awareness.** Add `ShowInAppSearchResultsIntent` and annotate the selected editor and visible note rows using `appEntityIdentifier`/`appEntityUIElements`; AppKit can annotate responder objects, so this does not require replacing the Mac editor first.
4. **Note actions.** Adopt the `.notes.createNote` and `.notes.updateNote` intent schemas. Route both through the same tested `NoteStore` commands used by the UI. Use confirmation and authentication policies for mutations; the default App Intent policy permits locked-device execution, which is inappropriate for private notes.
5. **Privacy and encryption.** Extend the OS 26 Spotlight policy to Siri and Apple Intelligence. Never place legacy encryption keys or transient decrypted migration content in intent parameters, donations, logs, or identifiers.
6. **Cross-device and shared-note semantics.** `SyncableEntity` requires a device-independent identifier so Siri can carry entity references between devices. If note sharing is later added, adopt `OwnershipProvidingEntity` so the system can request appropriate confirmation before changing shared content.
7. **Testing.** Add App Intents Testing coverage for schema properties, create/update behavior, authentication, view annotations, deleted or unavailable documents, and conflict states. Then test progressively in Shortcuts and Siri on physical devices using disposable iCloud accounts and collections, while retaining the OS 26 Spotlight regression suite.

App Intents and Spotlight are the route for exposing the app's notes and actions to Siri. The Foundation Models framework and its OS 27 `SpotlightSearchTool` are a separate, optional route for an in-app “ask my notes” experience. If added later, it should query the same protected Spotlight index and return cited note identities through `NoteStore`; it is not a substitute for App Entities, schema intents, or Siri integration.

**Exit criterion:** The OS 27 document adapter passes compatibility tests without dropping OS 26 support; automated App Intents tests pass; existing OS 26 Spotlight entries continue to open reliably; private notes remain excluded according to the documented policy; and create/update commands work through Siri on disposable OS 27 test devices.

**Progress as of August 2026:** No OS 27 `Document` adapter, Notes App Schema, `SyncableEntity`, Siri intent, onscreen-awareness, or App Intents Testing implementation exists yet.

## Swift Decision

There is meaningful value in Swift, particularly from:

- null safety and stronger value types;
- typed errors and serialization;
- structured concurrency;
- easier use of current Apple frameworks and Swift packages;
- improved testability when code is moved into small services; and
- a clearer path for future contributors.

A wholesale Swift rewrite is not recommended. It would create substantial regression and data-loss risk while leaving the actual platform, dependency, packaging, and test problems to be solved separately. The preferred approach is to make Swift the destination for new and deliberately extracted code while allowing proven Objective-C and C code to remain until replacing it has a measurable benefit.

## Current Prioritized Backlog

1. **Completed August 2026:** Restored the Phase 1 safety net to green. The latest clean composed runs report 841 warnings in both Debug and Release against the ceiling of 875, retain the corrected `master` push trigger, and reach the app smoke test, both XCTest targets, and every characterization executable.
2. **Completed August 2026:** Added sanitized representative full Notational Velocity/nvAlt archives for plaintext, attributed RTF, encrypted default/alternate-KDF, intact/interrupted WAL, wrong-passphrase, damaged, MacRoman, filename, and historical-sync cases; retained the separate IDEA-CFB compatibility vector. The production Objective-C reader now feeds `LegacyMigrationService`, and the Phase 2 gate verifies note/metadata values, source immutability, byte-identical backup, Keychain identity preservation, and rollback after an injected partial import.
3. **Completed August 2026:** Replaced the shared plain-string RTF/HTML representation with a lossless token document, UTF-16 AppKit/UIKit editor adapters, and format-preserving serializers. Fixture-driven insertion, deletion, and inline-format tests prove surrounding RTF font/color controls and HTML structure survive codec and store save/reopen cycles; the codec/store refusal remains as a guard against bypassing the rich model with a plain-string mutation.
4. Execute, rather than merely compile, the Phase 3 UI suites on explicit iPhone, iPad, and Mac destinations. Cover compact/split navigation, keyboard workflows, accessibility, Dynamic Type, rotation/resizing, restoration, and the shared disposable collection.
5. Characterize the existing live legacy collection merge, including identical and divergent UUID matches, collisions, backup lifecycle, successful publication, rollback, and injected failures. Then implement the Phase 4 OS 26-compatible iCloud document adapters, reconciliation, conflict handling, durable migration journal, and two-/three-device fault tests before enabling a shared production collection.
6. Implement the Phase 5 OS 26 UUID-backed `NoteEntity`, protected Core Spotlight index, deep-link/open behavior, privacy controls, incremental updates, full rebuild, and filesystem-duplicate characterization.
7. Complete Phase 6 build hygiene: remove macOS 10.5/10.9 and legacy SDK overrides; align all app targets, test targets, and package manifests to macOS/iOS/iPadOS 26 or later; make the intended Debug product universal; remove tracked `xcuserdata`; expand `.xcconfig` ownership; and verify unsigned builds, signed archives, hardened runtime, notarization, TestFlight/App Store signing, and clean-machine launch.
8. Complete Phase 7 removals one subsystem at a time: delete the unused AutoHyperlinks files; remove inactive Simplenote/sync/JSON/hashcash scaffolding after compatibility verification; and replace Carbon/`FSRef`, Launch Services, synchronous panels, unsafe archives, legacy WebKit, file notifications, RBSplitView, PTHotKeys, and ODBEditor with tested supported boundaries.
9. Continue Phase 8 with typed protocols and direct calls, isolated ARC leaf conversions, broader nullability/generics, static analysis, and memory diagnostics before shrinking the large legacy controllers.
10. After Phases 5–8 establish stable OS 26 behavior, implement Phase 9 OS 27 document APIs, Notes schema, `SyncableEntity`, Siri create/update actions, onscreen awareness, and App Intents Testing without changing UUIDs or dropping OS 26 compatibility.

## Definition of Done for Modernization Changes

A modernization change is complete when:

- existing user data and compatibility formats remain readable;
- supported Notational Velocity and nvAlt single-file, encryption, and WAL fixtures remain migratable through the permanently retained legacy compatibility subsystem;
- local and per-note iCloud Drive-backed collections preserve offline, coordination, conflict, and recovery behavior without undocumented migration or rewriting; the documented automatic unencrypted single-database-to-RTF launch upgrade is the current transitional exception;
- stable note IDs survive app-coordinated rename, move, device changes, and conflict recovery; externally ambiguous rename-plus-edit and copy-versus-move cases preserve both notes instead of claiming false identity certainty;
- new or changed behaviour is covered by automated tests;
- all configurations build without new warnings;
- the application launches against both representative fixtures and a clean data directory;
- release packaging remains self-contained and signable;
- migration and rollback behaviour is documented where data changes are involved;
- a completed modern migration leaves only canonical note files in public iCloud `Documents`, with app metadata and reconciliation state outside that directory;
- Spotlight, App Intents, and Siri exposure obey the documented privacy, legacy-encryption, authentication, and deletion policy; and
- obsolete code or dependencies replaced by the change are removed rather than left as an untested parallel path.

## References

- [Apple: Migrating Objective-C Code to Swift](https://developer.apple.com/documentation/swift/migrating-your-objective-c-code-to-swift)
- [Apple: Importing Objective-C into Swift](https://developer.apple.com/documentation/swift/importing-objective-c-into-swift)
- [Apple: AppKit integration with SwiftUI](https://developer.apple.com/documentation/swiftui/appkit-integration)
- [Apple: Creating a document-based app with the OS 27 `Document` protocol](https://developer.apple.com/documentation/swiftui/creating-a-document-based-app)
- [Apple: Updating an existing document-based app for OS 27](https://developer.apple.com/documentation/swiftui/updating-your-document-based-app)
- [Apple: Building rich SwiftUI text experiences](https://developer.apple.com/documentation/swiftui/building-rich-swiftui-text-experiences)
- [Apple: Elevate your app's text experience with TextKit (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/370/)
- [Apple: Notes App Schema domain](https://developer.apple.com/documentation/appintents/app-schema-domain-notes)
- [Apple: OS 27 note entity schema](https://developer.apple.com/documentation/appintents/appschema/notesentity/note)
- [Apple: Apple Intelligence and Siri AI](https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai)
- [Apple: Develop for Shortcuts and Spotlight with App Intents (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/260/)
- [Apple: Making App Entities available in Spotlight](https://developer.apple.com/documentation/appintents/making-app-entities-available-in-spotlight)
- [Apple: Providing contextual cues to Apple Intelligence and Siri](https://developer.apple.com/documentation/appintents/providing-contextual-cues-to-apple-intelligence-and-siri)
- [Apple: `SyncableEntity`](https://developer.apple.com/documentation/appintents/syncableentity)
- [Apple: App Intents Testing](https://developer.apple.com/documentation/appintentstesting)
- [Apple: Adding content to protected Core Spotlight indexes](https://developer.apple.com/documentation/corespotlight/adding-your-app-s-content-to-spotlight-indexes)
- [Apple: Deciding whether CloudKit is right for your app](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app)
- [Apple: Syncing SwiftData model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [Apple: Synchronizing documents in the iCloud environment](https://developer.apple.com/documentation/uikit/synchronizing-documents-in-the-icloud-environment)
- [Apple: `NSFilePresenter`](https://developer.apple.com/documentation/foundation/nsfilepresenter)
- [Apple: `NSFileVersion`](https://developer.apple.com/documentation/foundation/nsfileversion)
- [Apple: Designing for Documents in iCloud](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForDocumentsIniCloud.html)
- [Apple: iCloud fundamentals and SQLite store-file guidance](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/iCloudFundametals.html)
- [Apple: Configuring the Hardened Runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime/)
