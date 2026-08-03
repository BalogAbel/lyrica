# Mutation Size Budget and Local Storage Eviction Policy

> Status: Draft

## Goal

Close `LF-T3` and `LF-T4` from `docs/architecture/repository-review-2026-06-22.md`
— the two remaining High findings blocking the "indefinite offline" claim — and
resolve `docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md`.

Concretely:

1. **Bound the mutation store.** Give unsynced local intent an explicit size
   budget, with a warning threshold and a hard refusal of *new* writes past it.
2. **Account for and relieve storage pressure.** Measure the local footprint
   (mutation store, planning projection, song catalog), and define an eviction
   policy with a stated protection order.
3. **Decide what the caller does with a propagated storage failure** — the
   question `storage_pressure_probe_test.dart` deliberately left open.

This slice establishes the storage-accounting seam that the rest of the phase
reasons against.

## Problem

### LF-T3 — unbounded mutation growth

`CachedPlanningMutations` has primary key
`(userId, organizationId, aggregateType, aggregateId)`, so the store already
holds **at most one row per aggregate**, and
`DriftPlanningMutationStore` already folds repeated intent into that row:

| existing row | new intent | current behaviour |
|---|---|---|
| `planCreate` | `planEdit` | folded into the create (ADR-024 full-state draft) |
| `sessionCreate` | `sessionRename` | folded into the create |
| `sessionCreate` | `sessionDelete` | row deleted outright |
| `sessionItemCreateSong` | `sessionItemDelete` | row deleted outright |
| any | reorder | one row per `planId` / `sessionId` |

So "squash repeated edits" is largely done. The real growth vector is the
**number of distinct aggregates touched while offline** — a long offline span
that creates 300 session items creates 300 rows — plus the per-row
`originSnapshotJson` payload. Nothing caps either, and nothing tells the user
the store is growing.

**Squash correctness gap found while specifying this.** `recordSessionDelete`,
when it collapses a still-pending `sessionCreate`, deletes the session row and
removes the session from any pending reorder, but leaves the pending
`session_item` mutations that belong to that session. Those rows are orphaned:
they can never sync (the parent session does not exist remotely, so they fail
`dependencyBlocked`), they are invisible as a *cause*, and they consume budget
forever. The same shape applies to a `planCreate` that is never synced, but the
store has no plan-delete path, so only the session case is reachable today.

### LF-T4 — no storage accounting, no eviction policy

There is no size monitor and no eviction policy. Three separate Drift databases
carry local state:

| database | contents | re-fetchable? |
|---|---|---|
| `planning` | projection (`CachedPlanningPlans/Sessions/SessionItems`) **and** `CachedPlanningMutations` | projection yes; mutations **no** |
| `song_catalog` | snapshot (`CachedCatalogSummaries`, `CachedCatalogSources`) **and** `CachedCatalogSongMutations` | snapshot yes; song mutations **no** |
| `auth` (last-known identity) | offline-authenticated identity (ADR-020) | no |

Note that "the catalog" is not uniformly droppable: the catalog database also
carries pending *song* intent (`CachedCatalogSongMutations`, written by
`saveSongMutation`). Clearing that database wholesale would destroy unsynced
song edits — the exact failure the protection order exists to prevent.

`storage_pressure_probe_test.dart` already proves a failed local write
**propagates** rather than being swallowed. It does not say what the app does
with that failure.

## Non-Goals

- Web/IndexedDB verification. See "Native-only verification" below.
- Evicting the planning projection. See "Protection order".
- Any change to what the backend authorizes. Eviction and budgeting are local
  storage policy, never a permission gate (AGENTS.md rule 5).
- Riverpod 3 migration.

## Decisions

### D1 — Two ladders, not one

Catalog eviction cannot relieve the mutation budget: pending mutations are
protected, so deleting cached songs does not shrink the mutation store. The
policy is therefore two distinct ladders sharing one accounting seam:

