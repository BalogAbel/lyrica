# ADR-028: Local Storage Budget and Eviction Policy

- Status: Accepted
- Date: 2026-07-30
- Spec: `docs/specs/2026-07-30-lft3-mutation-budget-and-lft4-storage-eviction.md`
- Plan: `docs/plans/2026-07-30-lft3-mutation-budget-and-lft4-storage-eviction.md`
- Findings: LF-T3, LF-T4
- Closes: `docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md`

## Context

The 2026-06-22 repository review flagged two of the remaining High findings
blocking the "indefinite offline" claim in ADR-008:

- **LF-T3** — `CachedPlanningMutations` already folds repeated intent per
  aggregate (one row per `(userId, organizationId, aggregateType,
  aggregateId)`), so the real growth vector is not repeated edits but the
  **number of distinct aggregates touched while offline**, plus the per-row
  `originSnapshotJson` payload. Nothing caps either, and nothing warns the
  user.
- **LF-T4** — there is no storage quota monitor and no eviction policy.
  Three separate Drift databases carry local state (`planning`,
  `song_catalog`, `auth`), and `architecture.md`'s Offline Strategy framed
  the catalog as "one active snapshot" with no stated protection order for
  what could be dropped under pressure. `storage_pressure_probe_test.dart`
  had already proven that a failed local write propagates as an exception
  rather than being silently swallowed, but left open what the app does with
  that failure.

Specifying this slice also surfaced a correctness gap in the existing fold
logic that had to be fixed before a budget could safely sit on top of it: see
"Squash correctness fixes" below.

## Decision

### D1 — Two ladders, one seam

Catalog eviction cannot relieve the mutation budget, because pending
mutations are never evictable — deleting cached songs does not shrink the
mutation store. The policy is therefore two distinct ladders sharing one
accounting seam (`LocalStorageFootprint`, `LocalStorageBudget`,
`LocalStorageMonitor`):

| pressure | warn | act | refuse |
|---|---|---|---|
| **mutation budget** (LF-T3) | soft threshold → warning surfaced | *(no eviction — nothing droppable applies)* | hard threshold → refuse **new** writes |
| **storage pressure** (LF-T4) | soft threshold → warning surfaced | critical threshold or an actual write failure → evict droppable catalog, retry once | retry fails → typed failure propagates |

The remedy for a full mutation budget is to sync or discard pending work; the
error carries that message. Storage pressure, by contrast, has a real
release valve — droppable catalog data — so it escalates through eviction
before it ever needs to refuse anything.

### The budget is checked before the write, not after

`BudgetedPlanningMutationStore._guardedWrite` measures the mutation store's
current byte footprint **before** delegating to the write, and refuses with
`PlanningMutationBudgetExceededException` if that footprint is already at or
past `mutationRefuseBytes`. A refusal therefore means "the store was already
over budget," not "this write would push it over" — the store can overshoot
the budget by at most one mutation. That overshoot is accepted: the budget
exists to bound growth, not to cap it to the byte, and the accountant's byte
count is an explicit proxy rather than a true size (see D2).

Nothing is ever undone, deleted, or rewritten to enforce this budget. Pending
mutations are unsynced user intent with no other copy, so a refusal must
never destroy one.

**Rejected: check after the write and undo it.** An earlier draft of this
decorator measured the footprint after delegating to the write, and rolled
the write back if the post-write footprint exceeded the refuse threshold.
This was rejected once the fold semantics were worked through: a write that
folds into an existing aggregate (for example a `planEdit` landing on a plan
whose `planCreate` is still pending) does not create a new row, it merges
into one. "Undo the write" on a fold has no way to distinguish the newly
merged fields from the pending aggregate they were merged into — the only
reachable undo is deleting the whole row, which destroys the earlier
pending mutation, not just the one being refused. That is precisely the
failure mode this ADR exists to prevent. Checking before the write avoids
the question entirely: nothing is ever committed that then has to be taken
back.

### D2 — Content-derived byte accounting, no platform quota API

`PlanningStorageAccountant` and `CatalogStorageAccountant` estimate
footprint from row content with SQL aggregates — `SUM(length(col))` over
every text and JSON column, plus a fixed per-row overhead
(`kLocalStorageRowOverheadBytes = 64`, standing in for integer keys,
versions, positions and timestamps) — not from `dart:io` file size and not
from `navigator.storage.estimate()`.

Rationale: the same code path runs on native and web, it is deterministic
against an in-memory database, and it introduces no web-only branch that
this slice cannot verify. This is stated explicitly: the numbers are a
**footprint proxy**, comparable to each other and stable for a fixed corpus,
not a true on-disk size. They exclude index and page overhead, and on web
they say nothing about what the browser has actually allocated.

