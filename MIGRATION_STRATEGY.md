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
- gives every app-managed note a stable, cross-device identity suitable for iCloud conflict handling, deep links, Spotlight, App Intents, and Siri, while preserving both files when an external rename-plus-edit makes identity ambiguous;
- exposes only user-approved note content to Spotlight, Apple Intelligence, and Siri, with unavailable legacy-encrypted content and privacy-excluded notes omitted by default;
- no longer depends on unsupported Carbon APIs or obsolete binary frameworks;
- has automated coverage for important behaviour and compatibility formats; and
- uses Swift for new and substantially refactored code where Swift improves safety and clarity.

## Current Assessment

The project contains approximately 40,000 lines of Objective-C and C. Its largest and most interconnected classes include `NoteObject`, `AppController`, `NotationController`, `LinkingEditor`, and `NotesTableView`. Phase 1 now provides separate XCTest unit and disposable-directory integration targets plus focused characterization executables for the critical legacy seams. These tests establish regression detection for the current formats and behavior; Phase 2 must expand them with representative end-to-end Notational Velocity and nvAlt collections before extracting the new shared storage boundary.

The main modernization risks are not caused by Objective-C itself. They are:

- manual reference counting throughout the application;
- Carbon and `FSRef`-based file handling;
- extensive dynamic selector use and weakly typed interfaces;
- deprecated synchronous AppKit panels and alerts;
- old archive, WebKit, Launch Services, and notification APIs;
- obsolete AutoHyperlinks framework files that are no longer part of the target;
- legacy cryptographic compatibility code that must remain isolated and fixture-tested;
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
8. **Design identity before synchronization.** Titles and filenames are mutable presentation, not note identity. Assign a permanent UUID before iCloud, deep-link, or App Entity work.
9. **Keep cloud data and local indexes separate.** Rebuildable search indexes, thumbnails, caches, and local database accelerators must not be synchronized as user documents.
10. **Keep canonical note files clean.** New notes are ordinary attachment-free plain text, RTF, or HTML files. Do not embed Spiral UUIDs, revision records, tags, application state, or other private metadata in their content.

## Recommended Target Architecture

The product should become a shared Swift domain and storage system with separate SwiftUI application shells. Platform-specific text views and integrations remain behind narrow adapters:

- **NoteDomain (shared Swift package):** `Sendable` value types for notes, tags, folders, revisions, and conflicts. Attachments are not part of the product model. An app-managed note has a permanent UUID that does not change when its title, filename, or folder changes.
- **NoteFileCodec (shared Swift package):** deterministic, fixture-tested readers and writers for ordinary `.txt`, `.rtf`, and `.html` files. UTF-8 plain text is the preferred format for new notes. RTF is limited to textual rich formatting, and HTML must be self-contained textual markup with no linked assets, embedded media, or companion resource directories. The canonical file contains only user content and the syntax required by its declared format; it contains no Spiral manifest or embedded application metadata. The legacy Notational Velocity/nvAlt collection database remains a migration input only, not a competing live store or a format for new exports.
- **ReconciliationStore (shared Swift package):** private, per-note reconciliation records stored outside the public `Documents` directory of Spiral's iCloud ubiquity container. Local-only collections use the equivalent private Application Support location and migrate their records when the collection explicitly moves to iCloud. A record maps a UUID to its current and recent relative paths, raw-content hash, last common revision, bounded merge-base snapshot, app-only metadata, and tombstone state. Use one independently replaceable record directory per note rather than one global manifest or database file. The visible note must remain usable if this state is unavailable; loss of reconciliation state may lose app-only metadata or require conservative identity recovery, but must never make note content unreadable.
- **NoteStore (shared Swift package):** an actor-isolated storage contract for enumeration, lookup by stable ID, search, create/update/delete, coordinated saves, change observation, conflict representation, migration, and index events. It must not expose `AppKit`, `UIKit`, SwiftUI scene state, or Objective-C model objects.
- **Document adapters:** use the OS 27 SwiftUI `Document`/`ReadableDocument`/`WritableDocument` APIs for new iPhone and iPad document access when OS 27 is the deployment minimum. These APIs provide async URL access, snapshots, progress, and a framework-provided file coordinator. If older systems remain supported, isolate `FileDocument`/`ReferenceFileDocument` fallback code in the adapter because Apple no longer recommends those protocols for new document types on OS 27.
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

