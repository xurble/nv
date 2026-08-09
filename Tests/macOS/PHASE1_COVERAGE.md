# Phase 1 Safety-Net Coverage

Run the same clean workflow used by continuous integration with:

```sh
Scripts/ci/run-phase1.sh Debug
Scripts/ci/run-phase1.sh Release
```

The workflow builds the application, enforces the warning baseline, launches
the built executable against a disposable temporary notes directory, runs both
XCTest bundles, and then runs every `run-*-tests.sh` characterization harness.

| Migration-strategy requirement | Automated coverage |
| --- | --- |
| Note formats and encodings | `Phase1FormatTests`, `note-encodings.json`, and TXT/RTF/HTML golden files |
| Filenames and reserved characters | `LegacyNotePolicyTests` through the production `LegacyNotePolicies` seam |
| Labels and extended metadata | `LegacyNotePolicyTests` and `TemporaryCollectionIntegrationTests` extended-attribute copy |
| WAL and interrupted recovery | `WALRecoveryTests` against production `WALController`, including a torn final record and wrong key |
| Search matching, ordering, highlighting | `LegacyNotePolicyTests` through the production matcher/order/highlight seam |
| Import/export | `Phase1FormatTests` plus existing first-run migration tests |
| Historical synchronization metadata | `historical-sync-archive.plist` load/no-rewrite/no-service test and WAL metadata replay |
| Legacy encrypted data | `legacy-encryption-v1.json` covers passphrase and session KDFs, the compressed database payload envelope, wrong passphrase, AES, Base64, and legacy digest vectors |
| iCloud states and interrupted migration | `NotesMigrationTests` pure state policy and durable staged/published transaction recovery |
| Disposable launch | `run-disposable-launch-test.sh` and the guarded `SPIRAL_DISPOSABLE_LAUNCH_DIRECTORY` smoke path |
| Unit/integration targets and CI | Shared `Notation` scheme, `NotationSettingsTests`, `NotationIntegrationTests`, and `phase1-safety-net.yml` |
| Warning regression | `Config/WarningBaseline.txt` and `Scripts/ci/verify-warning-baseline.sh` |

All destructive and failure-injection coverage uses newly created temporary
directories. No test discovers or opens the user's configured notes directory
or live iCloud Drive collection.
