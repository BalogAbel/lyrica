# ADR-038: Plan Content Version and Cascading Delete

**Status:** Accepted (2026-09-30; implemented on
`feat/plan-delete-session-cascade`, including the fixes from three
adversarial review gates, recorded in the spec's Implementation section)
**Builds on:** ADR-019 (exactly-once mutation sync), ADR-030 (snapshot
identity and the in-flight create cancellation follow-up), ADR-028 D10 (a
delete that collapses a still-pending create)
**Context spec:**
`docs/specs/2026-09-29-plan-delete-and-session-cascade.md`
**Migration:**
`supabase/migrations/202609290001_plan_content_version_and_cascade_delete.sql`

## Context

Planning had no plan delete, and session delete was limited to empty
sessions. Both now cascade: a plan takes its sessions and their session items
with it, and a session takes its items. Both are offline-first, so the delete
is a local intent recorded against a view of the data that may be hours old.

A cascade delete removes content in bulk, so it must detect a concurrent
write to the subtree. Otherwise user A, offline, deletes a plan from an old
view while user B builds out its setlist, and A's delete silently destroys B's
work when A reconnects.

The existing versions do not cover this:

- `plans.version` is bumped only by `update_plan_fields` and
  `reorder_plan_sessions`. Session create, rename and delete, and every
  session-item write, leave it unchanged. A `version`-only check would accept
  A's delete.
- `sessions.version` does cover its subtree (create, delete and reorder of
  items, and rename, all bump it), so a session cascade needs no new
  counter.

The client adds two constraints. A delete recorded while the user's own child
write is still in flight must not conflict with that write. And the client
must not guess: any adjustment of a base version that absorbs a write the
deleting client never saw would silently break the guarantee above.

## Decision

1. **A separate `plans.content_version`** (`bigint not null default 1`,
   `check (content_version > 0)`). Every successful child write bumps it by
   exactly one, in the same transaction, through the internal
   `bump_plan_content_version` helper (not callable by clients):
   `create_session`, `rename_session`, `reorder_plan_sessions`,
   `create_song_session_item`, `delete_session_item`,
   `reorder_session_items`, `delete_session`, and the legacy
   `delete_empty_session`. A failed or rolled-back write bumps nothing. Plan
   field edits (`create_plan`, `update_plan_fields`) do not bump it; they stay
   covered by `plans.version`. Every bumping RPC except the legacy one also
   returns the post-bump value as `plan_content_version`.
2. **Lock order plan, then session, then item.** Each child write locks the
   owning `plans` row, through the bump, before its own version check and its
   first write to `sessions` or `session_items`. `delete_plan` takes the lock
   through the delete itself. After the lock, each function re-reads the rows
   its checks depend on, so a write or delete that committed while it waited
   produces the error a sequential call would: a version conflict for a
   changed row, `*_not_found` for a deleted one (review gate 1).
3. **`delete_plan` checks both versions.**
   `delete_plan(p_organization_id, p_plan_id, p_base_version,
   p_base_content_version)` deletes the plan only when `version` and
   `content_version` both still match. A mismatch or a null base raises
   `plan_version_conflict`; a missing or invisible plan raises
   `plan_not_found`. It requires both `canManagePlans` and `canEditSessions`.
   `delete_session(p_organization_id, p_session_id, p_base_version)` checks the
   session `version` only, and bumps the plan's `content_version` first (the
   bump rolls back on a conflict). Sessions and items follow through the
   existing `on delete cascade` foreign keys. Songs and attachments are only
   referenced, without an `on delete` action, so a cascade never deletes them.
   `delete_empty_session` is deprecated and kept, with its emptiness rule and
   return shape, for installed older clients.
4. **The client rebases a pending delete only by exact contiguity.** After
   every accepted planning write, the sync applies store-side effects
   (`applyAcceptedWriteEffects`). A pending cascade delete's base moves to the
   backend-returned value `R` only if it was exactly `R - 1`, and only for a
   value the backend returned for the client's own write:
   - `baseContentVersion` from a child write's `plan_content_version`;
   - `baseVersion` from a `planEdit` or plan-scoped `sessionReorder` response
     version;
   - a `sessionDelete`'s `baseVersion` from a session-scoped write's session
     version.

   Any other value is left as it is, and the delete conflicts. A `planCreate`
   or `planEdit` response's `content_version` never feeds the content rule,
   because it can include foreign writes. A stale base is fail-safe (a visible,
   recoverable conflict); an over-advanced base would be fail-open. The same
   effects purge a deleted subtree's remaining mutation rows after the backend
   accepts the delete, and a failed purge leaves the delete `accepted` so the
   next run purges again before clearing it.