The existing single-file format and its encryption implementation are legacy compatibility formats for people migrating from Notational Velocity or nvAlt. Retain the code required to identify, open, verify, decrypt, recover, and migrate those collections for as long as the product supports those users. Existing users must be able to migrate a verified copy to per-note documents without losing note content, metadata, or WAL-recoverable changes, while retaining the encrypted source backup until they deliberately remove it. Do not use the legacy format for newly created collections, do not continue writing it after a user completes migration to the modern store, and do not silently convert it merely because it was read successfully.

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
6. A folder without the database is inferred from its visible note extensions. TXT-family extensions (`txt`, `text`, `utf8`, and `taskpaper`), RTF, and HTML-family extensions (`html` and `htm`) are recognized. A folder with no recognized note files or a mixture of storage families is rejected rather than guessed.
7. For an encrypted database, the retained compatibility code obtains the passphrase and decrypts only the disposable copy. The confirmation text warns that the destination files are ordinary unencrypted files. Disabling encryption in the working copy neither modifies the original archive nor removes its legacy Keychain item.
8. Spiral copies and byte-verifies the converted working collection into its iCloud `Documents` directory, switches to that verified destination, and deletes the disposable copy. The original selected folder is always retained. There is no move option. The manual “switch to iCloud” workflow is also copy-or-keep only.

This is a transitional bridge, not the Phase 4 production store. The current Mac runtime still requires `Notes & Settings` and may retain legacy journal or metadata state alongside the generated per-note files; it continues to use that compatibility database as part of its live object graph. Consequently, the present iCloud folder is not yet the clean, metadata-free canonical store and must not be opened concurrently by the future iPhone/iPad clients. Phase 2 must move migration output into `NoteStore`, clean codecs, and private reconciliation records, and Phase 4 must publish only canonical note files in the public `Documents` directory before multi-client iCloud use is enabled.

## UI Direction and Mac Retention Decisions

SwiftUI moves onto the critical path because the iPhone, iPad, and Mac products need shared navigation, note list, search, selection, command models, sheets, and system-context annotations. The first iOS application should not wait for a complete Objective-C or ARC migration.

The first vertical slice should show the same temporary fixture collection in a SwiftUI `NavigationSplitView` on iPad and Mac and a compact navigation stack on iPhone. It should support search, open, create, edit, save, rename, tag, delete, and conflict display through `NoteStore`. The Mac can host its existing editor inside this shell while the iOS version uses a new editor adapter.

Do not make a source-level SwiftUI view automatically shared just because it compiles on every platform. Share feature state, commands, and views where interaction is genuinely common; use platform-specific toolbars, menus, keyboard commands, windowing, and text-editor wrappers.

Apple's current TextKit guidance continues to recommend `NSTextView` and `UITextView` for convenient, powerful rich-text editors, including when they are wrapped in SwiftUI. SwiftUI `TextEditor` with `AttributedString` is a credible iOS editor candidate, but it must pass characterization tests for links, indentation, find, selection, undo, input methods, accessibility, large notes, and the Mac's command semantics before replacing the AppKit editor.

### Retain as behavior, but replace the implementation

- the Mac's keyboard-first search/create flow, menus, responder chain, selection behavior, and global activation shortcut;
- external-editor interoperability, if current users still rely on it;
- import/export for supported text and rich-text formats;
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

Core Spotlight and `IndexedEntity` do not depend on the OS 27 Notes App Schema. If OS 26 is the product minimum, ship first-class Spotlight search in the OS 26 timeframe rather than holding all system integration for the OS 27 Siri work.

Implement the following in a Swift package shared by the Mac and future iOS applications:

