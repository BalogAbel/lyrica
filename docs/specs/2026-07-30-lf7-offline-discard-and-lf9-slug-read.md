# Offline-Capable Discard and the Slug Read Path

> Status: Implemented
>
> Evidence: branch `feat/offline-durability-phase4`. Full closeout verification
> passed at `6ffa35c` — `./scripts/verify.sh` exit 0 with the local Supabase
> stack, database reset, demo-user provisioning and the skip-gated integration
> suites actually executed (1090 tests passed, 18 skipped, coverage 73.57%),
> all backend write contracts green, `./scripts/check-migrations.sh` exit 0,
> and `flutter build web --release` exit 0.
>
> The "Discard All offline" testing item landed later than its own task, in
> `26fc44d`, together with the fix for a retry that could report success after
> coalescing onto a background sync that never reprocessed its record. Song
> discard and sync were subsequently serialized by a context lease
> (`91ab491`, `857deee`), which this document's D1 now describes.

## Goal

Close `LF-7` and `LF-9` from `docs/architecture/repository-review-2026-06-22.md`.

- **LF-7** — dropping local intent must never require the network.
- **LF-9** — resolving a plan by slug must not re-read and re-merge the whole
  mutation set twice.

## Problem

### LF-7, restated from the current code

The review recorded this as `discard`/`retry` calling `_refreshPlanning()` first
in `planning_mutation_sync_controller.dart`. That is no longer where it lives:
the planning-side refactors in PR #62 and PR #63 made planning discard
local-first, and `PlanningMutationSyncController.discardMutation` now clears the
mutation before it attempts any sync. The finding was resolved on the planning
side as a side effect of unrelated work.

The violation is live on the **song** side, and it is worse than the original.

`SongMutationSyncController.discardMine` calls
`_remoteRepository.fetchSong(...)` **before** touching local storage. Offline
that throws `SongMutationSyncErrorCode.connectivityFailure`, which falls through
to the generic handler and:

1. writes `SongSyncStatus.conflict` onto the record — a *discard* attempt
   mutates the record into a conflict state it was never in;
2. rethrows.

So an offline discard does not merely fail: it leaves the song in a worse state
than before the user asked. Per-row discard at least surfaces a generic failure
snackbar. "Discard All" is worse still — `unified_sync_providers.dart` catches
per entry on a best-effort basis and `UnifiedDiscardController.discardAll` never
rethrows, so the user taps discard, nothing is discarded, some records silently
flip to conflict, and no error reaches them at all.

**Why the network call is not actually needed.** `discardMine` means "throw away
my local edit and go back to the server's version". `saveSongMutation` writes to
`CachedCatalogSongMutations`, leaving `CachedCatalogSummaries` and
`CachedCatalogSources` — the last known server copy — untouched. Dropping the
mutation row therefore *is* the restore: reads fall back to the snapshot. The
remote fetch only buys **freshness**, which is the refresh path's job, not
discard's.

### LF-7, retry

Retry legitimately needs connectivity. Today `retryMutation` on the planning
side marks the record pending, calls `syncPendingMutations`, and that swallows a
connectivity failure without rethrowing — so `_applyToGroup` sees no error and
shows no snackbar. The record's `errorCode` does become `connectivityFailure`,
which re-renders the row as a retryable failure, so the state change is visible
even though nothing tells the user the retry could not run. On the song side
there is no per-row retry action at all for retryable failures; retry is only
reachable through the header's full re-sync.

### LF-9, confirmed and re-scoped

`getPlanDetailBySlug` calls `getPlanSummaryBySlug`, which calls `listPlans()` —
a full projection listing plus a mutation read plus a merge over every plan —
then scans linearly for the slug, then calls `getPlanDetail(id)`, which reads the
mutation set **again** and merges **again**. One slug open costs two mutation
reads and two merges, and the merge cost scales with mutation count, which S12
just made a budgeted, monitored quantity.

Two facts change how this should be handled, both established by reading the
current code rather than the review:

1. **The store already has what is needed.** `PlanningLocalStore` exposes
   `readPlanSummaryBySlug` and `readPlanDetailBySlug`, both single indexed
   lookups. `PlanningLocalReadRepository` bypasses both.

2. **The merge is load-bearing for slug resolution.** `_mergePlanSummaries`
   synthesises a `PlanSummary` for each pending `planCreate` straight from the
   mutation's own fields, including its slug. Such a plan does not exist in the
   projection yet, so a naive switch to the store's slug lookup would stop
   finding plans created offline. Any optimisation must still resolve slugs
   against pending creates.

3. **The path is currently dead.** Nothing in `lib/` watches
   `planningPlanBySlugProvider` or `planningPlanDetailBySlugProvider`. The slug
   routes resolve through `planningPlanListProvider` and then fetch detail by
   id. The N+1 is real code with no live caller.

## Decisions

### D1 — Discard is a local operation; refresh is a separate, best-effort step

`discardMine` becomes local-first and never requires connectivity:

| record state | discard action | network |
|---|---|---|
| remote-deleted conflict | delete the local song | none |
| pending create | delete the local song — it never existed remotely | none |
| anything else (pending update, pending delete, conflict) | clear the song mutation; reads fall back to the cached snapshot | none |

After the local discard succeeds, the controller makes a **best-effort** catalog
refresh to pick up the freshest server copy. A failure there is swallowed: the
discard has already happened and is not undone by it.