| pressure | measured-pressure display | hard consequence |
|---|---|---|
| **mutation budget** (LF-T3) | soft threshold → warning surfaced; no higher display tier | refuse threshold reached → refuse **new** writes |
| **storage pressure** (LF-T4) | soft and higher thresholds → warning display, more urgent as it climbs | *(measurement alone has no hard consequence — see below)* |

Measured pressure, at any level, only ever changes what the sync overview
displays — it never triggers eviction by itself. The one production
eviction trigger, for either ladder, is a write that actually fails at the
storage layer, and that failure gets exactly one evict-and-retry attempt
(see "Write path" below). The remedy for a full mutation budget is
different: sync or discard, and the refusal error message says so.

### D2 — Content-derived byte accounting, no platform quota API

Footprint is estimated from row content with SQL aggregates
(`SUM(length(col))` over the text and JSON columns, plus a fixed per-row
overhead), not from `dart:io` file size or `navigator.storage.estimate()`.

Rationale: the same code path runs on native and web, it is deterministic
against an in-memory database, and it introduces no web-only branch that this
slice cannot verify. The ADR records explicitly that this is a **footprint
proxy**, not true on-disk size.

### D3 — Enforcement by decorator

`BudgetedPlanningMutationStore implements PlanningMutationStore` wraps
`DriftPlanningMutationStore` and is the single enforcement point.

Rejected alternatives:

- **Check inside `DriftPlanningMutationStore._upsertRecord`.** One choke point,
  least code — but `saveSyncAttemptResult` and `retryMutation` also go through
  `_upsertRecord`, so a blanket check there would block status updates and
  retries. Wrong behaviour, and it would couple the planning store to the
  catalog database.
- **Check in `PlanningWriteService`.** Better error vocabulary, but the mutation
  store is public and called from more than one place, so the guarantee would
  not be tight.

The decorator guards only the `record*` methods — the ones that can introduce a
new aggregate. `saveSyncAttemptResult`, `retryMutation` and `clearMutation` pass
through unguarded: they modify or shrink an existing row. Guarding them would
make a full store unrecoverable, because discard itself would become impossible.

### D4 — Protection order

**Never evicted:**

- pending planning mutations *and* pending song mutations — unsynced user intent
  with no other copy;
- the planning projection — offline it is the *only* readable view, so dropping
  it blinds the user precisely when they cannot re-fetch;
- cached catalog **summaries** — they back the browsable song list; dropping
  them offline blinds the list for the same reason;
- the last-known identity store — ADR-020 offline-authenticated state.

**Droppable:** cached catalog **sources** (`CachedCatalogSources` — the
lyrics/ChordPro bodies) for songs that have **no pending song mutation**. They
are the largest payload by far, they are re-fetchable on reconnect, and a song
whose body is evicted still appears in the list. Excluding songs with pending
mutations keeps the rule absolute: eviction never touches a row that unsynced
intent depends on.

This supersedes the "one active snapshot" framing in `architecture.md`'s Offline
Strategy section, which LF-T4 was reasoned against.

### D5 — Native-only verification (the S12 tension, resolved)

LF-T4's risk is most acute on web, where IndexedDB is subject to silent browser
eviction, and there is no web offline e2e harness — Phase 3 added only a
`flutter build web` compile gate (DX-2).

**Chosen: implement and verify on native; document the web assumptions as
unverified.** The alternative — building a `chromedriver` lane first — is new CI
infrastructure that would consume this phase on its own.

Consequences, stated in the ADR rather than left implicit:

- Every threshold and the eviction trigger are verified against the native
  Drift/sqlite3 backend only.
- Because accounting is content-derived (D2), the *logic* is
  platform-independent; what is unverified is whether the browser evicts
  underneath us regardless, and whether the estimate tracks real IndexedDB
  usage.
- `docs/deferred/2026-06-29-web-offline-e2e.md` stays open, with its trigger
  condition unchanged: it is still a prerequisite for relying on IndexedDB
  capacity assumptions.

### D6 — Thresholds

Injectable constants on `LocalStorageBudget`, so tests run against tiny budgets:

| threshold | default | rationale |
|---|---|---|
| mutation warn | 1 MiB | ≈ a few thousand mutations; far past any normal offline span |
| mutation refuse | 4 MiB | bounds pathological growth without ever biting normal use |
| total warn | 128 MiB | native-informed heuristic |
| total critical | 192 MiB | raises the surfaced pressure classification; it does not itself trigger eviction |

These are deliberately sized to be unreachable in normal use. A budget that
bites during ordinary rehearsal planning would be the wrong budget: the purpose
is to make growth **bounded and observable**, and to give a signal before the
storage substrate fails, not to ration everyday work. The total thresholds are
heuristics on native and explicitly unverified on web (D5).

**Not implemented: proactive threshold eviction.** `LocalStorageMonitor` is
read-only — it measures and classifies but never calls the evictor. The
accepted contract is failure-driven only: `SongCatalogEvictor.evictDroppable()`
runs exactly once, from inside `BudgetedPlanningMutationStore`'s write-failure
branch, regardless of the last measured pressure. See "Write path" below and
ADR-028's D1/D6 for the full reasoning.

## Design

### Components

| unit | responsibility | depends on |
|---|---|---|
| `LocalStorageFootprint` | value type: `mutationBytes`, `mutationCount`, `projectionBytes`, `catalogBytes`, `totalBytes` | — |
| `LocalStorageBudget` | thresholds + the pressure classification for a footprint | `LocalStorageFootprint` |
| `LocalStoragePressure` | `ok` / `warning` / `critical` | — |
| `PlanningStorageAccountant` | measures mutation and projection bytes from the planning database | `PlanningLocalDatabase` |
| `CatalogStorageAccountant` | measures catalog bytes | `SongCatalogDatabase` |
| `LocalStorageMonitor` | combines both accountants into a footprint + pressure; **on demand**, not per write | both accountants, `LocalStorageBudget` |
| `SongCatalogEvictor` | `Future<int> evictDroppable()` — deletes cached catalog sources for songs without a pending song mutation, returns estimated bytes freed | `SongCatalogStore` |
| `BudgetedPlanningMutationStore` | the enforcement decorator | `PlanningMutationStore`, `PlanningStorageAccountant`, `SongCatalogEvictor`, `LocalStorageBudget` |

### Write path

On every guarded `record*` call:

1. Measure **mutation** bytes only — one aggregate over a small table. The
   projection and catalog are not measured per write; they are the monitor's
   job.
2. If at or above the mutation refuse threshold → throw
   `PlanningMutationBudgetExceededException`. The write does not happen and
   existing pending mutations are untouched.
3. Delegate the write. If it throws a storage failure → evict droppable catalog
   once → retry the write once → if it fails again, wrap and rethrow as
   `LocalStorageWriteFailure`.

Both exceptions travel through `PlanningWriteService` to the UI. Neither is
swallowed.

### Warning surface

`LocalStorageMonitor` is exposed through a provider consumed by the existing
unified sync status surface. No new UI concept: this phase is not UX work.

### Committed-storage revision seam

Added after the initial implementation to fix a staleness gap: the sync
overview's `localStorageFootprintProvider` used to measure once per provider
mount and never again, so a mounted listener kept showing a stale figure
after later commits. Every concrete storage boundary that can change the
measured footprint (planning mutation record/retry/result/clear, planning
projection replace/upsert/delete/order/cleanup, catalog snapshot
replace/mutation-save/delete/reconcile/clear/cleanup, and a
droppable-source eviction that actually removed rows) now takes an optional
`LocalStorageFootprintChanged` callback and invokes it once, after its own
commit. In production all of them are wired to the same callback, which
bumps one monotonic `localStorageFootprintRevisionProvider`;
`localStorageFootprintProvider` watches that revision before it measures, so
it remeasures on every real change while staying mounted. Delete/clear paths
key off affected-row counts, and an idempotent upsert whose persisted
payload is already identical emits nothing. See ADR-028 D7 for the full
contract, including the partial-failure cases (eviction that freed rows but
whose retry still failed; a batch that commits some rows before a later
failure).

