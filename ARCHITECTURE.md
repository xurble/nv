# Target Note Storage and Search Architecture

## Scope

This document defines Spiral's intended cross-platform architecture. It is a
target and a set of conformance requirements, not a description of the current
implementation. Implementation status, sequencing, and release gates live in
[`MIGRATION_STRATEGY.md`](MIGRATION_STRATEGY.md).

Spiral uses ordinary per-note files in one shared iCloud Drive container so the
same collection is usable from Mac, iPhone, iPad, Finder, Files, and unrelated
text editors. That interoperability creates a deliberate two-part model:

- the canonical document contains the user's note content; and
- a private reconciliation record contains stable identity and app metadata.

iCloud can deliver, evict, conflict, or temporarily omit either part
independently. The store must therefore represent uncertainty explicitly. It
must never treat an absent or unavailable side as proof of creation or deletion.

## Product and data-safety requirements

- A note's canonical user content is one ordinary `.txt`, `.rtf`, or `.html`
  file. Compatible source extensions such as `.md`, `.taskpaper`, and `.htm`
  remain unchanged while they still represent the note's format.
- The filename is the title and parent directories are the visible folder.
- App-created and migrated notes have permanent UUIDs that survive rename,
  move, device change, conflict recovery, and local index rebuilding.
- The public document contains no Spiral UUID, tags, revision envelope, or
  other private application metadata.
- Public files are authoritative for body, format, title, and folder. Private
  reconciliation records are authoritative for stable identity and app-only
  metadata. Local indexes and provisional discoveries are never authoritative.
- Missing, evicted, downloading, and not-yet-delivered items are distinct from
  confirmed deletion.
- No client may invent a permanent identity merely because a reconciliation
  record has not arrived yet.
- Metadata-only mutations do not rewrite canonical note bytes.
- Unchanged scans do not rewrite canonical files or reconciliation records.
- Every public and private iCloud file read or mutation is file-coordinated.
  File coordination protects access to the local replica; it is not treated as
  a distributed transaction or cross-device lock.
- Ambiguous identities, histories, deletions, and conflicts remain recoverable
  and visible to the user. Spiral does not select a winner merely to keep the
  collection open.
- Existing legacy encrypted formats remain readable through the migration
  boundary. The modern clean-file store is plaintext at the application level.
  A note marked private is not thereby encrypted or hidden from Finder, Files,
  backups, or filesystem indexing.

## Data layout

```text
iCloud.farm.poplar.spiral/
├── Documents/                         Finder-visible, synchronized
│   ├── Meeting notes.txt
│   ├── Draft.rtf
│   └── Projects/Plan.html
└── Data/Reconciliation/               app-private, synchronized
    ├── <note-uuid>.json
    └── <another-note-uuid>.json

Application Support/                   local to one account and client
└── Spiral/SharedCloudStore/
    ├── Catalog.sqlite                 summaries, FTS, availability, aliases
    └── Operations/                    recoverable local operation journal

Core Spotlight protected index         local projection of eligible notes
```

| Location | Contents | Authority |
| --- | --- | --- |
| `Documents` | Clean note files and paths | Body, format, title, and folder |
| `Data/Reconciliation` | Versioned per-note records | UUID, metadata, content ancestry, transition and tombstone state |
| Local catalog | Verified summaries, full-text index, availability, provisional discoveries, aliases, and operation summaries | None; durable locally but rebuildable |
| Local operation journal | Intended mutations, expected paths/hashes, and completion checkpoints | Recovery authority for unfinished local operations only |
| Protected Core Spotlight index | Eligible title, text, tags, dates, and UUID navigation | None; local and rebuildable |

The local catalog is partitioned by iCloud account identity and collection. On
an account change, the active store is torn down, in-memory note data is
cleared, and the old account's catalog and Spotlight projection are no longer
queryable from the new session.

## Domain and store boundaries

The store does not require every body to be local in order to list or search a
collection. Its public model separates summaries from bodies.

`NoteSummary` contains:

- permanent UUID or an explicitly provisional local identifier;
- title, folder, tags, dates, pin and privacy state;
- canonical relative path and last verified content hash;
- body and metadata availability;
- search freshness and last-indexed revision;
- conflict, deletion, ambiguity, and pending-operation state.

`NoteBody` contains the decoded plain-text, RTF, or HTML representation and is
loaded on demand. A body reports one of these states:

- `available`;
- `staleCachedCopy`;
- `notDownloaded`;
- `downloadPending`;
- `downloadFailed`; or
- `deletedOrMissingPendingConfirmation`.

