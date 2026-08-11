# Phase 5 catalog verification

All catalog and store tests use disposable temporary directories or locked
in-memory cloud adapters. They never resolve or mutate a user's live iCloud
container.

| Requirement | Automated coverage |
| --- | --- |
| Durable local catalog | `NoteCatalogTests.durableSearch` closes and reopens the SQLite database, then verifies summaries and FTS results remain available |
| Indexed search | Multi-term prefix and phrase matching, title/body/tag fields, pinned ranking, snippets, pagination, and completeness counts |
| Offload behavior | `SharedCloudNoteStoreTests.offloadedNoteRetainsCatalogProjection` changes an available canonical body to unavailable, verifies a download request, removes the editable in-memory body, and retains a stale searchable catalog projection |
| Honest never-indexed coverage | A record-only cloud placeholder remains title-searchable while reporting `neverIndexed` and incomplete coverage |
| Privacy | Private notes are excluded by default; cached body text is logically removed, SQLite secure deletion is enabled, the WAL is truncated, and disposable database files are checked for the removed plaintext |
| Account isolation | Reopening one catalog with a different account scope is refused before rows can be queried |
| Identity repair state | UUID aliases, provisional external discoveries, and operation summaries survive catalog reopen |
| Incremental mutation | Local and cloud create/update/delete paths update the affected catalog row without rewriting canonical content for indexing |

Run the focused suite with:

```sh
xcrun swift test --package-path Shared/SpiralCore --filter NoteCatalogTests
```

The Phase 5 exit criterion is not met yet. Shared SwiftUI list/search still
loads full notes and filters its visible collection in memory. Bounded
hydration, protected Core Spotlight, entity/deep-link integration, file
protection verification, account-change lifecycle handling, and measured
1,000-/10,000-note cross-platform budgets remain outstanding.