1. **Stable generic entity.** Define `NoteEntity` as an `IndexedEntity` without adopting the OS 27 Notes schema. Use the reconciliation record's permanent note UUID as its identifier; never use a title, filename, path, file-resource identifier, or legacy volume metadata as Spotlight identity.
2. **Entity resolution.** Implement an async entity query that resolves UUIDs through `NoteStore`. It must work without an AppKit controller, foreground window, or live legacy object graph.
3. **Protected semantic index.** Donate eligible note entities to a named, protected Core Spotlight index using indexing keys for title, textual content, tags, and created/modified dates. Associate the canonical file URL where appropriate. Update or delete entries after saves, renames, moves, deletes, conflict resolution, import, migration, and privacy or encryption-state changes.
4. **Opening and searching.** Add an `OpenIntent` and UUID-based deep links so selecting a result opens the exact note even after a rename or move. On macOS 26, expose focused App Intents such as Open Note and Search Notes for direct use from Spotlight; keep mutations out of this first milestone.
5. **Recovery.** Treat the Spotlight index as disposable. Support a full rebuild and system-requested reindexing through the OS 26 Core Spotlight reindexing delegate or index-extension path, while keeping the index out of iCloud Drive and out of the authoritative storage model.
6. **Privacy and native-file indexing.** Make Spiral's Spotlight donation an explicit collection-level setting with per-note exclusion, omit unavailable legacy-encrypted content, and never donate transient plaintext produced during migration. Because canonical `.txt`, `.rtf`, and `.html` files in Finder-visible or iCloud Drive locations may also be indexed independently by macOS, document that disabling Spiral's donation does not by itself guarantee removal of filesystem-generated Spotlight results. Characterize duplicate-result and exclusion behavior before promising complete Spotlight privacy.
7. **Testing.** Add disposable-collection coverage for initial indexing, incremental update and deletion, full rebuild, UUID deep links, rename and move behavior, locked legacy collections, privacy changes, unavailable iCloud files, conflicts, and possible duplication with filesystem-indexed canonical files. Verify results and actions manually in Spotlight on macOS 26.

This OS 26 work establishes the durable Spotlight entity, index, privacy policy, and navigation contract. The OS 27 work extends those same identities rather than replacing or reindexing them under a new identifier scheme.

## OS 27 Apple Intelligence and Siri Preparation

The OS 27 SDK adds a first-class Notes App Schema. Siri integration should therefore build on the OS 26 `NoteEntity` and Spotlight index. These APIs are currently beta and must be revalidated against the final SDK before shipping.

Implement the following in the shared system-integration package:

1. **Schema and cross-device identity.** Apply `@AppEntity(schema: .notes.note)` to the existing `NoteEntity` and conform it to `SyncableEntity`. Map the schema's name, attributed content, tags, pinned state, dates, and folder properties to the shared model; leave its optional attachment representation empty because Spiral has no attachment model. Preserve the UUID identifiers already donated on OS 26.
2. **Enhanced reindexing.** Add `IndexedEntityQuery` support for selected or complete entity reindexing while continuing to use the same protected Core Spotlight index and `NoteStore` resolution boundary.
3. **Navigation and onscreen awareness.** Add `ShowInAppSearchResultsIntent` and annotate the selected editor and visible note rows using `appEntityIdentifier`/`appEntityUIElements`; AppKit can annotate responder objects, so this does not require replacing the Mac editor first.
4. **Note actions.** Adopt the `.notes.createNote` and `.notes.updateNote` intent schemas. Route both through the same tested `NoteStore` commands used by the UI. Use confirmation and authentication policies for mutations; the default App Intent policy permits locked-device execution, which is inappropriate for private notes.
5. **Privacy and encryption.** Extend the OS 26 Spotlight policy to Siri and Apple Intelligence. Never place legacy encryption keys or transient decrypted migration content in intent parameters, donations, logs, or identifiers.
6. **Cross-device and shared-note semantics.** `SyncableEntity` requires a device-independent identifier so Siri can carry entity references between devices. If note sharing is later added, adopt `OwnershipProvidingEntity` so the system can request appropriate confirmation before changing shared content.
7. **Testing.** Add App Intents Testing coverage for schema properties, create/update behavior, authentication, view annotations, deleted or unavailable documents, and conflict states. Then test progressively in Shortcuts and Siri on physical devices using disposable iCloud accounts and collections, while retaining the OS 26 Spotlight regression suite.