### Squash correctness fix

`recordSessionDelete`, when collapsing a pending `sessionCreate`, also deletes
the pending `session_item` mutations belonging to that session, inside the same
transaction that deletes the session row.

## Testing

Extends the existing adversarial suite under
`apps/lyron_app/test/offline/adversarial/`. No parallel harness.

Contracts, written before the implementation:

1. **Squash preserves exactly-once sync (ADR-019) and OCC base-version
   semantics.** For each fold path: exactly one row per aggregate survives; the
   surviving record carries the correct `baseVersion` and the *earliest*
   `originSnapshot`; a folded record reconciles without manufacturing a false
   conflict.
2. **Pending mutations are never evicted.** Eviction with pending planning
   mutations *and* pending song mutations present leaves both
   `CachedPlanningMutations` and `CachedCatalogSongMutations` untouched, and
   leaves the source rows of songs carrying a pending mutation in place.
3. **The projection and the catalog summaries are never evicted.** Same test
   shape: planning projection tables and `CachedCatalogSummaries` intact, only
   unreferenced `CachedCatalogSources` removed.
4. **Refusal is recoverable.** With the budget exhausted, `record*` throws, but
   `clearMutation` and `retryMutation` still succeed — a full store can always
   be drained.
5. **The storage-failure contract, promoted from probe to enforcement.**
   `storage_pressure_probe_test.dart`'s `_InsertFailingExecutor` now drives the
   full chain: failure → eviction attempted → one retry → typed
   `LocalStorageWriteFailure` propagates. The probe's characterization comment
   is replaced by a contract statement.
6. **No orphaned session-item mutations.** Pending `sessionCreate` plus pending
   item creates, then `sessionDelete` → session row and all its item rows are
   gone; no row remains that could fail `dependencyBlocked`.
7. **Accounting is monotone and bounded.** Footprint grows with content and
   shrinks on `clearMutation`; a fixed corpus produces a stable estimate.

Added for the committed-storage revision seam
(`test/application/sync/unified_sync_providers_test.dart`,
`test/application/storage/song_catalog_evictor_test.dart`,
`test/offline/planning/planning_local_store_test.dart`,
`test/offline/song_catalog/song_catalog_store_test.dart`,
`test/offline/planning/planning_mutation_store_test.dart`,
`test/offline/adversarial/storage_pressure_contract_test.dart`):

8. **A mounted footprint provider remeasures.** With
   `localStorageFootprintProvider` already subscribed, advancing
   `localStorageFootprintRevisionProvider` and changing the underlying
   measurement produces a second measurement and a changed pressure
   classification.
9. **Each concrete storage boundary calls its callback after its own commit,
   not before it, and not for a throw or a true no-op.** Covered
   independently for planning mutation record/retry/result/clear, planning
   projection replace/upsert/delete/order/cleanup, catalog snapshot
   replace/mutation-save/delete/reconcile/clear/cleanup, and eviction.
10. **An idempotent upsert whose persisted payload is already identical does
    not emit a revision.**
11. **Eviction advances the revision even when the guarded write's retry
    later fails**, and **earlier committed rows advance the revision when a
    later outer batch operation fails** — the revision tracks what actually
    committed, not a top-level action's final result.

## Documentation

- **ADR** for the budget and eviction policy, carrying D1–D6, and stating the
  native-only verification decision and its unverified web consequences.
- `docs/architecture/architecture.md` — Offline Strategy: replace the "one
  active snapshot" framing with the protection order and the accounting seam.
- `docs/testing/testing-strategy.md` — the promoted storage contract and the
  budget/eviction contracts.
- `docs/architecture/repository-review-2026-06-22.md` — mark LF-T3 and LF-T4
  fixed in the commit that resolves them, using the existing
  `~~struck~~ **Done (...)**` convention and the §6 status-block style.
- `docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md` — removed in the
  same commit that resolves it, per `docs/deferred/README.md`.
- `docs/deferred/2026-06-29-web-offline-e2e.md` — left open, unchanged.