5. **Retry rules (review gate 3).** Retry is the explicit remove, so it is
   where a rebase could absorb unseen content. Three rules bound it:
   - **Conflict-only rebase.** A cascade delete (`planDelete`, and
     `sessionDelete`) is rebased onto the refreshed projection on retry only
     when its status is `conflict`, that is, after the user saw a visible
     conflict. A retry from any other status, for example a connectivity
     failure, resends the original bases, so a foreign write surfaces as a
     conflict instead of being silently absorbed. The plan stays hidden behind
     its pending delete, so a refresh can bring in writes the user never sees.
   - **Shown-status guard.** Grouped retries (the sync popup's keep-mine over
     a plan group) carry the status each row had when the popup showed it
     (`UnifiedSyncPlanMutationRef.syncStatus`, passed to
     `PlanningMutationSyncController.retryMutation(expectedStatus:)`) and skip
     a row whose status has changed since. Each retry runs a sync pass that
     can move a later row, for example send a pending delete that then
     conflicts. The skip is silent, and the row stays visible in its new
     state.
   - **In-flight rows are never retried.** `sending`, `accepted` and
     `cancelling` rows are left untouched. Retrying a create tombstone would
     re-create the deleted object, and retrying an in-flight write would
     resend something the backend may already hold.
6. **Per-kind RPC parameter whitelist.** Each mutation kind sends exactly its
   RPC's parameters. A delete converted from a tombstoned create still carries
   its create's `slug` and `name`; the old "add whatever the record carries"
   builder sent them to `delete_empty_session` (PostgREST `PGRST202`, an
   `unknown` error, a row stuck `pending` forever), and would have done the
   same for `delete_plan`.
7. **Client data model.** Drift schema 7 adds
   `CachedPlanningPlans.contentVersion` and
   `CachedPlanningMutations.baseContentVersion` (both nullable; `null` means
   "unknown until the next full refresh", and a delete sent with a `null` base
   is rejected by the backend as a conflict, which is fail-safe). `PlanSummary.contentVersion` carries the
   projection value. A full refresh reads every plan row before any session or
   item row, so the projection's `contentVersion` can only lag its children
   (false conflict), never lead them (false acceptance). A pending `planDelete`
   hides its plan from every merged read in any actionable status, while
   referenced songs stay delete-blocked until the backend accepts the delete
   (`countSongReferences` counts the projection, which matches the backend).

## Consequences

- **Deploy the backend first.** The client's plan selects name
  `content_version`, so a client build containing this slice fails every
  planning refresh against a backend without migration `202609290001`. The
  migration must be applied to production Supabase before any such client
  build ships. There is no automated deploy pipeline, so this is a manual
  ordering requirement. The reverse direction is safe: installed older clients keep working against the migrated
  backend, including their calls to the deprecated `delete_empty_session`.
- `plans.updated_at` moves on content changes, because the existing
  `plans_set_updated_at` trigger fires on every bump. It now means "last
  change to the plan or its content", and the plan list's `updatedAt`
  tie-break for equal `scheduledFor` values can reorder accordingly.
- Concurrent child writes on one plan serialize on its row lock.
- Narrow crash windows can still surface a self-conflict that a retry
  resolves: a crash between an RPC response and its rebase, a crash-resumed
  `accepted` marker (it carries no response values), and a child accepted
  before its plan reached the projection when the refresh then failed. All
  fail safe, as a visible `conflict`.
- The existing item-RPC race is closed. Before, two concurrent item writes
  could both pass a plain-read session version check before either locked the
  session row. Now the plan-row lock precedes the check, and a conditional
  update performs it.
- The reorder RPCs bump `content_version` even when they move nothing (for
  example on a plan without sessions). The extra bump can only cause a false
  conflict, never a false acceptance.
- I2, I4 and I5 of the spec hold for writes made through the planning RPCs.
  Direct table DML by `authenticated` under the `for all` RLS write policies
  bypassed them; that gap predated this change and was closed on 2026-10-01
  by ADR-039, after which the planning RPCs are the only writers.
- Discarding a conflicted plan delete restores the plan but not the child
  intents dropped when the delete was recorded. The confirmation dialog says
  so up front.
- A delete is recorded only against the snapshot its confirmation showed
  (review gate 4 F1). The delete drafts carry the confirmed `version` (and
  `content_version` for a plan), and `PlanningWriteService` throws
  `PlanningDeleteTargetChangedException` without recording anything when the
  target moved or is gone. Without it, a refresh landing while the dialog was
  open made the delete remove rows the dialog never listed, and the backend
  accepted it because the re-read base was current.

## Alternatives considered

- **`version`-only.** Check only `plans.version` on delete. Silently deletes
  others' work, because child writes do not touch it. Rejected.