`NoteStore` provides paged summary enumeration, indexed search, on-demand body
loading, explicit download requests, mutations, conflict and deletion
resolution, observation, and index events. It does not expose platform file
availability APIs directly to feature code.

The shared feature layer may display a cached or indexed result whose body is
offloaded, but it must show cloud/freshness state and load the coordinated body
before editing. A stale cached body is never silently saved over an unavailable
newer canonical revision.

## Reconciliation-record schema

Each synchronized record is independently replaceable and schema-versioned. It
contains at least:

- the note UUID and record origin (`appCreated`, `migration`, or
  `externalDiscovery`);
- current path, bounded recent paths, and any in-progress path transition;
- current document hash, previous verified hashes, and bounded merge ancestry;
- created and modified dates;
- pin and privacy values with per-field revision stamps;
- normalized tags represented with independent add/remove revisions;
- legacy metadata with an explicit merge policy;
- tombstone generation, deletion state, deleted path and deleted content hash;
- record revision and client identifier;
- optional `supersededBy` identity for repaired provisional discoveries; and
- schema and retention versions.

Scalar metadata merges field by field using deterministic revision stamps, so
a tag change on one client does not erase a concurrent pin change on another.
Tags merge per normalized tag rather than by replacing the whole array.
Content ancestry is updated only after matching the coordinated document bytes;
a metadata-only update cannot replace it with stale ancestry.

Unresolved `NSFileVersion` conflicts for reconciliation records are enumerated,
merged where the schema permits it, and explicitly marked resolved. Competing
authoritative records that cannot be merged are surfaced as a repair conflict.

Merge-base content is retained only when needed for recovery and is not
rewritten during unchanged scans. Retention is bounded by both size and age so
the private store does not become a permanent duplicate of the note collection.

## Asynchronous document and record pairing

The pairing state machine is the core synchronization rule.

| Observed state | Required action |
| --- | --- |
| Document and matching live record | Bind to the record UUID and load normally |
| Document available, record unavailable | Request the record and expose `awaitingMetadata`; do not create a permanent record |
| Live record available, document unavailable | Keep the summary searchable, request the body as policy permits, and expose `awaitingBody` |
| Tombstone available, document still present | Reserve the identity and expose `deletionInFlight`; never rediscover the document as a new note |
| Record path absent without a tombstone | Expose `missingPendingConfirmation`; do not infer deletion |
| Available document with no known record | Create a local provisional discovery, not an immediately authoritative UUID |
| Multiple authoritative records claim one document | Stop mutations for the affected note and expose a repair conflict |

### Provisional external discovery

A genuinely unmanaged file added by an outside editor needs a UUID, but a
never-seen record and a delayed record are observationally identical. Spiral
therefore uses a reversible discovery protocol:

1. Record a local provisional discovery keyed by normalized path, raw content
   hash, and observation generation.
2. Consult the last verified local mapping and all available current, recent,
   tombstone, transition, and alias records.
3. Request unavailable reconciliation items and wait for metadata-query
   quiescence. A timeout alone is never considered proof that no record exists.
4. If an authoritative record arrives, bind its UUID and discard the local
   provisional discovery.
5. If the file remains unmanaged after a complete observation cycle, publish a
   deterministic `externalDiscovery` record. Equivalent clients discovering the
   same path and bytes publish the same provisional identity.
6. If an older authoritative record arrives later and path/hash ancestry proves
   a unique match, the authoritative UUID wins. The discovery record becomes a
   retained `supersededBy` alias so existing links resolve to the authoritative
   UUID. App-only metadata is never taken from discovery defaults over
   authoritative values.
7. If ancestry is not unique, keep both recoverable and ask the user.

Deep links and system entity donation use authoritative identities, repaired
aliases, or published discovery identities that have completed stabilization.
Purely local provisional discoveries do not escape the client. If a published
discovery is repaired later, alias-aware resolution preserves its existing
links while the authoritative UUID becomes canonical.

### Ordering rules

- Claim exact current paths for all documents before attempting recent-path or
  hash matching. This global pass prevents a lexicographically earlier copy
  from stealing the original file's UUID.
- Claim recent paths next, then unique content ancestry. Greedy per-file hash
  matching is forbidden.
- A tombstone or in-progress deletion reserves its current and recent paths
  against external discovery until retention expires or the user explicitly
  restores the content.
- A same-path external replacement with unrelated content is surfaced as a
  possible replacement rather than automatically inheriting private metadata.

## Mutation protocol