App Intents and Spotlight are the route for exposing the app's notes and actions to Siri. The Foundation Models framework and its OS 27 `SpotlightSearchTool` are a separate, optional route for an in-app “ask my notes” experience. If added later, it should query the same protected Spotlight index and return cited note identities through `NoteStore`; it is not a substitute for App Entities, schema intents, or Siri integration.

## Repository Layout and Future iOS Application

The repository is organized around explicit product and sharing boundaries:

- `Apps/macOS` contains the existing AppKit application, including its sources, resources, supporting files, and macOS-only dependencies;
- `Apps/iOS` is reserved for a future universal iPhone and iPad application with a platform-appropriate user interface;
- `Shared` is reserved for deliberately extracted, tested code that has no AppKit or UIKit dependency, including the storage contract, compatibility models, and conflict rules shared by the two applications; and
- `Tests/macOS` contains the existing macOS XCTest and characterization suites. Future shared and iOS tests should be placed beside it at the equivalent boundary.

The existing application must not be treated as a multiplatform target merely because an iOS application is planned. Keep separate macOS and iOS app targets while their UI frameworks, life cycles, resources, and platform integrations differ substantially. Share code through narrow core, persistence, compatibility, and service boundaries only after those boundaries are characterized by tests.

The future iOS application should use one universal target for both iPhone and iPad. Device-specific layouts may differ, but separate application targets should only be introduced if the products genuinely require different identities, capabilities, or release lifecycles. The macOS and iOS targets should use the same clean note formats, versioned reconciliation-record schema, stable IDs, entity definitions, and `NoteStore` behavior, while each target owns its container access, lifecycle integration, editor adapter, commands, and platform-specific capabilities.

Moving an existing local collection into iCloud Drive must be an explicit, reversible migration with a preflight check, backup, progress reporting, failure recovery, and a documented rollback path. Tests and development builds must use temporary local directories and controlled coordination doubles rather than a developer's or user's live iCloud Drive data.

On a fresh installation with no persisted notes location and no local notes, Spiral should use the entitled iCloud Drive container's `Documents` directory by default, adopting an existing Spiral collection there when present and falling back to the local Application Support directory when iCloud Drive is unavailable. If Notational Velocity or nvAlt preferences are present on first launch, offer to import that application's notes without copying its preferences. After consent, require the user to select the notes folder; never infer or access a legacy folder from a preference path without that explicit selection. Infer whether the selected collection is a single database or a consistent family of separate TXT, RTF, or HTML files. Import an existing separate-file collection in its detected format. For a single database, inspect every note's attributed content: export the whole collection as RTF if any note has meaningful user-authored formatting, otherwise export it as TXT. Perform database recovery, decryption, inspection, and clean-file conversion only in a verified temporary copy. Copy and verify the converted collection into Spiral's iCloud container, retain the original legacy folder and its Keychain entry unchanged, clearly warn that an encrypted source becomes ordinary unencrypted files, and never offer a move option. Refuse a non-empty unrelated destination without modifying it; if an existing Spiral collection is already in the iCloud destination, adopt it without overwriting it and leave the selected legacy collection untouched. Manual migration of an existing Spiral collection is likewise copy-only and keeps the original folder as a backup. A future merge must preserve divergent versions rather than silently overwriting either collection.

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