- **Client-sent content fingerprint.** The client sends a fingerprint of the
  subtree it saw and the backend compares it. It needs the same own-write
  rebasing and is harder to verify. Rejected.
- **Folding child writes into `plans.version`.** One counter for everything.
  Every plan edit and session reorder would conflict with unrelated content
  writes, which produces false conflicts on the most common operations, and
  the client would have to rebase one aggregate's base from another aggregate's
  writes. Rejected.
- **Rebase a cascade delete on every retry, whatever its status.** It absorbs
  writes the user never saw, because the plan stays hidden behind its pending
  delete (review gate 3 F1). Rejected in favour of the conflict-only rule.

## Deferred

Follow-ups this slice created, each recorded under `docs/deferred/`:

- `docs/deferred/2026-09-29-plan-duplicate.md`: duplicate a plan or use one
  as a template. Scoped out because the design choice (server-side copy RPC
  versus a client-composed copy) is non-trivial and cuts both ways offline.
- `docs/deferred/2026-09-29-session-item-move.md`: move a session item to
  another session. Scoped out because a move touches two session aggregates
  while the mutation store keeps one row per aggregate.
- Direct table DML bypassing the RPC write contract (I2, I4, I5), found by
  review gate 1; it predated this slice. Resolved on 2026-10-01 by
  `docs/specs/2026-10-01-direct-table-dml-lockdown.md` and ADR-039.
- `docs/deferred/2026-09-30-planning-pull-unpaged-reads.md`: the pull's
  top-level reads are unpaged, so PostgREST's `max_rows` cap (1000) could
  truncate a plan's session list and put `contentVersion` ahead of the
  projected sessions. Found by review gate 2; it depends on data volume. Resolved on 2026-10-12 by
  `docs/specs/2026-10-12-paged-remote-pulls.md` and ADR-041.
- `docs/deferred/2026-09-30-session-rename-retry-never-rebases.md`
  (resolved by S5b PR 2, entry removed): a retried
  conflicted `sessionRename` never rebases, because `_currentBaseVersionFor`
  keys on `sessionId`, which session rows do not set. Found by review gate 3;
  it predates this slice and is unrelated to the cascade.
- `docs/deferred/2026-09-30-stranded-create-tombstones.md`
  (resolved by S5b PR 2, entry removed): a `cancelling`
  create tombstone is never resolved if the sync run that would resolve it is
  interrupted. The in-slice plan case is fixed; the general family (sessions
  and items) becomes its own slice.
- `docs/deferred/2026-09-30-capability-gating-offline-cold-start.md`:
  `IfCapability` is fail-open when capability resolution fails and the
  resolver's cache is in memory only, so a read-only member is offered delete
  after an offline cold start. The backend rejects it (I6 holds), and the plan
  stays hidden behind "could not find the target item" copy until the row is
  discarded. Found by review gate 4 (F5); the mechanism predates this slice and
  is kept fail-open on purpose for offline editors.
- `docs/deferred/2026-09-30-content-version-advance-on-context-switch.md`
  (removed by S5b PR 1; see the 2026-10-21 amendment): D7
  rule 1a advances the projection's plan `content_version` right after an
  accepted child write. If the org or user context switches mid-run, the old
  context's accepted child rows are cleared without a reconcile, so its
  projection sits at the advanced value without the write until its next
  refresh. Found by review gate 4 (F6); narrow, and nothing foreign is
  absorbed.

## Amendment: key edits (2026-10-13, S3)

Spec: `docs/specs/2026-10-13-personal-song-settings.md` (PS10–PS13); ADR-042;
migration `supabase/migrations/202610130001_session_item_key.sql`.

`set_session_item_key` writes a song item's plan-level `transpose` and `capo`.

- It is a child write. It locks the owning plan row first and bumps
  `plans.content_version` (decision 1; I4 unchanged). A no-op (every affected
  field already holds the requested value) writes and bumps nothing.
- Its optimistic concurrency uses `session_items.version`, which no other RPC
  bumps. Key edits on different items, and a key edit next to a structural
  write in the same session, never conflict.
- It does not bump `sessions.version`. A session's version covers its
  structure (items added, removed, reordered) and its name; a key is not
  structure. A session delete recorded from a view older than a key edit
  therefore still succeeds, while a plan delete recorded from such a view
  conflicts through `content_version`. Accepted: the deleting user removes
  the items they saw, and the key edit added no content they did not see.
- Lock order: plan, then item. It locks no session row.
- Client rule (S3 PR 2): a no-op success returns the CURRENT
  `content_version` and bumps nothing, so the value can include foreign
  bumps. The client feeds a key edit's `plan_content_version` to rules 1a and
  1b (D4 contiguity) only when the response is provably its own write (the
  returned item version is the sent base + 1 and the key state equals the
  sent edit applied to the sent base values, PS15). Any other response's
  content version is discarded: the projection lags and a stale plan delete
  conflicts, the fail-safe direction.