Discard and sync share context-wide ownership keyed by `(userId,
organizationId)`, because sync snapshots all pending songs for that whole
context. They are mutually exclusive within one context. Concurrent sync
requests coalesce into the active sync; sync requests that arrive while a
discard owns the context coalesce behind that discard and take their pending
snapshot only after the discard lease is released. A per-row discard that
arrives while sync owns the context returns the typed
`SongDiscardResult.syncInProgress` outcome immediately and changes no local
state. This is an expected result, not a generic exception path.

The discard lease is acquired before the mutation record is read and is held
through the best-effort refresh. This prevents sync from observing an
intermediate point between the local clear/delete and completion of the discard
operation. The LF-7 success boundary is the durable local clear or delete: no
remote compensating write is issued, and success does not require the
freshness-only refresh to succeed.

**A discard never writes `SongSyncStatus.conflict`.** Marking a record as
conflicted is a *sync* outcome; it must not be a side effect of the user asking
to throw the record away.

This mirrors the planning side's clear-then-sync shape, so both halves of the
unified popup behave the same way.

### D2 — Retry stays online-only but fails informatively

Retry is not made offline-capable — it genuinely needs the backend. It must
report rather than fail silently:

- the planning retry path surfaces a connectivity failure to the caller so the
  popup can show it, instead of returning normally and leaving only a changed
  chip colour to convey it;
- "retry" while offline must not be indistinguishable from "retry succeeded".

### D3 — LF-9 is fixed even though the path is dead

The repository methods are part of the `PlanningRepository` interface and will be
correct if they are ever called. Fix them; do not delete them.

`getPlanDetailBySlug` reads the actionable mutation set **once** and resolves the
slug without listing every plan:

1. read the actionable mutations once;
2. resolve the slug — first against pending `planCreate` mutations (so
   offline-created plans stay findable), then via
   `PlanningLocalStore.readPlanSummaryBySlug`;
3. read the plan detail by id and merge **once**, reusing the mutation set from
   step 1.

`getPlanSummaryBySlug` gets the same treatment: resolve against pending creates,
then the store's indexed lookup, with no full listing.

The path still has no live caller. This change is interface correctness for a
repository method that may be called later; it is not a measured performance
win and must not be presented as one.

### D4 — Discard All has atomic admission, not cross-domain rollback

Unified **Discard All** acquires the song discard lease for the active
`(userId, organizationId)` before starting either song or planning work. If a
song sync already owns that context, the operation returns typed
`UnifiedDiscardResult.syncInProgress` immediately and neither domain changes.
The UI tells the user that sync is in progress and to try again when it
finishes; it does not route this expected contention through the generic
discard-failure message.

After admission, song and planning discards run as best-effort domain
operations. This boundary guarantees atomic rejection before either domain
starts, not a transaction across the separate domain stores and not
compensating rollback if an unexpected per-entry failure occurs after work has
started.

## Non-Goals

- Making retry work offline. It cannot.
- Changing what the backend authorises. Nothing here moves an authorization
  decision into the client.
- Removing the unused slug providers. That is a separate call, noted rather than
  taken.
- Any change to the planning discard path, which is already local-first.

## Testing

1. **Offline song discard drops the mutation.** With a remote repository that
   throws `connectivityFailure` on every call, `discardMine` succeeds, the song
   mutation is gone, and the song reads back as the cached snapshot version.
2. **Offline discard never writes a conflict.** Same setup: the record's sync
   status is not `conflict` afterwards — this is the exact regression the
   current code has.
3. **Offline discard of a pending create deletes the song locally.** Nothing
   remains to sync, and no network call was required.
4. **A failing best-effort refresh does not undo the discard.** The refresh
   throws; the mutation stays gone.
5. **Discard All offline reports rather than silently no-ops.** With every
   discard now succeeding locally, the previously silent path has nothing to
   swallow; assert that the mutations are actually gone after a discard-all with
   no connectivity.
6. **Offline retry surfaces a connectivity failure** to the caller instead of
   returning as if it had worked.
7. **`getPlanDetailBySlug` reads the mutation set once.** Counted with a
   recording fake store: exactly one actionable-mutation read and no full plan
   listing per call.
8. **Slug resolution still finds a plan created offline**, whose slug exists
   only in a pending `planCreate` mutation and not in the projection. This is
   the trap in the optimisation and must fail if the pending-create branch is
   removed.
9. **Sync and discard are mutually exclusive per user and organization.** A
   discard attempted during an owned sync returns `syncInProgress` immediately,
   makes no local change, and does not invoke its refresh; another organization
   remains independent.
10. **Sync queued behind discard snapshots afterwards.** Concurrent sync calls
    made during a discard share one queued future, start only after lease
    release, and do not send the discarded mutation.
11. **Discard All rejects before either domain.** When song sync owns the
    active context, the typed unified result is `syncInProgress` and neither
    song nor planning discard starts; the popup shows dedicated wait-for-sync
    guidance rather than the generic failure message.

## Documentation

- `docs/architecture/architecture.md` — the Offline Strategy section records that
  dropping local intent never requires the network, for both songs and plans.
- `docs/testing/testing-strategy.md` — the new offline-discard contracts.
- `docs/architecture/repository-review-2026-06-22.md` — mark LF-7 and LF-9 fixed,
  recording that LF-7's planning half was already resolved by PR #62/#63 and that
  the live violation was on the song side, and that LF-9's path has no live
  caller.