**Completed in August 2026:** The shared `Notation` scheme now contains distinct `NotationSettingsTests` unit and `NotationIntegrationTests` disposable-directory targets in Debug and Release. Golden fixtures and characterization tests protect TXT, RTF, HTML, every legacy encoding-menu entry, filename sanitization and collision handling, labels, extended attributes, search matching/order/highlighting, import/export round trips, historical synchronization metadata without service activation or fixture rewriting, the legacy encrypted-database KDF/compression/cipher envelope, known cipher vectors, and the production WAL's replay/torn-write/wrong-key behavior. Simulated iCloud policy tests distinguish unavailable and delayed files from deletion, preserve concurrent/conflicting edits, and exercise a durable copy transaction interrupted both before and after publication. A built-app smoke mode proves launch against an explicitly validated disposable temporary directory without opening real preferences or notes. GitHub Actions runs the complete app build, smoke test, both XCTest targets, and all characterization executables in Debug and Release; a clean-build baseline of 875 repository warnings per configuration rejects increases. Representative full NV/nvAlt database archives, live legacy-model merge transactions, and ongoing coordinated multi-client iCloud behavior remain Phase 2 and Phase 4 work rather than gaps in the Phase 1 regression boundary.

### Phase 2: Establish the Shared Model, Clean Note Codecs, and Reconciliation Store

- Establish a permanent `LegacyCompatibility` boundary for Notational Velocity and nvAlt migration. Move or wrap the existing single-file archive, encryption, passphrase verification, and WAL recovery behavior without changing its accepted inputs.
- Add golden fixtures from representative Notational Velocity and nvAlt versions for unencrypted databases, encrypted databases, changed KDF iteration counts, legacy cipher variants, intact and interrupted WALs, wrong passphrases, damaged archives, separate-file formats, encodings, and historical metadata before extracting model values.
- Add end-to-end migration tests proving that each legacy fixture can be opened or recovered, converted to the new model, verified note-for-note and metadata-for-metadata, and rolled back without modifying the source collection.
- Characterize the transitional first-run importer with those fixtures, including preference isolation, folder-format inference, TXT-versus-RTF selection, standard extension enforcement, source and Keychain preservation, cancellation, wrong passphrases, mixed-format refusal, and failure before iCloud publication.
- Introduce stable UUID identity without changing existing filenames or embedding identity in note contents. During explicit, backed-up migration, create a private per-note reconciliation record outside the public `Documents` directory for each clean note file.
- Define `NoteDomain`, deterministic `.txt`/`.rtf`/`.html` codecs, the private per-note `ReconciliationStore`, conflict values, and the `NoteStore` contract in a shared Swift package. Do not introduce `.spiralnote` packages or an attachment model.
- Implement a local temporary-directory store first, with fixture-based import from both the single database and legacy separate files.
- Add local cache/index rebuilding and prove that deleting it loses no user data.
- Specify rollback: the migration retains a verified, byte-for-byte source backup and can export readable clean files without making legacy and modern stores active dual writers. For encrypted sources, require explicit confirmation that the clean destination is plaintext and retain the encrypted backup until the user deliberately removes it.

**Exit criterion:** The shared Swift package can import and, where necessary, WAL-recover all supported Notational Velocity and nvAlt fixtures; save clean per-note files and private reconciliation records; reopen them losslessly; rebuild its local index; and represent conflicts without linking AppKit or UIKit. The source fixtures remain byte-for-byte unchanged.

**Completed in August 2026:** `Shared/SpiralCore` now provides the platform-neutral `Note` domain with permanent UUID identity, deterministic metadata-free TXT/RTF/HTML codecs, versioned independent reconciliation records, conflict and index-event values, an actor-isolated local `NoteStore`, a disposable rebuildable index, separate-file import, and a copy-only legacy migration transaction with byte-verified retained backup and rollback. The Mac's archive, encryption, passphrase, and WAL implementation is quarantined behind `LegacyCompatibility/NVLegacyCompatibility.h`; it operates only on a verified disposable copy and feeds clean files/value snapshots across `LegacyCompatibilitySource`, without exposing AppKit-era model objects to the package. Encrypted imports require explicit confirmation that the destination is ordinary plaintext and preserve both the encrypted source and its Keychain item. Golden NV/nvAlt boundary snapshots plus the retained Phase 1 cipher, KDF, archive-metadata, encoding, and intact/torn/wrong-key WAL fixtures cover the accepted compatibility matrix. Package tests delete and rebuild the complete local index, reopen files and reconciliation records losslessly, preserve UUIDs across moves, retain metadata, represent conflicts, refuse mixed formats and unsafe paths, and prove rollback/source immutability entirely in disposable directories. `Scripts/ci/run-phase2.sh` runs this package suite and the full existing application compatibility suite in Debug and Release.