## Amendment: rule 1a placement and the retry rule (2026-10-21, S5b)

**Status:** Accepted (2026-10-22, S5b design gate). Item 1 (MG4) is
implemented by S5b PR 1 (#97); item 2 (MG8) and item 3 (F1) are implemented
by S5b PR 2 (`fix/planning-unresolved-rows`).
**Spec:** `docs/specs/2026-10-21-planning-mutation-gaps.md` (MG4, MG8, F1).

1. **Rule 1a runs only after a successful reconcile of the same record
   (MG4).** Decision 4's projection advance (D7 rule 1a) leaves the
   accepted-write effects. It runs only in the refresh-failed branch, for a
   record whose run context is still the active one, right after that
   record's reconcile completed without throwing. The effects call keeps
   rules 1b, 2 and 3, which rebase the run's own pending deletes, and stays
   where it was, unconditional. Before, a context switch or a reconcile
   failure between the advance and the reconcile cleared or failed the
   accepted row without bringing the write W into the projection, which left
   the projection at R without W and broke I7 (the deferred entry for
   review gate 4's F6 finding, removed when this item was implemented).
   This now cannot happen: a context switch, a failed or skipped reconcile
   never leaves the projection at R without W. One race stayed, pre-existing
   and not closed by PR 1 (F1): a pull for the same context stored between
   C5 and the reconcile, after which the reconcile writes the older W over
   the pull's newer content while the projection keeps the pull's content
   version. Item 3 below closes it.
   A delete recorded earlier in the run reads R - 1 and is still rebased by
   rule 1b at batch end. Accepted narrow window (refresh-failed branch
   only): a `planDelete` recorded between a record's batch-end effects call
   (rule 1b) and that record's advance reads R - 1 and gets no later rule-1b
   rebase for that record, so it ends in a visible false conflict (fail-safe,
   I3 holds); before, rule 1a ran ahead of rule 1b inside the effects call
   and that draft read R. Consequence (already listed under "Narrow crash
   windows"): a crash after the RPC leaves the projection at R - 1 until the
   next refresh, so a later delete can show one visible false conflict.
2. **Retry rebases only from a visible conflict, for every kind that
   overwrites a shared value (MG8).** Decision 5's conflict-only rebase now
   covers `planEdit`, `sessionRename`, `sessionReorder` and
   `sessionItemReorder`, next to the cascade deletes and the key edit. A
   retry from any other status resends the original bases. The automatic
   sync never rebases, so a Retry that did would silently overwrite a
   foreign value the user's own overlay hid; now it surfaces as a conflict
   that Keep mine resolves knowingly. Creates and `sessionItemDelete` keep
   rebasing in any status (they add or remove the user's own object). The
   session-rename lookup (`_currentBaseVersionFor` keyed on `sessionId`,
   which a session row does not set) resolves the session by `aggregateId`.
3. **The reconcile and rule 1a are one projection transaction, applied only
   when the projection does not already hold the write (F1, S5b PR 2).**
   `PlanningLocalStore.applyAcceptedWrite` reads the projected plan content
   version `C` and the gate's versioned row, decides, runs the reconcile's
   per-kind writes, then performs rule 1a, in one Drift transaction, so a
   pull cannot store in between. With `R` the record's accepted content
   version (in memory only, backend responses only) and the written version
   the one the reconcile writes: `C >= R` skips reconcile and advance; a
   versioned row (plan, session, session item, by kind) projected above the
   written version skips both; `C == R - 1` applies and sets `C := R`;
   anything else (`C < R - 1`, `C` or `R` unknown) applies without the
   advance. A crash-resumed marker and a key edit not provably the caller's
   own have no `R` and are gated by their versioned row only. The separate
   rule-1a store call and its swallowed failure (item 1) are gone: an
   exception rolls back both and propagates, the rows stay `accepted` and
   the next run resumes them. User decisions (2026-10-27): (1) the
   versioned-row check extends the deferred entry's sketch (which gated only
   `planEdit` and `planCreate`) to every kind, so a pull stored after a
   crash cannot be overwritten by a resumed marker's older base; (2) below
   `R - 1` the write is applied without the advance, so an offline sync
   against a stale projection does not hide the user's own write. Residual,
   pre-existing: a plan deleted by another member after an own `planCreate`
   or `planEdit`, with a pull stored before the reconcile, is re-inserted
   until the next refresh (plan writes do not bump the content version, and
   an absent row cannot show it is newer); it holds no foreign content and
   its delete ends visibly (`plan_not_found`, `failedRemoteDelete`).
