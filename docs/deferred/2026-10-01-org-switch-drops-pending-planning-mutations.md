# An Organization Switch Drops Pending Planning Mutations

**Slice:** found by the 2026-10-01 delivery-roadmap analysis
(`docs/plans/2026-10-01-delivery-roadmap.md`, finding 4). This is a code-reading
finding and has not been reproduced. Scheduled for verification and a decision
in **S5b** (`fix/planning-mutation-gaps`).

**Related:**
- `docs/architecture/decisions/ADR-035-local-data-purge-contract.md`: the
  exhaustive `PurgeReason` set and the D7 single purge gate
- `docs/architecture/decisions/ADR-016-active-organization-resolution-semantics.md`
- `docs/product/vision.md`, "Sync Contract": local writes survive until they
  are accepted, discarded, or cleared by sign-out

**Files:**
- `apps/lyron_app/lib/src/application/active_organization_resolution.dart`:
  the active organization is the smallest organization id
  (`organizationIds.sort()`, then `.first`)
- `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`:
  `handleActiveContextChanged`, the `!sameBoundary` branch
- `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart`:
  `deletePlanningData`, which deletes `cachedPlanningMutations` together with
  the projection

## Problem

The active organization is the lexicographically smallest organization id
among the user's memberships. Suppose a user who is a member of organization A
also becomes a member of organization B, and B's id sorts before A's. The next
online resolution then selects B, and `handleActiveContextChanged` sees a
boundary change. Its `!sameBoundary` branch calls `deletePlanningData` for the
previous `(userId, organizationId)` pair. That call deletes the previous
organization's projection **and its pending planning mutations**.

This conflicts with the documented contracts in three ways:

- **No purge reason.** None of the four `PurgeReason` values applies, and the
  delete does not pass through `LocalDataLifecycle`, the ADR-035 D7 gate. The
  user is still a member of A, so this is not a revocation.
- **Writes lost that the product promises to keep.** The product sync contract
  keeps local writes until they are accepted, discarded, or cleared by
  sign-out. Here unsynced edits made in A are lost without any of these.
- **Asymmetry with songs.** The song side keeps the previous organization's
  data: `SongCatalogStore.deleteCatalog` has no production caller, so pending
  song mutations survive the same switch.

`docs/architecture/architecture.md` does describe the projection purge ("purges
the previous active organization data when the active organization changes").
It does not say that pending mutations are lost with it, and the product
contract above says they are not.

## Why it was deferred

The analysis that found it was a sequencing pass, not an implementation slice.
The path also has narrow preconditions: a multi-organization user, a new
membership whose organization id sorts first, and unsynced planning edits at
the moment of the switch. Under the current single-active-organization product
model it is rare. It is still a silent loss of user intent, so it belongs to
the next slice that re-enters planning sync.

## Requirements for the slice that picks this up

- **Prove it first.** A red test: pending planning mutations for organization A,
  then an online resolution that selects B. Assert what happens to A's pending
  rows. If the test shows the rows survive, close this entry with the test as
  evidence.
- **If confirmed, choose one rule and record it** in ADR-035 or in the
  architecture doc's Offline Strategy:
  - **(a) Keep:** keep the previous organization's pending mutations until they
    are synced or discarded, and keep syncing them while the membership
    exists. Only the projection is dropped.
  - **(b) Explicit purge:** add an explicit, audited purge reason for an
    organization switch. The user must be warned about the unsynced work it
    drops, as the different-user re-auth flow does (ADR-029).
- **Align the song side** with whichever rule is chosen, or document why the
  two domains differ.
- **Make the S3 personal layer follow the same decision.** Per the roadmap, the
  personal-layer outbox is not deleted on an organization switch.
- **Update or remove this entry** in the same change.
