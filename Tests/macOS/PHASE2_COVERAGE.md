# Phase 2 Shared-Core Coverage

Run the shared Swift package and the complete Phase 1 compatibility suite in
both configurations with:

```sh
Scripts/ci/run-phase2.sh Debug
Scripts/ci/run-phase2.sh Release
```

All package and production-reader tests create uniquely named directories under
the system temporary directory. They never discover or open configured notes,
preferences, Keychain data, or live iCloud data.

| Phase 2 requirement | Implementation and automated coverage |
| --- | --- |
| Permanent legacy boundary | macOS `LegacyCompatibility/NVLegacyCompatibility.h`, production `NVLegacyArchiveSource`, shared `LegacyCompatibilitySource`, full archive fixtures, and crypto/WAL characterization executables |
| Source and Keychain preservation | each production-reader probe compares source and retained-backup fingerprints; the importer only receives a disposable copy, preserves the archived Keychain database identifier, and never accesses or removes a real Keychain item |
| Encrypted-source warning | core refuses encrypted migration before explicit plaintext confirmation; Mac adapter presents the warning before creating clean files |
| Shared domain and store contract | `Note`, permanent `NoteID`, revisions, conflicts, index events, and async `NoteStore` protocol |
| Deterministic clean codecs | metadata-free UTF-8 TXT, RTF, and HTML serialization; authored external RTF/HTML bytes remain unchanged until edited; legacy text decoding coverage |
| Private reconciliation | independently replaceable, schema-versioned JSON record per UUID; current/recent paths, raw hash, bounded merge base, metadata, privacy, and tombstone state |
| Local store | disposable-directory create/update/rename/move/delete/reopen tests with filename collisions and stable UUIDs |
| Separate-file import | TXT-family inference and mixed-family refusal through `LegacySeparateFileSource` |
| Legacy archive import | generated sanitized full archives exercise plaintext NV/MacRoman/filename/history values, attributed nvAlt RTF, AES-256 with default and alternate KDF iterations, intact and interrupted WAL, wrong passphrase, and damaged input through the production Objective-C reader and `LegacyMigrationService`; the older IDEA-CFB input has a fixed alternate-cipher vector |
| Cache rebuild | test deletes the complete index, reopens the collection, and rebuilds it from canonical files plus reconciliation records without losing content or metadata |
| Conflict values | local/external/common-base values and store conflict events are exercised without AppKit/UIKit |
| Rollback | natural and fault-injected failures remove the new modern store, reconciliation records, and cache, preserve the source byte-for-byte, and retain its verified backup |

Real user collections are never fixtures. The full archives are deterministic,
sanitized archives generated with the production archive, encryption, and WAL
writers. Additional historical archives may be added only after removing
personal content and verifying provenance; the low-level accepted-input matrix
remains guarded by the Phase 1 crypto, archive, metadata, encoding, and WAL
fixtures.