Every multi-file mutation has a durable local journal entry. The journal makes
local crash recovery deterministic; synchronized record transition state makes
the operation understandable when another client sees only one side.

### Create

1. Choose a collision-safe path and permanent UUID.
2. Journal the intended record and content hashes.
3. Publish a record whose transition expects the new document.
4. Write the coordinated canonical file.
5. Verify both sides and clear the transition and journal entry.

A client that receives either side first exposes an awaiting state. It does not
invent a second UUID.

### Content edit

1. Load and coordinate the current canonical revision.
2. Merge against the last verified ancestry when both sides changed.
3. Write the document only if encoded bytes changed.
4. Update ancestry without changing unrelated metadata revisions.
5. Incrementally update the local catalog and Spotlight projection.

Saving one note performs work proportional to that note, not the collection.

### Metadata edit

Update only changed record fields with new field revisions. Do not touch the
canonical document or its modification date. Merge any reconciliation-record
conflict before publishing the next record revision.

### Rename or move

Publish transition information containing old path, intended new path, and
expected hash; perform the coordinated move; then finalize current/recent paths.
A client that sees the moved file before the final record can still bind it to
the transition's UUID.

### Delete

1. Journal the deletion.
2. Publish a tombstone with a new deletion generation, expected path, and
   content hash before removing the canonical file.
3. Delete the coordinated document.
4. Mark document removal complete and clear the journal entry.

Seeing the tombstone first produces `deletionInFlight`; seeing the missing
document first produces `missingPendingConfirmation`. Neither order resurrects
the note. Tombstones and identity aliases have a documented retention period;
garbage collection runs only after every affected state is recoverable and
never uses a user's real collection for experiments.

## Observation and incremental reconciliation

Spiral observes both `Documents` and `Data/Reconciliation`, including their
iCloud metadata and download-state changes. File-presenter and metadata-query
payloads are wake-up and dirty-path hints, not authoritative new state.

Signals are debounced and coalesced into at most one active reconciliation
task plus one accumulated dirty set. New signals update that set rather than
queueing an unbounded series of full scans.

Incremental reconciliation:

- evaluates dirty documents and records together;
- uses resource metadata and known hashes to avoid rereading unchanged bodies;
- writes only changed files and records;
- updates only affected catalog and Spotlight rows; and
- publishes one coherent feature-model change batch.

Full read-only integrity scans still run at startup, foreground activation,
after account changes, and periodically when the client is active. They repair
local catalog drift but do not rewrite unchanged cloud state. Expensive body
hashing and decoding are bounded, cancellable, and performed off the main actor.

## Local search and Core Spotlight

Search is a local, durable service rather than a filter over every decoded
`Note` value.

The account-scoped SQLite catalog stores summaries and an FTS index of the last
verified textual body that the client's retention policy permits. It supports:

- tokenized multi-term search across title, body, tags, and folder;
- prefix and phrase matching;
- relevance ranking with pinned and recency boosts;
- snippets and highlighted match ranges;
- pagination; and
- availability and freshness filters.

The catalog uses the strongest platform file protection compatible with
background indexing, follows the same account and per-note retention policy as
search, and never stores legacy migration plaintext or a privacy-excluded body.

The protected Core Spotlight index is an incremental projection of notes that
the user permits in system search. It uses the permanent UUID for identity and
contains title, textual body, tags, dates, and canonical URL where appropriate.
Renames and moves update the same entity. Deletes, privacy changes, identity
repair, and account changes update or remove it immediately.

An offloaded body remains searchable from its last verified local index when
policy permits. A newly installed client cannot search the body of a note it has
never downloaded. A resumable background indexer may hydrate eligible bodies
subject to network, power, storage, and privacy policy, but collection opening
never synchronously downloads every note. Search shows completeness and
freshness, for example “12 notes still indexing,” rather than silently returning
an incomplete result set.

Spiral does not synchronize its SQLite or Spotlight indexes. Synchronizing a
separate full-text projection would duplicate private content and is a separate
product and privacy decision.

## Offload behavior

| State | List and search | Open and edit |
| --- | --- | --- |
| Body offloaded, record and index available | Summary and last verified indexed body remain searchable with a cloud/freshness badge | Download and verify the coordinated body before editing |
| Body never indexed on this client | Title and available metadata are searchable; search reports incomplete body coverage | Download on open or through the background indexer |
| Record offloaded, body available, verified local mapping exists | Show cached summary as `awaitingMetadata`; do not create a new record | Permit read-only body access; defer metadata-sensitive mutation until pairing is verified |
| Both sides offloaded | Preserve the last verified summary and search projection; request only what the foreground action or index policy needs | Show progress and retryable download errors |
| Initial client with neither side hydrated | Show discovered cloud placeholders and indexing progress, not an empty collection | Hydrate incrementally |