### OS 26 Milestone: Ship Spotlight Search on Mac

- Implement the OS 26 Spotlight plan above as soon as `NoteStore` and permanent reconciliation UUIDs are available; it may proceed alongside the Phase 3 UI work and must not wait for the OS 27 Notes schema.
- Donate title, textual content, tags, and dates through a generic `NoteEntity` to a named, protected Core Spotlight index.
- Route Spotlight results and the Open Note action through UUID-based navigation, initially adapting the Mac's existing UUID-aware URL handling at the application boundary.
- Keep the index current through `NoteStore` index events and support deterministic full rebuilding without reading or writing a user's authoritative note data outside normal coordinated access.
- Add an opt-in collection policy with per-note exclusion, omit locked or unmigrated legacy-encrypted content, and characterize duplicate and exclusion behavior for Finder-visible canonical files.
- Do not adopt the OS 27 Notes schema, `SyncableEntity`, Siri create/update intents, or OS 27-only reindexing APIs in this milestone.

**Exit criterion:** On macOS 26, eligible notes from a disposable collection appear in Spotlight by title and content, selecting a result opens the same UUID after rename or move, update/delete/rebuild behavior is covered by automated tests, and the documented privacy policy matches observed Core Spotlight and filesystem-index behavior.

### Phase 3: Build a Cross-Platform SwiftUI Vertical Slice

- Add the universal iPhone/iPad target and a SwiftUI feature package.
- Build adaptive collection navigation, search, note list, editor hosting, create/rename/tag/pin/delete, empty/error/download/conflict states, and settings against `NoteStore`.
- Reuse the same feature views in a new Mac shell where behavior is common. Wrap the existing Mac editor and its command bridge rather than translating `LinkingEditor` immediately.
- Use a `UITextView` adapter on iOS if SwiftUI rich-text editing cannot meet the formatting, selection, and performance tests.
- Add UI tests for iPhone compact navigation, iPad split navigation and keyboard use, Mac keyboard-first workflows, VoiceOver, Dynamic Type, multitasking/resizing, state restoration, and large collections.

**Exit criterion:** iPhone, iPad, and Mac can operate on the same disposable local fixture collection through the shared model and store, with no legacy controller dependency in the iOS target.

### Phase 4: Make iCloud Drive the Production Store

- Implement platform adapters for ubiquity-container discovery, download state, coordinated access, file presentation, version conflicts, moves, and deletes.
- On OS 27, adopt the new SwiftUI `Document` APIs for the iPhone/iPad document layer; keep availability-specific implementation out of `NoteStore`.
- Implement three-way per-note merges where safe. Plain text may use line-based merging after encoding validation; RTF and HTML require format-aware validation and should preserve both versions whenever an automatic merge could damage formatting or markup.
- Reconcile external edits through coordinated notifications plus full scans at launch and foregrounding. Match by current path first and then by recent paths and content hashes; preserve both when rename-plus-edit, copy-versus-move, or history assignment is ambiguous.
- Handle offline create/edit/delete, duplicate reconciliation UUIDs, external file renames and replacements, eviction, account changes, delayed downloads, note/reconciliation-record arrival in either order, interrupted saves, tombstones, and storage exhaustion.
- Run two-device and three-device fault tests with disposable collections, including edits performed by unrelated text editors and by direct uncoordinated file writes. Never test against the user's live notes directory.
- Replace the transitional publication of the compatibility database with guarded copy-only migration through `NoteStore`, clean per-note files, private per-note reconciliation records, and a durable transaction journal; do not add a move option.