### D3 — Enforcement is a decorator, guarding only the methods that can grow the store

`BudgetedPlanningMutationStore implements PlanningMutationStore` wraps
`DriftPlanningMutationStore` and is the single enforcement point. It guards
exactly the nine `record*` methods — `recordPlanCreate`, `recordPlanEdit`,
`recordSessionCreate`, `recordSessionRename`, `recordSessionDelete`,
`recordSessionReorder`, `recordSessionItemCreateSong`,
`recordSessionItemDelete`, `recordSessionItemReorder` — because those are
the only calls that can introduce or grow a pending aggregate.

`saveSyncAttemptResult`, `retryMutation` and `clearMutation` pass straight
through **unguarded**. This is deliberate, not an oversight: they modify or
shrink an existing row rather than growing one, and guarding them would make
a full store unrecoverable. Once the mutation budget is exhausted,
`clearMutation` is the only way out — discard has to keep working
unconditionally, or the budget becomes a trap with no recovery path.

**Rejected alternatives** (from the spec, carried here for the durable
record):

- **Check inside `DriftPlanningMutationStore._upsertRecord`.** One choke
  point, least code — but `saveSyncAttemptResult` and `retryMutation` also
  route through `_upsertRecord`, so a blanket check there would block status
  updates and retries, and it would couple the planning store to the
  catalog database.
- **Check in `PlanningWriteService`.** Better error vocabulary, but the
  mutation store is public and has more than one caller, so the guarantee
  would not be tight.

### On a storage write failure, evict once and retry once

A write that reaches the delegate and fails at the storage layer (not a
domain rejection such as `LocalPlanningSlugConflictException`, which is
rethrown untouched — retrying it would fail identically, and evicting first
would destroy cached data for nothing) is treated as storage pressure
(LF-T4): `SongCatalogEvictor.evictDroppable()` runs once, then the write is
retried once. Every guarded write is an upsert keyed by its aggregate, so
the retry is idempotent — a partially applied first attempt cannot
duplicate. If the retry still fails, the failure is wrapped as a typed
`LocalStorageWriteFailure` and propagated; it is never swallowed.

### D4 — Protection order

**Never evicted:**

- pending planning mutations and pending song mutations — unsynced user
  intent with no other copy;
- the planning projection — offline it is the only readable view, so
  dropping it blinds the user precisely when they cannot re-fetch;
- cached catalog summaries — they back the browsable song list, for the same
  reason;
- the last-known identity store (ADR-020).

**Droppable:** cached catalog **sources** (`CachedCatalogSources` — the
lyrics/ChordPro bodies) for songs that have **no pending song mutation**.
They are the largest payload by far and are re-fetchable on reconnect.
Excluding songs with a pending mutation keeps the rule absolute: eviction
never touches a row that unsynced intent depends on.

Accepted consequence, stated plainly: after eviction, a song whose source
was dropped still appears in the list (its summary survives), but reading
its body requires connectivity until the next catalog refresh repopulates
it.

This supersedes the "one active snapshot" framing that `architecture.md`'s
Offline Strategy section previously used, which LF-T4 was reasoned against.

### D5 — Native-only verification

LF-T4's risk is most acute on web, where IndexedDB is subject to silent
browser eviction, and there is no web offline e2e harness — Phase 3 added
only a `flutter build web` compile gate (DX-2).

**Chosen: implement and verify on native; document the web assumptions as
unverified.** Every threshold and the eviction trigger are verified against
the native Drift/sqlite3 backend only. Because accounting is content-derived
(D2), the *logic* is platform-independent — the same SQL runs unmodified on
web. What is **not** verified is whether the browser evicts underneath the
app regardless of anything this policy does, and whether the byte estimate
tracks real IndexedDB usage at all.

**Rejected: build a `chromedriver` web offline e2e lane first.** That is new
CI infrastructure that would have consumed this phase on its own, for a
harness whose absence is already a separately tracked deferred item.

`docs/deferred/2026-06-29-web-offline-e2e.md` stays open, with its trigger
condition unchanged: it remains the prerequisite for relying on IndexedDB
capacity assumptions in production.

### D6 — Thresholds

Injectable constructor parameters on `LocalStorageBudget`, so tests can run
against tiny budgets without waiting for real data volume:

| threshold | default | rationale |
|---|---|---|
| mutation warn | 1 MiB | roughly a few thousand mutations; far past any normal offline span |
| mutation refuse | 4 MiB | bounds pathological growth without ever biting normal use |
| total warn | 128 MiB | native-informed heuristic |
| total critical | 192 MiB | triggers automatic catalog eviction on the write path |

