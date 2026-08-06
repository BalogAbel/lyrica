# ADR-028: Local Storage Budget and Eviction Policy

- Status: Accepted
- Date: 2026-07-30
- Spec: `docs/specs/2026-07-30-lft3-mutation-budget-and-lft4-storage-eviction.md`
- Plan: `docs/plans/2026-07-30-lft3-mutation-budget-and-lft4-storage-eviction.md`
- Findings: LF-T3, LF-T4
- Closes: `docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md`
- Amended: 2026-08-04 — Spec:
  `docs/specs/2026-08-04-storage-recovery-boundary-and-budget-admission.md`
  (PR #64 review findings P1a, P1b, P2; adds D8, D9, D10 below)
- Amended: 2026-08-04 — same spec, "What implementation found" closed by a
  second, more targeted re-review round (commits `ba62067`, `dc6a401`,
  `2b84978`, `39da44f`): corrects D3, extends D8 and D9
- Amended: 2026-08-06 — Spec:
  `docs/specs/2026-08-06-in-flight-create-cancellation.md`. Corrects D10's
  rationale: the in-flight-create-cancellation work (see ADR-030's follow-up
  of the same name) split the delete-collapses-pending-create case into
  three branches, only one of which still shrinks the store. D10's
  admission itself is unchanged; only the stated reason is restated to
  match what the three branches actually do.
- Amended: 2026-08-06 — PR #64 review finding M1 (commit `431a051`):
  corrects D8's "one recovery boundary, shared by every growing local
  write" claim, which was concretely false for the planning mutation path
  until this commit, not merely narrower than stated the way the earlier
  P1a amendment above was.

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

| pressure | measured-pressure display | hard consequence |
|---|---|---|
| **mutation budget** (LF-T3) | soft threshold → warning surfaced; no higher display tier | refuse threshold reached → refuse **new** writes |
| **storage pressure** (LF-T4) | soft and higher thresholds → warning display, more urgent as it climbs | *(measurement alone has no hard consequence — see below)* |

Measured pressure is a monitoring and user-facing display concern only;
classification never triggers eviction by itself, at any level. The
**only** production eviction trigger, for either ladder, is a write that
actually fails at the storage layer: that failure evicts droppable catalog
data once and retries the write once, independent of whatever the last
measured display level was. The remedy for a full mutation budget is
different: it is to sync or discard pending work, and the refusal error
carries that message. See "On a storage write failure, evict once and
retry once" below for the failure-triggered path, and "Rejected: proactive
threshold eviction" for why a high measurement does not also evict.

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

`saveSyncAttemptResult`, `retryMutation` and `clearMutation` are **never
admitted against the mutation budget**. This is deliberate, not an
oversight: they modify or shrink an existing row rather than growing one,
and guarding them would make a full store unrecoverable. Once the mutation
budget is exhausted, `clearMutation` is the only way out — discard has to
keep working unconditionally, or the budget becomes a trap with no recovery
path.

**Corrected, 2026-08-04 (second PR #64 re-review round, commits `ba62067`,
`dc6a401`, `2b84978`, `39da44f`).** This section previously said the three
writes above "pass straight through unguarded," full stop. That was stale in
a way that mattered: unguarded by the *budget*, yes, but a targeted
re-review found that `saveSyncAttemptResult` also needs the storage-recovery
boundary (D8), and that all three need to share the per-context write queue
(D9) the nine `record*` admissions already used — for a race that has
nothing to do with the budget itself (see D9's second amendment). The three
writes are not one undifferentiated group; they split three ways:

| write | budget admission (D1/D10) | write queue (D9) | storage recovery (D8) |
|---|---|---|---|
| the nine `record*` methods | yes, unless the write provably collapses a pending create (D10) | yes | yes |
| `saveSyncAttemptResult` | never | yes | yes |
| `retryMutation` | never | yes | no |
| `clearMutation` | never | yes | no |

`saveSyncAttemptResult` needs recovery because it is the only one of the
three that can *grow* the stored row — it writes through the same
`_upsertRecord` path as the others, adding `errorCode`/`errorMessage` —
so an unrecovered storage failure on it would surface a raw exception
instead of the typed `LocalStorageWriteFailure` every other growing local
write gets (D8). It matters more than that here: `saveSyncAttemptResult` is
also the durable marker `PlanningMutationSyncController._run` writes
immediately after a successful remote send, recording the mutation as
`accepted`. If that write fails and the failure is swallowed rather than
recovered, the record stays `pending`, and the next sync **resends a
mutation the backend already accepted** — an ADR-019 exactly-once violation
reached through a storage failure, not a sync-logic bug. That is exactly why
this write can never be budget-admitted either: refusing it for budget
reasons would strand the very marker that prevents the resend, on the one
write of the three whose failure has the worst consequence.

`retryMutation` clears `errorCode`/`errorMessage` and rebases the base
version on an already-existing row — it shrinks or holds steady, never
grows — and `clearMutation` is a pure delete. Neither can produce the kind
of storage-layer growth failure D8 exists to recover from, so neither needs
the recovery boundary; they only need the same queue ordering as every other
write for their context, for the race D9's second amendment closes.

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

This decorator's admission logic is amended below without changing which
methods are budget-admitted: D9 serialises the measure/check/write sequence
per context and, as of the second re-review round, also queues the three
writes in the table above; D10 admits a delete that collapses a still-pending
create regardless of budget.

### D8 — One recovery boundary, shared by every growing local write

**Amendment, 2026-08-04, closing P1a from the PR #64 review.** This section
originally described the eviction/retry policy as something
`BudgetedPlanningMutationStore._guardedWrite` implemented inline. That was
narrower than the ADR's own framing ("a write that reaches the delegate and
fails at the storage layer is treated as storage pressure"):
`SongCatalogEvictor.evictDroppable()` was reachable from exactly that one
write path. Song mutation writes, catalog snapshot replacement, and
planning projection writes went straight to Drift, so a storage failure on
any of them surfaced a raw Drift exception instead of the typed
`LocalStorageWriteFailure` this ADR claimed for local writes generally.

`LocalStorageWriteRecovery.guard<T>(Future<T> Function() write)`
(`application/storage/local_storage_write_recovery.dart`) is now the single
implementation of the policy this section describes:

1. run `write`;
2. on a `LocalStorageDomainRejection` (see below), rethrow untouched —
   retrying would fail identically, and evicting would destroy cached data
   for nothing;
3. on an `Error`, rethrow untouched — unchanged from the original
   narrowing: an `Error` subclass (`ArgumentError`, `StateError`,
   `TypeError`, ...) signals a programming defect, never storage pressure,
   and must never be misreported as such;
4. on any other `Exception`, evict droppable catalog sources once via the
   injected `SongCatalogEvictor`, retry `write` once, and wrap a second
   failure as `LocalStorageWriteFailure`. If eviction itself throws, the
   write is never retried and the **original** write error is surfaced as
   the failure's cause with `bytesFreedByEviction: 0` — unchanged from the
   original narrowing: the caller needs to act on the write failure, and
   the eviction failure is a secondary symptom, plausibly of the same
   underlying condition.

It is injected into the Drift stores the same way `onStorageFootprintChanged`
already is (D7): an optional, nullable constructor parameter, always
supplied by `core_providers.dart`/`planning_providers.dart`/
`song_catalog_providers.dart` in production, `null` where a test constructs
a store directly — in which case the write runs unguarded.

**Correction, 2026-08-06 (PR #64 review, M1, commit `431a051`).** This
section's own heading claims one recovery boundary shared by every growing
local write. That was false for `BudgetedPlanningMutationStore`:
rather than taking the provider-supplied `LocalStorageWriteRecovery`
instance the way `DriftPlanningLocalStore` and `DriftSongCatalogStore`
already did, its constructor built its own internally from an injected
`SongCatalogEvictor` (`_recovery = LocalStorageWriteRecovery(evictor:
evictor)`). Production wiring in `planning_providers.dart` never routed
planning mutation writes through `localStorageWriteRecoveryProvider` at
all — the provider was registered and consumed by the other two stores, but
partly dead code for this one. `BudgetedPlanningMutationStore` now takes an
injected `LocalStorageWriteRecovery recovery` parameter in place of the
evictor, and `planning_providers.dart` passes
`ref.watch(localStorageWriteRecoveryProvider)` — the exact same instance
every other guarded store already shares. There is no behavioral difference
for a single instance today (the two `LocalStorageWriteRecovery`s were
constructed identically, so `guard`'s policy was identical either way) —
which is why this is a structural correction, not a behavioral one — but
the *claim itself* was concretely false until this commit, not merely
narrower than stated the way the P1a amendment above was. Pinned by a new
test in `footprint_production_wiring_test.dart` asserting
`planningMutationStoreProvider`'s store calls through the exact
`localStorageWriteRecoveryProvider` instance the provider graph supplies,
using a counting subclass rather than a mock so the assertion is "this
instance was called," not merely "some instance was called."

**Which writes are guarded, and the rule that decides it.** Every local
write that can increase stored bytes:

- `BudgetedPlanningMutationStore`'s nine `record*` methods (unchanged; the
  class no longer implements the eviction/retry policy itself, it delegates
  to this boundary after its own budget/collapse admission decision — D3,
  D9, D10);
- `BudgetedPlanningMutationStore.saveSyncAttemptResult` (2026-08-04, second
  PR #64 re-review round) — added because it is the one write of the three
  pass-through methods that can grow the stored record
  (`errorCode`/`errorMessage`); see D3's table and the exactly-once
  reasoning there for why this one needed recovery and the other two did
  not;
- `DriftPlanningLocalStore.replaceActiveProjection`, `upsertSyncedPlan`,
  `upsertSyncedSession`, `upsertSyncedSessionItem`;
- `DriftSongCatalogStore.replaceActiveSnapshot`, `saveSongMutation`, and
  `reconcileSyncedSong` — reconcile inserts a new summary/source row pair
  the first time a song syncs, which grows the store the same way a
  snapshot replacement does, even though it also deletes the now-resolved
  mutation row in the same transaction.

Deliberately **not** guarded: every pure delete (`deleteSong`,
`clearSongMutation`, `deleteCatalog`, `deleteCatalogsForUser`,
`deleteSyncedSession`, `deleteSyncedSessionItem`, `deletePlanningData`,
`deletePlanningDataForUser`, `deletePlanningProjection`) and the two
reorder methods (`replaceSyncedSessionOrder`, `replaceSyncedSessionItemOrder`,
which update `position`/`version` on rows that already exist rather than
inserting). There is nothing to recover from on a pure delete or shrink,
and guarding one would add an eviction attempt to the very operation that
frees space. `BudgetedPlanningMutationStore.retryMutation` and
`.clearMutation` are not guarded for the same reason — see D3's table.

**The marker interface, and why not a hardcoded list.** A caller opts an
exception into domain-rejection treatment by having its class implement
`LocalStorageDomainRejection` — a bare marker interface owned by
`application/storage` — rather than the generic boundary hardcoding
concrete exception types from every module that uses it. `application/storage`
sits below both `application/planning` and `offline/song_catalog`; a
hardcoded list would force it to import their exception types, which is a
layering violation the marker avoids. Three exceptions implement it today:
`LocalPlanningSlugConflictException`, `LocalSongSlugConflictException`
(added by this amendment — `saveSongMutation`'s slug-conflict check throws
mid-write and must not be misread as storage pressure), and
`PlanningProjectionAbortedException`.

**`PlanningProjectionAbortedException` is a cooperative-cancellation
signal, not a failure.** `DriftPlanningLocalStore._ensureProjectionCurrent`
throws it when the caller's `shouldContinue` reports that a newer refresh
has superseded this one; `PlanningSyncController` already catches it
explicitly when a refresh is superseded. Without the marker, a superseded
refresh would have been read by the shared guard as storage pressure,
evicting droppable catalog data for no benefit and retrying the write
straight into the same abort.

**No eviction recursion.** `SongCatalogEvictor.evictDroppable()` deletes
only cached song sources, via a raw statement against `SongCatalogDatabase`
directly — it never goes through any guarded store method. So a guarded
write's recovery path can never call back into a guard: eviction is
structurally outside every write this boundary protects, and shrinking
writes are never guarded in the first place.

### D9 — Serialise measure, check and write per context

**Amendment, 2026-08-04, closing P1b from the PR #64 review.**
`_guardedWrite` measured the mutation store's footprint, `await`ed, checked
the threshold, then `await`ed the write — three separate `await` points
with nothing serialising the sequence between them. Two concurrent
`record*` calls for different aggregates in the same context could both
measure the same pre-write footprint, both pass the check, and both write,
overshooting the "at most one mutation past the threshold" bound stated
above.

`BudgetedPlanningMutationStore` now runs measure, check, and the delegated
write as one unit per `(userId, organizationId)`, via a
`Map<String, Future<void>> _writeQueue` keyed the same way as
`PlanningMutationSyncController._inFlight`. It is a FIFO queue, not a
single-flight coalescer: unlike a sync trigger, every `record*` call must
run its own write and report its own outcome rather than share another
call's result, so each caller chains onto the queue instead of being handed
someone else's future. A write's failure is neutralised before being
published as the new queue tail, so it never poisons the next queued write
for the same context; the map entry is dropped once nothing is queued
behind it, via an `identical()` check mirroring the cleanup already used by
`PlanningMutationSyncController` and `SongMutationSyncController`.

Serialising per context rather than globally keeps a write for one
user/organization from blocking a write for another. The overshoot bound
this ADR originally stated now actually holds: only one admission can be in
flight per context at a time, so the store can overshoot its refuse
threshold by at most one mutation, not by however many writes raced.

Budget logic itself is unchanged by this amendment; it now runs inside
`_admitAndWrite`, called once per queued turn.

**Second amendment, 2026-08-04, closing the collapse-versus-`clearMutation`
race found by a second, more targeted re-review round (commits `ba62067`,
`dc6a401`, `2b84978`, `39da44f`).** The queue above was built to serialise
the nine `record*` admissions against each other; it did not originally
include `saveSyncAttemptResult`, `retryMutation`, or `clearMutation`. That
gap was itself a race, independent of the budget: a `record*` call's
collapse decision (`_collapsesPendingCreate`, read once, early, before the
write's queued turn even starts) and the delegate's own re-check of the same
aggregate (read again, late, inside its own transaction, once the queued
turn actually runs) are two separate reads of the same row. `clearMutation`
is exactly what `PlanningMutationSyncController` calls, for that same
aggregate, immediately after a mutation is accepted. Unqueued, a concurrent
`clearMutation` could land in the gap between those two reads: the
decorator's early read still saw the pending create and skipped the budget
check on that basis, but by the time the delegate's own late re-check ran,
`clearMutation` had already removed it — so the delegate found nothing left
to collapse and wrote a brand-new delete row instead, one that had never
passed a budget check at all. A falsification test in
`test/application/planning/budgeted_planning_mutation_store_test.dart`
("the collapse race") reproduced exactly this, deterministically, with a
Completer-gated fake delegate that pauses `recordSessionDelete` between the
decorator's collapse decision and its own internal re-check.

`clearMutation` and `retryMutation` now join the same per-context
`_writeQueue` the nine `record*` admissions use, via a `_queuedWrite` helper
that provides ordering only — no budget, no recovery. `saveSyncAttemptResult`
joins it too, via a `_recoveredWrite` helper that adds the D8 recovery
boundary on top of the ordering (never the budget — D3's table). Once a
`record*` call's turn starts, no other write for the same context —
including a `clearMutation` or `retryMutation` for a different aggregate in
that context — can run until it finishes, so the collapse decision and the
delegate's re-check can no longer be separated by an intervening write for
that context.

### D10 — Admit deletes that collapse a pending create's row

**Amendment, 2026-08-04, closing P2 from the PR #64 review. Rationale
corrected, 2026-08-06 — see the note at the end of this section.**
`recordSessionDelete` and `recordSessionItemDelete` were budget-guarded
like every other `record*` write, even though both can *shrink* the store:
when the aggregate they target still holds a still-pending create (a
session or session item that never reached the backend), the delete
collapses that create rather than adding a row; `recordSessionDelete`
additionally removes that session's pending item and item-order rows. At
an exhausted budget, both were refused before the delegate ever ran, so
the ordinary delete affordance could not drain a full store. The
documented escape hatch, `clearMutation` via discard, still worked, so
this was not a trap — but refusing a write that would free space was wrong
on its own terms.

`_guardedWrite`/`_admitAndWrite` now take an optional
`Future<bool> Function()? isCollapse` that, when it resolves `true`, skips
the budget check entirely for that write. It is wired for
`recordSessionDelete` and `recordSessionItemDelete` via
`_collapsesPendingCreate`, which reads the existing mutation for the target
aggregate through the same `PlanningMutationStore.readMutation` contract
the delegate itself uses, keyed the same way, and compares only `kind` —
mirroring, not duplicating, `DriftPlanningMutationStore`'s own
`existing?.kind == <pendingCreateKind>` collapse check inside those same
two methods, so the guard and the delegate cannot disagree about what
counts as a collapse.

This is decided from store state, not from the method name: a
`recordSessionDelete` against a session that is **not** a pending create
(including one with no local mutation at all, or one folded into a pending
edit/rename) genuinely adds a delete row and stays subject to the budget
exactly like any other write.

**Correction, 2026-08-06** (`docs/specs/2026-08-06-in-flight-create-cancellation.md`;
see ADR-030's "In-Flight Create Cancellation Follow-Up" for the mechanism).
The in-flight-create-cancellation work split what this section describes as
a single collapse into three branches on the existing row's `syncStatus`,
only one of which still shrinks the store:

1. **pending, not in flight** — the row is physically removed, exactly as
   described above. This one shrinks.
2. **`sending`** (the create's own remote send is in flight right now) —
   the row is kept and rewritten as a `cancelling` tombstone, holding the
   delete intent until the create's outcome is known. No shrink: one row
   is replaced by one row.
3. **`accepted`-but-uncleared** (the backend already confirmed the create;
   the local clear has not run yet) — the row is kept and rewritten as a
   real pending delete. No shrink, for the same reason.

`_collapsesPendingCreate`'s `kind`-only check still admits all three,
unchanged — a `kind` match is exactly the right condition for all three. It
is the *reason* for the admission that this section's original title
overstated: "admitted because it provably shrinks the store" only ever
described branch 1. Branches 2 and 3 are admitted because refusing a
delete in the `sending` or `accepted` window at an exhausted budget would
strand exactly the delete intent the in-flight-create-cancellation work
exists to preserve — a far worse outcome than the handful of bytes a
same-row rewrite may add — and because a rewrite in place cannot grow the
store meaningfully either way, since it replaces one row with one row. So,
restated: this write is admitted regardless of budget because refusing it
would either strand user intent (branches 2 and 3) or block the only way
to drain a full store (branch 1), and in no case can it grow the store
meaningfully. The admission mechanism did not change; only the rationale
above is corrected to match what the code has done since the in-flight
work landed.

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

The 2026-08-04 widening (D8) that extends the same recovery boundary to
`DriftSongCatalogStore` and `DriftPlanningLocalStore` is verified the same
way — native Drift/sqlite3 fault injection only. It neither narrows nor
widens the web/IndexedDB gap stated above.

### D6 — Thresholds

Injectable constructor parameters on `LocalStorageBudget`, so tests can run
against tiny budgets without waiting for real data volume:

| threshold | default | rationale |
|---|---|---|
| mutation warn | 1 MiB | roughly a few thousand mutations; far past any normal offline span |
| mutation refuse | 4 MiB | bounds pathological growth without ever biting normal use |
| total warn | 128 MiB | native-informed heuristic |
| total critical | 192 MiB | raises the surfaced pressure classification from warning to critical; it does not itself trigger eviction (see D1) |

These are deliberately sized to be unreachable in normal use. A budget that
bites during ordinary rehearsal planning would be the wrong budget: the
purpose is to make growth **bounded and observable**, and to give a signal
before the storage substrate fails, not to ration everyday work. The total
thresholds are heuristics on native and explicitly unverified on web (D5).

**Rejected: proactive threshold eviction.** An earlier draft of this policy
also had `LocalStorageMonitor` trigger `SongCatalogEvictor.evictDroppable()`
whenever a measurement crossed `totalCriticalBytes`, on the theory that
eviction should run before a write ever has the chance to fail. No production
path implements that second trigger, and this ADR now describes the policy
that actually ships: `LocalStorageMonitor.measure()` is read-only and never
calls the evictor. `LocalStorageBudget.classify()` only classifies a
footprint into `ok` / `warning` / `critical` for the sync overview to
display; classification has no side effect. Eviction happens exactly once,
from inside `BudgetedPlanningMutationStore._guardedWrite`'s failure branch,
regardless of what the last measured pressure was. A store that is measured
critical but whose writes keep succeeding is never evicted; a store that is
measured `ok` but whose write throws (a real disk/quota failure can occur
before the measured total looks large, since accounting is a proxy, not the
platform's own quota signal) is evicted immediately. Proactive eviction
remains a real option for a future slice, but adding it now would be a new
behavior change, not a documentation correction.

### D7 — Committed-storage revision seam

`localStorageFootprintProvider` used to measure once per provider mount and
never again, so a long-lived listener (the sync overview) could keep
displaying a stale byte count and pressure classification after mutation
writes, clears, sync reconciliation, or catalog-source eviction changed what
was actually on disk.

Every concrete storage boundary that can commit a change to the
SQL-measured footprint now takes an optional `LocalStorageFootprintChanged`
callback (`void Function()`, declared in
`local_storage_footprint_revision.dart`) and invokes it once, after the
concrete commit: `DriftPlanningMutationStore`'s record/retry/result/clear
paths, the planning projection's replace/upsert/delete/order/cleanup paths in
`planning_local_store.dart`, the catalog store's snapshot
replace/mutation-save/delete/reconcile/clear/cleanup paths in
`song_catalog_store.dart`, and `SongCatalogEvictor.evictDroppable()`. In
production, `core_providers.dart` wires all of them to the same
`localStorageFootprintChangedProvider`, whose callback increments a single
monotonic `localStorageFootprintRevisionProvider` (a `StateProvider<int>`).
`localStorageFootprintProvider` watches that revision before it measures, so
each bump forces a remeasurement even while the provider stays mounted — no
UI-level polling or manual invalidation call is needed.

Two behaviors follow directly from "after the concrete commit, and only for
an actual change":

- **Delete and clear paths key off affected-row counts.** A `DELETE`/clear
  that matched zero rows emits nothing — there was nothing to remeasure.
- **Idempotent upserts compare the persisted payload before deciding to
  emit.** A write whose incoming content is identical to what is already
  stored is a true no-op and emits nothing, so re-saving unchanged data does
  not thrash the revision or force a redundant measurement.

The callback fires from inside the storage boundary itself, not from a
controller or screen, so every caller gets the same guarantee without a
mechanical per-call-site edit. This also means the revision still advances
for a partially-successful operation: an eviction that freed rows but whose
subsequent guarded write retry still failed emits its callback for the rows
it actually deleted, and earlier rows committed by an outer batch that later
returns an error still advance the revision for what was actually
persisted before the failure. The revision is a pure invalidation seam over
a monotonic counter — it carries no byte or count information itself; SQL
accounting inside the accountants remains the only source of the measured
values.

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
- `test/application/sync/unified_sync_providers_test.dart` — a mounted
  `localStorageFootprintProvider` remeasures and its classification changes
  after the revision provider advances, pinning D7's watch-before-measure
  contract.
- `test/application/storage/song_catalog_evictor_test.dart` — the eviction
  callback fires exactly once for a commit that actually deleted rows and
  not for the following true no-op, and does not fire when measurement
  throws before any delete runs.
- `test/offline/planning/planning_mutation_store_test.dart` — `recordPlanCreate`
  invokes the injected callback after its commit and not before it, not after
  a throw (a duplicate-slug rejection), and `clearMutation` does not invoke it
  for a true no-op (clearing a nonexistent mutation). The other planning
  mutation record paths (`recordPlanEdit`, `recordSessionCreate`,
  `recordSessionRename`, `recordSessionDelete`, `recordSessionReorder`,
  `recordSessionItemCreateSong`, `recordSessionItemDelete`,
  `recordSessionItemReorder`), plus `saveSyncAttemptResult` and
  `retryMutation`, are not covered by a callback assertion.
- `test/offline/planning/planning_local_store_test.dart` — `upsertSyncedPlan`
  invokes the callback after its commit, not for an identical-payload upsert
  that persists no change; `replaceActiveProjection` invokes it for a
  committed row even when a later operation in the same outer batch aborts,
  and not for an aborted projection replacement itself; `deletePlanningData`
  is confirmed not to fire for a true no-op (deleting a nonexistent user's
  data) but its own positive-fire case is not separately asserted. The
  session/session-item/order projection paths (`upsertSyncedSession`,
  `deleteSyncedSession`, `replaceSyncedSessionOrder`,
  `upsertSyncedSessionItem`, `deleteSyncedSessionItem`,
  `replaceSyncedSessionItemOrder`) and `deletePlanningDataForUser` are not
  covered by a callback assertion.
- `test/offline/song_catalog/song_catalog_store_test.dart` — `saveSongMutation`
  invokes the callback after its commit, not after a throw (a duplicate-slug
  rejection), and not for an identical-payload upsert that persists no
  change; `clearSongMutation` is confirmed not to fire for a true no-op
  (clearing a nonexistent mutation). `replaceActiveSnapshot`, `deleteSong`,
  `reconcileSyncedSong`, `deleteCatalog`, and `deleteCatalogsForUser` are not
  covered by a callback assertion.

Production wiring — that every one of these storage instances actually
receives the shared callback, whether or not its individual commit path has
a focused emission test — is guarded separately by
`test/application/storage/footprint_production_wiring_test.dart`.

- `test/application/storage/local_storage_write_recovery_test.dart`
  (2026-08-04, D8) — unit tests of `LocalStorageWriteRecovery.guard` itself,
  independent of any concrete store: success returns without touching the
  evictor; a `LocalStorageDomainRejection` and an `Error` both rethrow
  untouched with no eviction or retry; a plain `Exception` evicts once and
  retries once, returning the retry result; a second failure wraps as
  `LocalStorageWriteFailure` carrying the retry error and the freed byte
  count; and when eviction itself throws, the write is never retried and the
  original write error is the failure's cause with
  `bytesFreedByEviction: 0`.
- `test/offline/planning/planning_local_store_test.dart` (`DriftPlanningLocalStore
  storage recovery (D1)` group) and `test/offline/song_catalog/song_catalog_store_test.dart`
  (`DriftSongCatalogStore storage recovery (D1)` group) (2026-08-04, D8) —
  the same fault-injection shape `storage_pressure_contract_test.dart` uses,
  extracted to `test/support/insert_failing_executor.dart`, driven against a
  second, unwrapped `SongCatalogDatabase` backing the recovery's evictor so
  eviction reads/deletes never fight with the failing guarded database.
  Covers a failed `replaceActiveProjection`, `upsertSyncedPlan`,
  `upsertSyncedSession`, and `upsertSyncedSessionItem` (planning) and failed
  `saveSongMutation`, `replaceActiveSnapshot`, and `reconcileSyncedSong`
  (catalog): evict droppable sources, retry once, surface a typed
  `LocalStorageWriteFailure`, and confirm the failed write never landed.
  `replaceActiveProjection` and `saveSongMutation` are each also covered for
  the retry-succeeds case, and `PlanningProjectionAbortedException` / a song
  slug-conflict domain rejection are each confirmed to pass through
  untouched with zero evictions. Every write path guarded by D1 now has a
  dedicated fault-injection recovery test.
- `test/application/planning/budgeted_planning_mutation_store_test.dart`
  (2026-08-04 additions, D9/D10) — three concurrent `record*` calls for
  different aggregates in the same context, against a budget that admits
  only one: exactly one succeeds and the other two are refused (this test
  fails against the pre-amendment unserialised guard, which lands all
  three); concurrent writes for two different `(userId, organizationId)`
  contexts do not block each other, shaped with a `Completer` so it would
  deadlock forever if serialisation were global instead of per context; at
  an exhausted budget, `recordSessionDelete` against a pending
  `sessionCreate` succeeds and removes the session plus its pending item
  and item-order rows, and `recordSessionItemDelete` against a pending
  `sessionItemCreateSong` succeeds and removes it; and `recordSessionDelete`
  against a session that is **not** a pending create is still refused at an
  exhausted budget, proving the admission decision comes from store state,
  not the method name.
- `test/application/planning/budgeted_planning_mutation_store_test.dart`
  (2026-08-04, second re-review round, D3/D8/D9) —
  `saveSyncAttemptResult` is confirmed never refused for budget reasons even
  with the budget exhausted, and its stored status is confirmed to actually
  update (D3); a `saveSyncAttemptResult` recovery group, driven by a
  scripted insert-failure executor that fails by 0-indexed call number
  rather than a countdown (so a seed write can succeed before the write
  under test fails), covers both a storage failure that evicts droppable
  sources, retries once, and surfaces a typed `LocalStorageWriteFailure`
  when the retry also fails, and a transient failure that recovers on the
  retry with the record carrying the new status afterwards (D8); and "the
  collapse race" test, described under D9's second amendment above, pins
  that a `clearMutation` concurrent with a collapsing `recordSessionDelete`
  never results in a new delete row admitted without a budget check (D9).

- `test/application/storage/footprint_production_wiring_test.dart`
  (2026-08-06, M1) — `planningMutationStoreProvider` routes a guarded write
  through the `localStorageWriteRecoveryProvider` instance: a counting
  subclass of `LocalStorageWriteRecovery` overrides `guard` and is installed
  via the provider override, and a `recordPlanCreate` call is confirmed to
  invoke it. This test fails against the pre-fix code, which built its own
  `LocalStorageWriteRecovery` internally and never called the provider's
  instance at all — the guard count stays 0.

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
- A critical measured total is a monitoring/warning signal only; it does not
  evict by itself (D1, D6). The single production eviction trigger remains a
  storage write that actually fails.
- The sync overview's storage figure now refreshes after real commits
  instead of being measured once per provider mount (D7).
- (2026-08-04 amendment) The shared `LocalStorageWriteRecovery.guard` now
  covers every local write that can grow stored bytes, not only planning
  mutations — the "a write that reaches the delegate and fails at the
  storage layer is treated as storage pressure" claim this ADR made was
  narrower than the code until this amendment (D8).
- (2026-08-04 amendment) The mutation budget's overshoot bound ("at most one
  mutation past the threshold") is now actually enforced under concurrency
  via per-context serialisation; before this amendment it was a documented
  intention that concurrent writes could violate (D9).
- (2026-08-04 amendment) A delete that collapses a still-pending create is
  admitted regardless of the mutation budget, so an exhausted budget can no
  longer block the ordinary delete affordance from draining a store that is
  actually shrinkable (D10).
- (2026-08-04, second re-review round) `saveSyncAttemptResult` now shares the
  D8 recovery boundary, so a storage failure on the ADR-019 "already
  accepted" marker recovers the same way every other growing local write
  does instead of surfacing a raw exception and risking a resend of an
  already-accepted mutation; it remains permanently exempt from budget
  admission, deliberately, for that same reason (D3). All three previously
  unqueued pass-through writes (`saveSyncAttemptResult`, `retryMutation`,
  `clearMutation`) now share the per-context write queue with the nine
  `record*` admissions, closing a race where a concurrent `clearMutation`
  landing between a `record*` call's collapse decision and the delegate's
  own re-check could grow the store with a write that never passed a budget
  check (D9).
- (2026-08-06 amendment) `BudgetedPlanningMutationStore` now takes an
  injected `LocalStorageWriteRecovery` instead of building its own from an
  evictor, so D8's "one shared boundary" claim is now actually true for the
  planning mutation path — before this commit it was concretely false for
  that path, not merely narrower than stated (M1).
