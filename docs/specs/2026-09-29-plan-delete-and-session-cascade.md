# Plan Delete and Cascading Session Delete

> Status: Proposed (design agreed 2026-09-29; implementation plan pending)

**Branch:** `feat/plan-delete-session-cascade`
**ADR:** ADR-038 (to be written with the implementation; see D12)
**Deferred siblings:** `docs/deferred/2026-09-29-session-item-move.md`,
`docs/deferred/2026-09-29-plan-duplicate.md`

## Problem

Planning cannot delete a plan. There is no backend RPC, no
`PlanningMutationKind`, and no UI for it. `docs/architecture/state-machines.md`
already describes the intended behavior ("`Removed` plan means local intent to
delete the plan and its full hierarchy"), but nothing implements it. A plan
created by mistake, or a past service plan, stays in the list forever.

Session delete is limited to empty sessions. `PlanningWriteService.deleteSession`
throws `SessionDeleteBlockedException` for a non-empty session, the session
card shows the delete button only when the session has no items, and
`delete_empty_session` rejects a non-empty session with
`session_delete_blocked_not_empty`. To remove a populated session the user has
to remove every song first.

Both operations have to be offline-first, like every other planning write. A
local delete intent must be recorded, overlaid, and synced later. It must not
destroy content the deleting user has not seen, and it must never delete
songs.

### Why the existing version is not enough

`plans.version` is bumped only by `update_plan_fields` and
`reorder_plan_sessions`. Session create, rename, and delete, and all session
item writes, leave it unchanged. Suppose user A is offline and deletes a plan
based on an old view, while user B builds out that plan's setlist. A
`version`-only check would accept A's delete when A reconnects, and B's work
would disappear without a conflict.

`sessions.version` does not have this gap: `create_song_session_item`,
`delete_session_item`, `reorder_session_items`, and `rename_session` all bump
it. A session-level base-version check already covers the session's whole
subtree.

## Goals

- Delete a plan together with its sessions and session items (cascade).
- Delete a session together with its session items (cascade). This replaces
  the empty-only rule.
- Work fully offline, with the same mutation-store, overlay, sync, and
  recovery machinery as every other planning write.
- Reject a cascade delete when the deleted subtree changed after the deleting
  client based its delete on it (I2).

## Non-Goals

- Moving a session item to another session:
  `docs/deferred/2026-09-29-session-item-move.md`.
- Duplicating a plan or using one as a template:
  `docs/deferred/2026-09-29-plan-duplicate.md`.
- Soft delete, archive, trash, or undo after the backend accepts a delete.
- Plan list filtering or grouping (past/upcoming).
- Note and attachment session items, and group-scoped plans. These are
  unchanged: new plans still persist `group_id = null`.
- Auto-converging a delete that hits `plan_not_found` / `session_not_found`.
  Planning keeps its existing `failedRemoteDelete` path (D9). Only the song
  domain auto-converges delete-sourced remote deletion.
- Showing a conflicted plan removal as a visible, inspectable plan. It stays
  hidden, consistent with every other actionable delete intent (D10).

## Invariants (binding for implementation and review)

**I1. Songs are never deleted by planning.** A cascade reaches only
`plans → sessions → session_items`, through the existing
`sessions_plan_scope_fk` and `session_items_session_scope_fk`
(`on delete cascade`). `session_items_song_scope_fk` and
`session_items_attachment_scope_fk` have no `on delete` action. Deleting a
referencing row never touches the referenced song or attachment. On the
client, `countSongReferences` counts the projection, not the overlay, so a
song stays delete-blocked locally until the plan or session delete is
accepted and the projection drops the referencing items. That matches the
backend, which still holds the items until then.

**I2. No silent loss of unseen content.** The backend accepts a cascade
delete only if the deleted subtree is at exactly the version the client based
the delete on:
- plan: `version` and `content_version`
- session: `version`

Any interleaved write by anyone else makes the delete a visible `conflict`.

**I3. Client base adjustments account only for the client's own accepted
writes.** Every client-side adjustment of a base version (D7) must be
verifiable against a backend-returned value by contiguity, and must never
absorb a foreign write. When in doubt, leave the base stale. A stale base
produces a visible, recoverable conflict (fail-safe). An over-advanced base
would silently break I2 (fail-open), so that is never acceptable.

**I4. Every successful planning child write bumps `plans.content_version`
by exactly 1, in the same transaction.** A failed or rolled-back write bumps
nothing. "Child write" means every RPC that creates, renames, deletes, or
reorders a session or a session item. Plan field edits are not child writes;
they are covered by `plans.version`. The reorder RPCs count as child writes
even when they move nothing (for example on a plan without sessions); the
extra bump can only cause a false conflict, never a false acceptance.

**I5. Lock order.** Every planning write RPC locks the owning `plans` row
(through the `content_version` bump, or through the delete itself) before
its first write to `sessions` or `session_items`. Planning RPCs therefore
never acquire plan and session/item row locks in opposite orders. After
taking that lock, a function re-reads the rows its checks depend on, so a
write or delete that committed while it waited produces the same error a
sequential call would: a version conflict for a changed row, `*_not_found`
for a deleted one.

**I6. Authorization is backend-enforced.** Flutter capability gating
(`IfCapability`) only hides affordances.

**I7. The projection's `contentVersion` never runs ahead of the content it
reflects.** A full refresh reads plan rows, including `content_version`,
before it reads their session and item rows (D4). A race can then only leave
the projection's `contentVersion` behind its children, which gives a false
conflict (safe). It can never leave `contentVersion` ahead of its children,
which would give a false acceptance.

## Decisions

### D1 — Backend: `plans.content_version`

- New column `plans.content_version bigint not null default 1` with
  `check (content_version > 0)`. Existing rows start at 1.
- The bump (`update public.plans set content_version = content_version + 1
  ... returning content_version`) is added to:
  - `create_session`, `rename_session`, `reorder_plan_sessions`
  - `create_song_session_item`, `delete_session_item`,
    `reorder_session_items`
  - the new `delete_session` (D3)
  - the legacy `delete_empty_session` (D3)
- In each function the bump is the first write, after the existing
  authorization and validation lookups (I5). `reorder_plan_sessions`
  therefore moves its existing `plans.version` bump into the same statement,
  ahead of its session position rewrites. A later exception rolls the bump
  back with the rest of the transaction (I4).
- `create_plan` and `update_plan_fields` do not bump `content_version`.
  `plans.version` semantics are unchanged.
- **Returned value.** Every bumping RPC except the legacy
  `delete_empty_session` returns a new `plan_content_version bigint` column
  holding the post-bump value:
  - `create_session` and `rename_session` currently `return public.sessions`.
    They change to `returns table (...)` with the same session column names
    plus `plan_content_version`.
  - The four `returns table` functions gain the column.
  - Because PostgreSQL cannot change a function's return type in place, each
    of these six is `drop function` + `create function`. The drop and create
    re-apply `security definer`, `set search_path = public`, and the exact
    `revoke all ... from public, anon, authenticated` /
    `grant execute ... to authenticated` pairs from
    `202605160007_auth_boundary_hardening.sql`.
  - The change is compatible with already-installed clients. The client
    maps rows by key name, accepts both a `Map` and a `List` response, and
    ignores extra keys.
- `create_plan` and `update_plan_fields` keep `returns public.plans`. Their
  response picks up `content_version` automatically with the new column.
- **Side effect (intended):** the existing `plans_set_updated_at` trigger
  fires on every content bump, so `plans.updated_at` now means "last change
  to the plan or its content". The plan list's `updatedAt` tie-break for
  equal `scheduledFor` values can reorder accordingly.

### D2 — Backend: `delete_plan`

Signature:
`delete_plan(p_organization_id uuid, p_plan_id uuid, p_base_version bigint, p_base_content_version bigint)`

- `security definer`, `set search_path = public`, revoked from
  `public, anon, authenticated`, granted `execute` to `authenticated`.
- A null `p_base_version` or `p_base_content_version` raises
  `plan_version_conflict` (P0001), mirroring `update_plan_fields`.
- Lookup: plan row in `p_organization_id` with `id = p_plan_id` and both
  `has_capability(org, 'canManagePlans', group_id)` and
  `has_capability(org, 'canEditSessions', group_id)`. The cascade removes
  sessions, so both capabilities are required. The two currently map to the
  same roles, but they are separate capabilities.
  - No row found raises `plan_not_found` (P0002). This keeps the existing
    conflation of "missing" and "not visible to you" used by every planning
    write RPC.
- The delete:
  `delete from public.plans where organization_id = ... and id = ... and version = p_base_version and content_version = p_base_content_version returning id, organization_id, true, version, content_version`.
  - Result shape:
    `returns table (id uuid, organization_id uuid, deleted boolean, deleted_version bigint, deleted_content_version bigint)`.
  - If no row is deleted, it raises `plan_version_conflict`. The `detail`
    names both expected and current values.
- The cascade runs through the existing FKs. No explicit child deletes.

### D3 — Backend: `delete_session` (cascade) and legacy `delete_empty_session`

- New
  `delete_session(p_organization_id uuid, p_session_id uuid, p_base_version bigint)`,
  same hardening as D2.
  - Lookup and errors are identical to `delete_empty_session`:
    `canEditSessions` on the session's scope, `session_not_found`, and
    `session_version_conflict`. There is no emptiness check.
  - It bumps the owning plan's `content_version` (I4) before deleting the
    session (I5).
  - The delete is conditional on `version = p_base_version`. On no match it
    raises `session_version_conflict`, which rolls the bump back.
  - `returns table (id uuid, plan_id uuid, organization_id uuid, deleted boolean, deleted_version bigint, plan_content_version bigint)`.
- `delete_empty_session` stays only for already-installed clients.
  - Its signature, return shape, and emptiness rule are unchanged.
  - It gains the `content_version` bump (I4), placed ahead of the delete
    (I5).
  - New clients never call it. The domain model marks it deprecated.
  - Dropping it later is a separate migration, once no supported client
    calls it.

### D4 — Client data model

- **Mutation kind.** `PlanningMutationKind.planDelete`, with value
  `plan_delete` and aggregate type `plan`. It shares the per-aggregate row
  with `planCreate` and `planEdit`.
  - Every exhaustive `switch` over the kind is updated: RPC mapping,
    reconciler, overlay, sync overview summary (`'plan removed'`), and
    `_currentBaseVersionFor`.
- **RPC mapping.** `planDelete` calls `delete_plan` with `p_plan_id`,
  `p_base_version`, and `p_base_content_version`. `sessionDelete` now calls
  `delete_session`.
- **RPC parameters are built per kind from an explicit whitelist.** Today's
  builder adds `p_slug`, `p_name`, and `p_description` whenever the record
  carries them. `resolveCancelledCreate` turns a tombstoned create into a
  delete with `copyWith`, so the converted delete still carries its create's
  `slug` and `name`.
  - As a result, a converted `sessionDelete` sends
    `delete_empty_session(..., p_slug, p_name)`. PostgREST finds no function
    with that signature (`PGRST202`), the error maps to `unknown`, and the
    row stays `pending` forever.
  - That is an existing latent defect. This slice would add the same path
    for `planDelete`, so it is fixed here.
  - Each kind sends exactly its RPC's parameters, and nothing else.
- **`PlanningMutationRecord`** gains:
  - `baseContentVersion` (`int?`, persisted; meaningful for `planDelete`
    only).
  - `acceptedPlanContentVersion` (`int?`, in-memory only). It is filled by
    `SupabasePlanningMutationRepository._mapRow` from `plan_content_version`,
    or from `content_version` on a `plans` row response. This mirrors
    `orderedSiblingPositions`, which is also response-only.
- **Drift `PlanningLocalDatabase` schema 6 → 7:**
  - `CachedPlanningPlans.contentVersion` (`integer().nullable()`). Rows that
    predate the migration hold `null`, meaning "unknown until the next full
    refresh".
  - `CachedPlanningMutations.baseContentVersion` (`integer().nullable()`).
- **`PlanSummary` gains `contentVersion` (`int?`).**
  - The overlay preserves the projection value for existing plans.
  - An overlay-only (pending `planCreate`) plan carries `null`.
- **Sync payload.** `PlanningSyncPlan` and the Supabase plan selects add
  `content_version`.
  - `fetchPlanningSyncPayload` keeps reading all plan rows before any
    session or item row, as it does today. This order is now a correctness
    requirement (I7), pinned by a test.
  - A null `contentVersion`, whether from a pre-migration row or an older
    backend, sends `p_base_content_version = null`. The backend rejects
    that as a conflict, which is fail-safe. The next refresh fills the
    value, and a retry rebases onto it (D9).
- **`upsertSyncedPlan`.** A `planCreate` reconcile inserts the row with the
  response `content_version`, or 1 if absent. A `planEdit` reconcile
  preserves the existing row's `contentVersion` and never overwrites it
  from the response. A `planEdit` response's `content_version` can include
  foreign writes, so taking it would break I7.

### D5 — Recording a plan delete (`recordPlanDelete`)

Terms used below:

- **In-flight:** `syncStatus` ∈ {`sending`, `cancelling`, `accepted`}. The row
  is on its way to the backend, or already on it.
- **Child rows of plan P:**
  - every mutation row with `planId == P` and aggregate type `session`,
    `session_item`, or `session_item_order`
  - the `session_order` row with `aggregateId == P`

`PlanningWriteService.deletePlan(context, PlanDeleteDraft(planId))` does the
following:

1. Requires the matching context.
2. Reads the merged plan detail.
3. Records the delete with:
   - `baseVersion = plan.version`
   - `baseContentVersion = plan.contentVersion`
   - `originSnapshot = _planSnapshot(plan)` (includes `name`)
4. Schedules sync.
5. Uses the same aggregate invalidation path as plan create, because the
   plan set changed (ARCH-2).

`DriftPlanningMutationStore.recordPlanDelete` runs in one transaction and
branches on the existing `plan` row for P:

- **(a) `planCreate`, not in-flight** (pending or any failure status).
  Physical collapse: delete the `plan` row and every child row of P in any
  status. This matches ADR-028 D10: as far as the client knows, the plan
  never reached the backend, so no child can have either.
  - One exception is a create the backend committed but whose response was
    lost. That is the existing LF-T5b family
    (`docs/deferred/2026-09-28-client-abandoned-committed-write-lf-t5b.md`),
    and the same exception already applies to today's session collapse.
  - Its outcome is a plan that reappears on the next refresh, not silent
    loss. It is not addressed here.
- **(b) `planCreate` `sending`.** Rewrite the row as a `cancelling` tombstone
  (in-flight create cancellation D2). Drop every non-in-flight child row.
  - In normal operation no child of P is in-flight here: sync is sequential
    per context, and children sort after their plan's create.
  - A crash-resume state can still leave a stale `sending` child row. That
    row is kept like any other in-flight row. There is no assertion.
  - `planCreate` joins `sessionCreate` and `sessionItemCreateSong` as a
    cancellable create in `PlanningMutationSyncController._run`.
  - `resolveCancelledCreate` maps `planCreate` to `planDelete`, with:
    - `baseVersion = acceptedBaseVersion` (response `version`)
    - `baseContentVersion = acceptedPlanContentVersion ?? 1`
  - A failed create discards the tombstone, exactly as today. Because the
    plan then never existed on the backend, the store also deletes every
    remaining child row of P in the same transaction.
- **(c) `planCreate` `accepted`** (accepted but not yet cleared). Convert to
  a real pending `planDelete` with:
  - `baseVersion = existing.baseVersion ?? draft.baseVersion`
  - `baseContentVersion = draft.baseContentVersion ?? 1`
  - Drop non-in-flight child rows.
- **(d) Anything else** (no row, or `planEdit` in any status including
  in-flight). Upsert a pending `planDelete` on the `plan` row with:
  - `baseVersion = existing?.baseVersion ?? draft.baseVersion`
  - `baseContentVersion = draft.baseContentVersion`
  - `originSnapshot = existing?.originSnapshot ?? draft.originSnapshot`
  - Drop non-in-flight child rows.
  - An overwritten `sending` `planEdit` is handled by D7 rule 2 plus the
    existing ADR-030 D3 revision gate.

Order key: branches (c) and (d) take a fresh `orderKey` (after every
existing row), so any surviving in-flight child row, including a `sending`
row resent after a crash, concludes before the delete is sent. Branch (b)
keeps the create's key.

Budget admission (`BudgetedPlanningMutationStore`): same rule as
`recordSessionDelete`. The write is admitted regardless of budget when the
`plan` row holds a pending `planCreate` (`_collapsesPendingCreate`).
Otherwise it is budget-guarded.

### D6 — Recording a cascading session delete (`recordSessionDelete`)

- `PlanningWriteService.deleteSession` drops the emptiness precondition.
  `SessionDeleteBlockedException` and `AppStrings.sessionDeleteBlockedMessage`
  are removed.
- The three `sessionCreate` branches (collapse, tombstone,
  accepted → pending delete) are unchanged.
- The non-create branch now also drops the session's non-in-flight child
  rows: `session_item` rows with `sessionId == S` and the
  `session_item_order` row with `aggregateId == S`.
  - Previously these rows had to be kept, because the backend required the
    session to be empty before deleting it.
  - Under cascade they could only bump the session `version` and make the
    delete conflict with itself.
- The non-create branch takes a fresh `orderKey` (same reason as D5).
- `baseVersion = existing?.baseVersion ?? draft.baseVersion`, unchanged.

### D7 — Sync: contiguous own-write rebase

`PlanningMutationStore.rebaseCascadeDeleteBases(context, synced)` (name
indicative) runs as one local transaction and is idempotent. `synced` is the
record mapped from a successful RPC response. It applies only these three
rules, each only on exact contiguity:

1. If `synced.kind` is a child kind (`sessionCreate`, `sessionRename`,
   `sessionDelete`, `sessionReorder`, `sessionItemCreateSong`,
   `sessionItemDelete`, `sessionItemReorder`) and
   `synced.acceptedPlanContentVersion == R` for plan P:
   - **a.** If projection plan P has `contentVersion == R − 1`, set it to R.
   - **b.** If the `plan` row for P is a `planDelete` that is not in-flight
     and has `baseContentVersion == R − 1`, set that to R.

   A `planCreate` or `planEdit` response's `content_version` never feeds this
   rule. `planEdit` does not bump `content_version`, so after exactly one
   foreign child write its response value would falsely pass the `R − 1`
   check and absorb that write (I3). Only D5(b)'s tombstone resolution and
   D4's `planCreate` upsert read it.
2. If `synced.kind` ∈ {`planEdit`, `sessionReorder`} and the response plan
   `version == V`: a `planDelete` row for P with `baseVersion == V − 1` is
   set to V. This includes the same row when a `planDelete` overwrote an
   in-flight `planEdit`.
3. If `synced.kind` ∈ {`sessionRename`, `sessionItemCreateSong`,
   `sessionItemDelete`, `sessionItemReorder`} and the response session
   `version == V` for session S: a `sessionDelete` row for S that is not
   in-flight and has `baseVersion == V − 1` is set to V.

Any other value is left untouched, and the delete conflicts, which is correct
(I2 and I3).

Rules 1–3 run only for a record mapped from an RPC response in the current
sync run. A crash-resumed `accepted` marker carries no response values: its
`baseVersion` is still the pre-write base. For such a record only the D8
purge runs.

The call is best-effort. An `Exception` it throws is swallowed, so the
`accepted` marker write that follows it is never skipped; an `Error` still
propagates. Failing to rebase leaves a base stale, which is fail-safe. A
failed purge runs again at batch conclusion.

**Call sites** in `PlanningMutationSyncController._run`:

- Immediately after `syncMutation` returns, before the `accepted` marker
  write. It runs even when that write is skipped by the revision gate
  (ADR-030 D3). This covers a delete recorded while the child's RPC was in
  flight.
- Again for every entry in `acceptedRecords` before its clear or reconcile
  (idempotent). This covers a delete recorded between the response and the
  end of the batch.
- At batch conclusion the call runs for each accepted record right before
  that record's reconcile, in `acceptedRecords` order. So a `planCreate`
  reconciled at cv=1 followed by its accepted child reaches cv=2 when the
  post-write refresh fails. The reconciler itself contains no rule-1a code.
- Whether a record came from a response in this run is carried as an
  explicit flag next to it, never inferred from object identity.

The method goes through `BudgetedPlanningMutationStore`'s per-context write
queue, like `saveSyncAttemptResult`. It is not budget-guarded, because it
never grows a row.

**Residual windows (accepted, fail-safe).** In the cases below the delete
surfaces as a visible `conflict`, and "retry" resolves it (D9). This is the
same class the existing session-delete-after-in-flight-item path already has
today.

- A crash between an RPC response and its rebase.
- A crash-resumed `accepted` marker, which carries no response values.
- A child accepted before its plan reached the projection, when the refresh
  then failed and a delete was recorded before the reconcile.

### D8 — Accepting a delete

- **Purge.** When a `planDelete` RPC succeeds, the store deletes every
  remaining child row of P in any status. When a `sessionDelete` RPC
  succeeds, it deletes every remaining `session_item` / `session_item_order`
  row of S.
  - This runs right after the response, and again (idempotently) when the
    accepted delete row is reconciled or cleared. That covers a crash
    between the two.
  - Any leftover row targets an object that no longer exists and would
    otherwise surface as a spurious failure.
  - No child row can still be awaiting a remote call at that point, because
    sync is sequential per context and the delete sorts after every
    surviving child (fresh `orderKey`).
  - An `accepted` child processed earlier in the same run can be purged.
    Its in-memory reconcile still runs, ahead of the delete's because
    `acceptedRecords` keeps send order, and its revision-gated clear becomes
    a no-op.
- **Reconciler, when the refresh fails.** `planDelete` calls a new
  `PlanningLocalStore.deleteSyncedPlan`, which removes the plan, its
  sessions, and its items from the projection in one transaction.
  `sessionDelete` keeps using `deleteSyncedSession`, which already removes
  the session's items.
- **Refresh succeeds.** The projection is replaced wholesale. The plan is
  gone.

### D9 — Failure handling and recovery

- **Classification is unchanged:**
  - `plan_version_conflict` → `conflict`
  - `plan_not_found` → `remoteMissing` → `failedRemoteDelete`
  - permanent authorization denial → `failedAuthorization`
  - connectivity → `pending`
- **Retry** is the explicit remove (the state machine's
  `RemovedConflict → explicit remove`). `retryMutation` rebases
  `baseVersion` from the projection plan `version`, as
  `_currentBaseVersionFor` gains a `planDelete` case. It also rebases
  `baseContentVersion` from the projection `contentVersion`.
  - The sync popup's conflict row for a plan removal must say that the plan
    changed after it was deleted.
  - The keep-mine / retry action deletes the plan as it now exists,
    including those changes. Discard keeps the plan.
- **Discard** clears the `planDelete` row, and the plan reappears. Child
  intents dropped at record time (D5) are not restored. The confirmation
  dialog says so up front (D11).
- **Plan group title.** `_planTitle` in `unified_sync_overview.dart`
  resolves the title for a group whose plan is hidden from `planTitles`. It
  treats `planDelete` like `planCreate`/`planEdit` in its first pass and
  uses that row's `originSnapshot['name']`. Otherwise the group could pick
  up a surviving child row's session name.

### D10 — Read overlay

- A `planDelete` in any actionable status hides plan P:
  - P is removed from `listPlans`.
  - `getPlanDetail(P)` fails with the existing not-found error.
  - `getPlanDetailBySlug` / `getPlanSummaryBySlug` return `null`.
  - No child overlay is applied for P.
- A `cancelling` `planCreate` tombstone is already excluded from actionable
  reads, so it is hidden too.
- Reader and deep links into a hidden plan get the existing slug not-found
  UI. No reader behavior changes.

### D11 — UI

- **Plan detail header.** A new overflow `PopupMenuButton` (`Icons.more_vert`)
  holds a "Delete plan" item.
  - It is shown only with both `Capability.managePlans` and
    `Capability.editSessions`.
  - The existing edit and add-session icon buttons stay as they are.
- **Plan delete confirmation dialog.** Title "Delete plan?". Body:
  - "“{name}” and its {n} sessions ({m} songs) will be deleted. The songs
    stay in the song library."
  - When the plan has unsynced local changes, it also says "Unsynced changes
    to this plan will be discarded."
  - Actions: Cancel / Delete, with the destructive action styled as such.
- **After a confirmed plan delete** the app navigates to
  `PlanningRoutes.planListPath` and invalidates like plan create.
- **Session card.** The delete button shows for every session, gated by
  `Capability.editSessions`.
  - Dialog title "Delete session?".
  - Empty session body: "This removes the session."
  - Non-empty session body: "“{name}” and its {m} songs will be removed
    from this plan. The songs stay in the song library."
  - When there are unsynced changes, the same discard line as the plan
    dialog.
- **Strings.** All copy goes in `AppStrings`, in English like the existing
  strings.

### D12 — Documentation (same change as the code, AGENTS.md)

- `docs/domain/domain-model.md`:
  - plans: delete semantics and `content_version`
  - sessions: cascade delete replaces "allowed only for locally empty
    sessions"; `delete_empty_session` deprecated
  - session_items: removed by cascade
  - local data: the stored-mutation lists
- `docs/architecture/state-machines.md`:
  - Plan mapping: the two-version conflict rule
  - Session mapping: remove the empty-only line and add the cascade
- `docs/architecture/architecture.md`: the planning write boundary list
  (plan delete), and the in-flight/accepted-window paragraph (plan create
  cancellation and D7).
- `docs/architecture/decisions/ADR-038-plan-content-version.md`:
  - the two-version model and the rejected alternatives (plan-version only;
    a client-sent content fingerprint; folding content into `version`)
  - the contiguity rule (I3)
  - the lock order (I5)
- Both deferred entries listed at the top (written with this spec).

## Testing (TDD; each red test before its green change)

**Backend.** Extend `scripts/tests/planning-write-contract-test.sh`, or add a
sibling contract script wired into `scripts/run-tests.sh`.

- B1. `delete_plan` happy path: plan, sessions, and items are gone; the
  referenced songs and their attachments are intact.
- B2. Each of the eight bumping RPCs raises `content_version` by exactly 1,
  and returns it where D1 says so. A failing call (for example a version
  conflict) leaves `content_version` unchanged.
- B3. `delete_plan` conflicts on:
  - a stale `p_base_version`
  - a stale `p_base_content_version` after a foreign `create_session`
  - a null base
- B4. `delete_plan` authorization: `organization_read_only`, a non-member,
  and a foreign-organization id all get `plan_not_found`.
- B5. `delete_session`:
  - a non-empty session loses its items and keeps its songs
  - a stale `p_base_version` conflicts and the plan's `content_version` is
    unchanged
  - on success it bumps the plan
- B6. `delete_empty_session` still behaves as before and now bumps.
- B7. Every new or recreated function is `security definer` with
  `search_path=public`, executable by `authenticated` and not by `anon`.

**Client unit and adversarial tests** (`test/application/planning/`,
`test/offline/planning/`, `test/offline/adversarial/`):

- C1. `recordPlanDelete` branches (a)–(d): child-row dropping with the
  in-flight exception, fresh `orderKey`, budget admission.
- C2. `recordSessionDelete`: the non-create branch drops non-in-flight item
  rows and takes a fresh `orderKey`; the create branches are unchanged.
- C3. D7 rules 1–3:
  - a contiguous value rebases
  - a non-contiguous value (a foreign write interleaved) does not
  - applying twice is a no-op
  - a projection already refreshed past R is untouched
  - a `planEdit` response whose `content_version` happens to equal
    base + 1 does not rebase anything
- C4. The sync controller:
  - `planCreate` tombstone resolution, both outcomes; the failed outcome
    also removes the plan's child rows, including a crash-stale `sending`
    one
  - the hook runs even when the accept write is revision-gated out
  - the purge after `planDelete` / `sessionDelete` success
  - purge idempotence across a simulated crash
- C5. The reconciler: `planDelete` removes the plan subtree;
  `upsertSyncedPlan` keeps `contentVersion` on `planEdit`. The sync
  controller applies rule 1a in `acceptedRecords` order, before each
  reconcile.
- C6. The overlay hides P for every actionable status, in list, detail, and
  slug reads.
- C7. Retry rebases both `baseVersion` and `baseContentVersion` from the
  projection.
- C8. `SupabasePlanningMutationRepository`:
  - `delete_plan` and `delete_session` parameters
  - `plan_content_version` and `content_version` mapping
  - a missing value maps to `null`
  - a delete converted from a tombstoned create, which still carries the
    create's `slug`/`name`/`description`, sends exactly its own RPC's
    parameter set
- C9. Drift 6 → 7 migration, extending `planning_migration_test.dart`.
- C10. I7: `fetchPlanningSyncPayload` issues every plan-row read before any
  session read.
- C11. I1 locally: a song referenced by a plan with a pending `planDelete`
  stays delete-blocked, and becomes deletable once the delete is reconciled.
- Adversarial:
  - A `planDelete` recorded while a child create is `sending`, and the
    create is then accepted: no self-conflict.
  - A foreign `create_session` between view and delete: `conflict`; retry
    after refresh succeeds; discard restores the plan.

**Widget tests:**

- overflow menu visibility by capability
- plan dialog copy (counts; unsynced-changes line present/absent)
- navigation to the plan list after a delete
- session delete button present on a non-empty session, with its dialog copy
- existing tests asserting "delete only when empty" are updated, not deleted

Every task's verification runs the full `scripts/run-tests.sh` suite, not a
subdirectory.

## Acceptance

1. **Offline plan delete.** A plan deleted offline disappears from the list
   immediately. On reconnect the backend removes the plan, its sessions, and
   its items. Every referenced song is still in the catalog and becomes
   deletable afterwards.
2. **Session cascade.** Deleting a populated session removes it and its
   items the same way. Songs are untouched.
3. **Foreign change conflicts.** If another member changes the plan's
   sessions or items after the local view the delete was based on, the
   delete does not go through. It shows as a conflict in the sync popup, and
   the user can retry (delete anyway) or discard (keep the plan).
4. **Own in-flight edits do not conflict.** A delete recorded while the
   user's own child write is in flight does not conflict because of that
   write.
5. **Authorization.** Read-only members see no delete affordances, and the
   backend rejects the RPCs for them.
6. **Old clients keep working.** Installed older clients can still create,
   edit, and delete empty sessions against the migrated backend.