These are deliberately sized to be unreachable in normal use. A budget that
bites during ordinary rehearsal planning would be the wrong budget: the
purpose is to make growth **bounded and observable**, and to give a signal
before the storage substrate fails, not to ration everyday work. The total
thresholds are heuristics on native and explicitly unverified on web (D5).

### Eviction and budgeting are local storage policy, not authorization

Nothing in this ADR changes what the backend authorizes. `SongCatalogEvictor`
deletes local cache rows only; it never touches, blocks, or gates a write
RPC. This keeps AGENTS.md rule 5 intact: authorization stays backend-enforced
(Postgres RLS + `security definer` RPCs); local storage policy governs only
what the client keeps around, never what it is allowed to do.

## Squash correctness fixes

Specifying this budget required reasoning precisely about what a folded
mutation row guarantees, which surfaced two correctness gaps in the existing
fold logic. Both are fixed in this slice, ahead of and independent of the
budget itself, and pinned by
`test/offline/adversarial/planning_squash_contract_test.dart`.

**The base-version fold disagreed with itself.** The reorder paths
(`recordSessionReorder`, `recordSessionItemReorder`) already kept the base
version captured by the *first* local edit when folding a later draft into
an existing pending row. `recordPlanEdit`, `recordSessionRename`,
`recordSessionDelete` and `recordSessionItemDelete` did the opposite: they
let a later draft's `baseVersion` overwrite the one already stored.

This matters because `draft.baseVersion` comes from the locally merged
read — the value the user actually saw includes their own pending overlay,
not a freshly refreshed remote state. If a later local edit rebases the
stored `baseVersion` forward, it asserts a base the user never observed
against the remote server, and it silently suppresses exactly the conflict
optimistic concurrency exists to raise. All four drifted paths now keep the
first captured base version, matching the reorder paths.

`retryMutation`'s rebase is unaffected and stays as it is: it explicitly
recomputes a fresh base version via `_currentBaseVersionFor`, but only on a
user-initiated retry, where rebasing onto the latest known state is the
correct, deliberate action rather than a side effect of an unrelated fold.

**Collapsing a still-pending `sessionCreate` orphaned its item
mutations.** When `recordSessionDelete` collapses a still-pending
`sessionCreate` (the session is deleted locally before it ever synced), it
already deleted the session's own mutation row and removed the session from
any pending reorder. It did not delete the session's pending `session_item`
and `session_item_order` mutations. Those rows were orphaned: the parent
session never reached the backend, so they could only ever fail
`dependencyBlocked` on sync, and — once the mutation budget existed — they
would have consumed it forever with no way to reach zero. They are now
deleted with the session, inside the same transaction.

## Testing

- `test/offline/adversarial/planning_squash_contract_test.dart` — pins
  exactly-once folding (ADR-019) and the corrected base-version semantics
  above, plus the orphaned session-item cleanup.
- `test/application/storage/local_storage_budget_test.dart`,
  `planning_storage_accountant_test.dart`, `local_storage_monitor_test.dart`,
  `song_catalog_evictor_test.dart` — the accounting and eviction contracts,
  including the multi-tenant case (a different `(userId, organizationId)`
  owner's droppable source is evicted independently of another owner's
  protected one).
- `test/application/planning/budgeted_planning_mutation_store_test.dart` —
  the enforcement decorator: writes below the refuse threshold succeed;
  writes at or above it are refused without eviction; a refusal leaves
  existing pending mutations untouched and `clearMutation` still drains the
  store; a refused **fold** leaves the pending aggregate it would have
  folded into completely intact; a domain rejection
  (`LocalPlanningSlugConflictException`) propagates without eviction or
  retry.
- `test/offline/adversarial/storage_pressure_contract_test.dart` — the
  former characterization probe, now an enforced contract: a simulated
  storage write failure evicts droppable catalog sources, retries once, and
  surfaces a typed `LocalStorageWriteFailure`; the failed mutation is
  confirmed absent from a subsequent read, ruling out a partial commit.

See `docs/testing/testing-strategy.md` for how these fit into the broader
adversarial suite.

## Consequences

- The mutation store can overshoot its refuse threshold by at most one
  mutation (checked-before-write, D1 above). Accepted.
- After catalog eviction, a song's body requires connectivity to read again
  until the next catalog refresh, even though it still appears in the list.
  Accepted (D4).
- Every threshold in this ADR is verified against native Drift/sqlite3 only;
  the web/IndexedDB assumptions behind them are unverified until
  `docs/deferred/2026-06-29-web-offline-e2e.md` is addressed (D5).
- `architecture.md`'s Offline Strategy section is updated to carry the
  protection order and the accounting seam instead of the superseded "one
  active snapshot" framing.