**Exit criterion:** Multiple devices can edit different notes offline and converge, while same-note conflicts remain visible and recoverable and interrupted migration can resume or roll back.

### Phase 5: Add the OS 27 Notes Schema, App Intents, and Siri

- Extend the OS 26 `NoteEntity`, protected index, UUID navigation, and privacy policy according to the OS 27 preparation plan above; do not create a parallel entity or change stable identifiers.
- Add `SyncableEntity` and the Notes schema, then schema create/update intents, onscreen awareness, and content transfer.
- Keep intents thin; all reads and mutations go through `NoteStore` authorization and conflict rules.
- Retain OS 26 Spotlight coverage as a compatibility suite and test that the OS 27 additions do not duplicate entries or break existing result navigation.

**Exit criterion:** Automated App Intents tests pass, existing OS 26 Spotlight entries continue to open reliably, private notes remain excluded according to the documented policy, and create/update commands work through Siri on disposable OS 27 test devices.

### Phase 6: Make the Products Reproducible and Distributable

- Decide and document the minimum supported macOS, iOS, and iPadOS versions. In particular, decide whether the new mobile application requires OS 27 or carries an older document-adapter fallback.
- Reconcile the deployment target with `Info.plist`; remove PowerPC, i386, and macOS 10.4-era metadata.
- Move hand-maintained build settings into `.xcconfig` files and reduce configuration-specific drift.
- Remove machine-specific header and library search paths.
- Verify Debug, Release, Archive, and clean-machine launch workflows.
- Add Developer ID signing, hardened runtime, archive validation, and notarization for Mac, plus App Store/TestFlight signing and archive validation for iPhone and iPad.
- Document the shared iCloud Drive container identifiers, capabilities, and signing requirements for both applications. Keep the guarded first-run copy-and-verify migration separate from the ongoing storage path, which must not be considered production-ready until the storage contract and recovery tests exist.
- Evaluate App Sandbox separately; do not enable it until user-selected folders, security-scoped bookmarks, external editors, and Apple Events have an explicit design.

**Exit criterion:** Release archives install and run on clean supported Mac, iPhone, and iPad devices without Homebrew or developer tools.

**Progress as of August 2026:** The application builds with the current Xcode and macOS SDK, and the macOS target now declares the shared `iCloud.farm.poplar.spiral` Documents container with the Finder name “Spiral Notes.” Fresh installations default to this container when it is available. A first run that detects Notational Velocity or nvAlt preferences now offers the guarded, folder-selected, copy-only import described above; the manual switch workflow offers Copy or Keep and no longer offers Move. This behavior is provisional: the current Mac controller still publishes and writes its compatibility database alongside the generated note files. Production iCloud enablement must target the per-note store from Phase 4, and iPhone/iPad clients must not share the transitional collection. The container identifier still needs registration and verification with the intended Apple Developer team. The Homebrew OpenSSL dependency and architecture-specific legacy deployment overrides have been removed, and unsigned Debug and Release builds now produce universal `arm64`/`x86_64` executables. Broader `.xcconfig` extraction, hardened-runtime, signing, notarization, archive, clean-machine, and live-container verification work remains outstanding.

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

Editor URL detection now uses `NSDataDetector` with characterization coverage, and AutoHyperlinks is no longer referenced by the Xcode project, although its framework files remain in the repository. Legacy Sparkle, its update metadata, and its update command have been removed. Homebrew OpenSSL linkage has also been removed, with universal compatibility vectors covering the substituted AES-CBC, MD5, and Base64 implementations.

### Phase 8: Quarantine and Shrink the Legacy Mac Core

- Add nullability annotations and lightweight generics to headers at subsystem boundaries.
- Replace avoidable `performSelector:` calls with protocols, blocks, or direct typed calls.
- Convert isolated leaf classes to ARC first.
- Progressively enable ARC, temporarily compiling resistant legacy files with `-fno-objc-arc` if necessary.
- Run the static analyzer and memory diagnostics on persistence, synchronization, and editor workflows.

