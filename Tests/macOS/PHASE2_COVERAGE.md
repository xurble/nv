# Phase 2 Shared-Core Coverage

Run the shared Swift package and the complete Phase 1 compatibility suite in
both configurations with:

```sh
Scripts/ci/run-phase2.sh Debug
Scripts/ci/run-phase2.sh Release
```

All package tests create UUID-named directories under the system temporary
directory. They never discover or open configured notes or live iCloud data.

| Phase 2 requirement | Implementation and automated coverage |
| --- | --- |
| Permanent legacy boundary | macOS `LegacyCompatibility/NVLegacyCompatibility.h`, shared `LegacyCompatibilitySource`, golden NV/nvAlt value snapshots, existing crypto and WAL characterization executables |
| Source and Keychain preservation | verified source fingerprint and retained backup tests; production importer only receives a disposable copy and uses the non-removing encryption migration API |
| Encrypted-source warning | core refuses encrypted migration before explicit plaintext confirmation; Mac adapter presents the warning before creating clean files |
| Shared domain and store contract | `Note`, permanent `NoteID`, revisions, conflicts, index events, and async `NoteStore` protocol |
| Deterministic clean codecs | metadata-free UTF-8 TXT, RTF, and HTML serialization; authored external RTF/HTML bytes remain unchanged until edited; legacy text decoding coverage |
| Private reconciliation | independently replaceable, schema-versioned JSON record per UUID; current/recent paths, raw hash, bounded merge base, metadata, privacy, and tombstone state |
| Local store | disposable-directory create/update/rename/move/delete/reopen tests with filename collisions and stable UUIDs |
| Separate-file import | TXT-family inference and mixed-family refusal through `LegacySeparateFileSource` |
| Legacy archive import | existing quarantined controller retains archive, KDF, cipher, passphrase, and WAL input compatibility; its clean-file/value output is the only input accepted by the shared boundary |
| Cache rebuild | test deletes the complete index, reopens the collection, and rebuilds it from canonical files plus reconciliation records without losing content or metadata |
| Conflict values | local/external/common-base values and store conflict events are exercised without AppKit/UIKit |
| Rollback | failed conversion removes the new modern store and cache, preserves the source byte-for-byte, and retains its verified backup |

Real user collections are never fixtures. Additional historical archives may
be added only after removing personal content and verifying provenance; the
low-level accepted-input matrix remains guarded by the Phase 1 crypto, archive,
metadata, encoding, and WAL fixtures.