An initial all-offloaded collection must start observers before hydration and
must recover in place as downloads complete. It must not require a relaunch.

## Outside editors

Outside editors remain supported because canonical notes are ordinary files.
The next incremental reconciliation or integrity scan applies these policies:

| Outside change | Result |
| --- | --- |
| Edit bytes at the same path | Keep identity only when current path and ancestry support it; otherwise flag possible replacement |
| Rename or move without changing bytes | Recover UUID through transition, recent path, or unique ancestry |
| Add a recognized file | Use provisional external discovery before publishing identity |
| Copy a recognized file | Exact current-path claims preserve the original UUID; the copy receives a discovery identity |
| Delete a file | Await tombstone or user confirmation; absence alone is not deletion |
| Rename/move and edit simultaneously | Use transition ancestry when available; otherwise preserve both and request repair |
| Add an unsupported visible file | Leave valid notes usable; report and quarantine the unsupported item from Spiral operations |

Spiral never deletes, moves, or rewrites an unsupported outside item merely to
make the collection valid.

## Conflict handling

Content merges use raw hashes and bounded common ancestry:

1. Identical revisions collapse.
2. If only one revision differs from the common base, use it.
3. Plain text may merge validated non-overlapping edits with a proven base.
4. RTF and HTML merge only through format-aware operations that preserve their
   authored structure.
5. Otherwise preserve both byte sequences as ordinary documents and expose a
   conflict-resolution workflow.

The UI supports choose-local, choose-external, manual merge, keep-both, and
mark-resolved operations. System `NSFileVersion` conflicts for both canonical
documents and reconciliation records are not left indefinitely unresolved.

Deletion confirmation, possible replacement, duplicate authoritative identity,
and failed transition recovery have similarly explicit repair workflows.

## Performance requirements

The architecture targets work proportional to changed data:

- opening lists summaries without decoding every body;
- a normal save reads and writes one note and its changed record fields;
- metadata-only saves do not write the note file;
- one cloud signal does not trigger multiple queued collection scans;
- unchanged integrity scans produce no iCloud writes;
- search executes through an index and paginates results; and
- background hydration is bounded and cancellable.

Release performance tests use disposable 1,000- and 10,000-note collections,
mixed TXT/RTF/HTML sizes, cold and warm catalogs, 50% and 100% offload, bulk
download arrivals, low storage, interrupted networks, and simultaneous edits.
They record launch latency, first searchable result, query latency, save latency,
peak memory, bytes read and written, record writes, download count, and energy.

## Lifecycle and account handling

- iPhone and iPad reconcile on startup and whenever a scene becomes active.
- Mac reconciles on startup and application foreground activation.
- All clients observe iCloud identity changes. They cancel active work, clear
  in-memory content, close the account-scoped catalog, remove or deactivate its
  Spotlight projection, resolve the new container, and open the new account as
  a separate collection.
- Download, storage-exhaustion, and coordination failures are retryable states
  with visible affected-note scope. A failed operation never reports success
  merely because one side was written.

## Legacy compatibility boundary

The Mac retains a quarantined compatibility runtime for inspecting, decrypting,
WAL-recovering, and converting Notational Velocity/nvAlt collections. Migration
operates on a byte-verified disposable copy, publishes clean files and records,
and retains the source or a verified backup. It does not remain as a second live
synchronization implementation.

Migrating encrypted data to the modern store requires an explicit warning that
the destination is plaintext. Legacy decryptors remain supported even though
the modern store does not write the old encrypted format.

## Conformance and release gate

The shared iCloud store is not production-ready until automated fault tests and
registered-container physical-device tests prove:

- document-first, record-first, tombstone-first, deletion-first, and offloaded
  arrival sequences converge without identity duplication or resurrection;
- late authoritative records safely supersede provisional discoveries;
- concurrent metadata fields merge without unrelated lost updates;
- record and document `NSFileVersion` conflicts are recoverable in the UI;
- warm and cold clients preserve honest search/list completeness under offload;
- account changes cannot expose the previous account's cached notes;
- unchanged signals and scans cause no cloud write amplification;
- save and search meet the performance requirements above; and
- storage exhaustion, process termination, and network interruption leave a
  recoverable journaled state.

No test may use a user's real notes directory or iCloud collection.