ARC migration should be separate from Swift migration so memory-management regressions are easier to identify.

**Exit criterion:** Most application code uses ARC and exposes sufficiently typed interfaces for safe Swift interoperability.

**Progress as of August 2026:** A narrow Objective-C bridge supports the new Swift settings code, demonstrating basic interoperability. The wider application remains predominantly manual-memory-managed Objective-C, and systematic ARC conversion, nullability, generics, static analysis, and interface strengthening have not begun.

Once tests, ARC, and service boundaries are established, review the large core classes. Split responsibilities before deciding whether to migrate them to Swift. A smaller Objective-C façade over tested Swift services may be safer than translating a large class line for line.

Delete obsolete compatibility paths, nibs, frameworks, and source files only after their replacements have shipped and migration compatibility has been verified. Do not delete the permanently supported Notational Velocity/nvAlt single-file, encryption, or WAL migration capability; only isolate or replace its implementation behind equivalent fixtures.

Do not port `NoteObject`, `NotationController`, `AppController`, or `LinkingEditor` to iOS. Their responsibilities must move into `NoteDomain`, `NoteStore`, feature state, and platform adapters. On Mac, retain only the thin behavior-specific pieces that remain valuable after the shared stack takes ownership.

**Exit criterion:** Remaining Objective-C/C exists intentionally as a Mac UI adapter or legacy compatibility reader, and the iOS application, shared store, Spotlight indexer, and App Intents have no dependency on it.

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

1. Establish the permanently retained Notational Velocity/nvAlt `LegacyCompatibility` boundary around the transitional importer and add golden fixtures for the single database, WAL, separate files, encodings, metadata, and every encryption variant. Prove that the current copy-only flow preserves its source and Keychain item before extracting or changing its behavior.
2. Specify permanent note UUID assignment and a reversible legacy-to-UUID migration, including duplicate and rollback behavior.
3. Specify clean `.txt`, `.rtf`, and `.html` behavior, deterministic app writes, supported encodings and markup, and golden fixtures before implementing the codecs. Explicitly exclude attachments and `.spiralnote` packages.
4. Specify the private per-note reconciliation record, bounded merge-base retention, tombstones, external-change matching rules, and ambiguous-change preserve-both behavior; then create the shared Swift package with `NoteDomain`, `NoteFileCodec`, `ReconciliationStore`, conflict values, and a temporary-directory `NoteStore`.
5. Add lossless, source-preserving migration tests from Notational Velocity and nvAlt single databases—including encrypted and WAL-recovery cases—and every supported separate-file format.
6. Build one SwiftUI navigation/search/list vertical slice on iPhone, iPad, and Mac using fixture data; wrap the existing Mac editor.
7. Decide the supported OS ranges and whether the mobile target can require OS 27's new `Document` APIs.
8. Implement the local rebuildable index and prove that deletion/rebuild cannot lose user data.
9. For the OS 26 milestone, define a generic UUID-backed `NoteEntity: IndexedEntity`, donate eligible notes to a named protected Core Spotlight index, add UUID opening and focused Spotlight actions, and test update/delete/rebuild plus native-file duplicate and privacy behavior.
10. Implement per-note coordinated iCloud access and two-device offline/conflict tests before switching any real collection to it.
11. For OS 27, extend the same `NoteEntity` with the Notes schema and `SyncableEntity`; add Siri create/update intents and App Intents Testing without changing Spotlight identifiers.
12. Remove the unused AutoHyperlinks files, then establish signed release archives and verify the Mac App Store update path without combining those changes with the storage migration.
13. Add CI for shared tests and all product configurations, with a warning baseline and disposable-data enforcement.

## Definition of Done for Modernization Changes

A modernization change is complete when:

- existing user data and compatibility formats remain readable;
- supported Notational Velocity and nvAlt single-file, encryption, and WAL fixtures remain migratable through the permanently retained legacy compatibility subsystem;
- local and per-note iCloud Drive-backed collections preserve offline, coordination, conflict, and recovery behavior without silent migration or rewriting;
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
