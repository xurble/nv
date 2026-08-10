<!--
Copyright (c) 2026 Gareth Simpson and Zachary Schneirov. All rights reserved.
This file is part of Spiral, a fork of Notational Velocity.

Spiral is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Spiral is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Notational Velocity. If not, see <http://www.gnu.org/licenses/>.
-->

# Phase 4 verification

All automated storage tests use disposable temporary directories or locked
in-memory fault adapters. They never resolve or mutate a user's live iCloud
container.

| Requirement | Automated coverage |
| --- | --- |
| Legacy identical/divergent UUID merge | `LegacyNotePolicyTests` exercises add, skip-identical, and preserve-divergent decisions used by `NotationController` |
| Merge collisions | Case-insensitive monotonic “Merged Copy” titles and existing filename collision rules |
| Merge backup lifecycle | `NotesMigrationTests` covers byte-verified backup creation, successful commit cleanup, staged restore, backup removal after rollback, pre-mutation failure, and retained backup after injected restore failure |
| OS 26 document access | `CoordinatedCloudAdapterTests` executes coordinated write/read/move/delete and traversal refusal through `FoundationCloudDocumentAdapter` |
| Availability and change signals | Ubiquitous download states, `NSFileVersion`, `NSFilePresenter`, and `NSMetadataQuery` are isolated behind the adapter; fault tests prove unavailable files request download and never imply deletion |
| Identity reconciliation | Current path, bounded recent paths, then content hash; ambiguous hashes and duplicate UUID records are surfaced instead of guessed |
| Format-aware merge | Validated non-overlapping UTF-8 line edits merge; same-line edits, invalid encoding, RTF, and HTML preserve both revisions |
| Two-device faults | Delayed private-record replicas edit different notes offline and converge in the shared document view |
| Three-device faults | Delayed replicas merge three non-overlapping same-note edits; divergent same-line edits retain a visible conflict copy |
| Durable migration | Per-item atomic journal resumes interrupted publication and verifies the retained backup and final destination |
| Guarded rollback | Rollback removes only journal-owned bytes whose hashes still match and refuses to erase a later external edit |
| Production shared store | Two `CloudNoteStore` clients share coordinated documents and private records; a Mac-created note keeps its UUID through a mobile edit and Mac reload |
| Legacy handoff gate | Mobile preflight refuses legacy/unrelated public data, and Mac retirement byte-verifies a retained database/WAL backup before deleting only those artifacts |

Run the shared coverage in Debug or Release through
`Scripts/ci/run-phase2.sh Debug` and `Scripts/ci/run-phase2.sh Release`; the
Phase 3 gate composes the same package suite with platform UI coverage. Before
release, separately verify the registered container on physical Mac, iPhone,
and iPad devices for first handoff, account changes, eviction, storage exhaustion,
unrelated text-editor writes, and real network interruption.
