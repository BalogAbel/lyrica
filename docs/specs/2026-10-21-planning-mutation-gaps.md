# Spec: Planning Mutation Gaps (S5b)

> Status: Accepted (2026-10-22, design gate approved). PR 1 (MG1–MG5 and
> their MG13 rows) merged as #97 (`9c16d79`, 2026-10-27). PR 2 (MG6–MG9 and
> the F1 fix) is implemented on `fix/planning-unresolved-rows`, PR open
> (plan: `docs/plans/2026-10-27-planning-unresolved-rows.md`); PR 3 is not
> started. PR 1
> plan: `docs/plans/2026-10-22-planning-run-boundaries.md`. Amends ADR-030 (in-flight create
> cancellation follow-up), ADR-035 (organization switch, import runs, D5
> purge ownership) and ADR-038 (rule 1a placement, retry rule), and
> supersedes the matching options in the deferred entries listed under
> "Deferred Entries".

- Date: 2026-10-21
- Roadmap slice: S5b (`docs/plans/2026-10-01-delivery-roadmap.md`)
- Branches: `fix/planning-mutation-gaps` (this spec, the PR 1 plan and
  PR 1), `fix/planning-unresolved-rows` (PR 2), `fix/purge-and-pull-guards`
  (PR 3)
- Decision IDs: MG1–MG14.
- Backend: no change. No migration, no hosted deploy.
- Hard dependency (merged): S3 PR 2 (#95), which added `sessionItemKeyEdit`
  to the same mutation store and sync controller.

## Problem

S5b collects the open gaps of the planning mutation state machine and the
purge and pull boundaries next to it. Each one was found by a review or an
analysis and recorded as deferred work:

| Item | Source | Effect today |
|---|---|---|
| Organization switch drops pending planning mutations | `2026-10-01-org-switch-drops-pending-planning-mutations.md` | **Silent loss, confirmed on 2026-10-21** (below) |
| Content-version advance on a mid-run context switch | `2026-09-30-content-version-advance-on-context-switch.md` | I7 broken for the old context until its next refresh; a plan delete confirmation can under-count |
| A sync run keeps sending after the context moved (O2) | `2026-10-05-gate-cross-user-leaks.md` | The previous user's rows go out with the new token and end `failedAuthorization` / `conflict` |
| A coalesced refresh can predate the write (R3) | `2026-10-14-key-edit-residuals.md` | One visible self-conflict on the next edit, every versioned kind |
| Stranded create tombstones (resolved by PR 2) | `2026-09-30-stranded-create-tombstones.md` (removed) | A `cancelling` row nobody resolves; delete intent lost if the create committed |
| Session-rename retry never rebases (resolved by PR 2) | `2026-09-30-session-rename-retry-never-rebases.md` (removed) | Keep mine on a rename conflicts forever |
| Discarding a failed create orphans its dependents (R1) | `2026-10-14-key-edit-residuals.md` | Key-edit and order rows fail later, visibly |
| D5 purge resets ignore ownership (O3) | `2026-10-05-gate-cross-user-leaks.md` | A purge for A completing after B became current clears B's planning state |
| Membership purge has no import check | `2026-10-11-membership-purge-import-gap.md` | Rows an import writes between the recount and the deletion are purged uncounted |
| Childless plans after a mid-pull revocation (R2) | `2026-10-12-paged-pull-residuals.md` | `content_version` ahead of the stored children |

**Organization-switch verification (2026-10-21).** A probe test in
`planning_sync_controller_test.dart` (not committed; it becomes PR 1's red
test) recorded a pending `planEdit` for `(user-1, org-b)`, then called
`handleActiveContextChanged` for `(user-1, org-a)`. Result:
`Expected: an object with length of <1>, Actual: []`. The `!sameBoundary`
branch calls `PlanningLocalStore.deletePlanningData`, which deletes the
previous organization's projection **and** its mutation rows, outside the
`LocalDataLifecycle` gate and without a `PurgeReason`. The trigger is real:
the active organization is the smallest organization id
(`active_organization_resolution.dart`), so joining an organization whose id
sorts first switches the context while the old membership is intact.

## Goals

- No planning write is lost, or silently absorbed, because the context moved,
  a run was interrupted, or a refresh came from the wrong moment.
- Every row ends resolved or visible: no state that nothing ever revisits.
- Purges and pulls act only for the user, organization and moment they were
  decided for.
- Every fix covers S3's `sessionItemKeyEdit` (MG13).

## Non-Goals

- An organization switcher, or showing another organization's pending work
  in the sync popup (MG1 records the gap).
- Idempotent create RPCs (tombstone option (b), LF-T5b).
- The session-transition coordinator
  (`docs/deferred/2026-10-11-session-transition-coordinator.md`): S5b adds
  no new background writer and no new purge.
- Gate residuals C4, F5, N1, N2 and paged-pull R1, R3 (S6b), R4.
- Any backend change.

## Invariants (binding for implementation and review)

Unchanged, restated because every decision below is checked against them:

- **I3 (plan-delete spec).** A client base moves only by contiguity with a
  value the backend returned for the client's own write, or onto the
  projection after a visible conflict (Keep mine). When in doubt it stays
  stale: a stale base conflicts (fail-safe), an over-advanced base absorbs a
  foreign write (fail-open, never acceptable).
- **I7.** The projection's `contentVersion` never runs ahead of the content
  it reflects. The F1 race (a pull for the same context stored between C5
  and the reconcile, then the older accepted write written over it) is
  closed by PR 2: the reconcile and rule 1a are one transaction gated on
  the projection (decision F1 below).
- **ADR-019 exactly-once.** An `accepted` row is never resent.
- **ADR-030 D2/D3.** Every write that concludes a remote exchange is gated on
  the revision that was sent; a miss is not an error.
- **ADR-035 D1.** Local user data is destroyed for the four `PurgeReason`s
  only, through `LocalDataLifecycle`.

## Decisions

### PR 1 — context and run boundaries

**MG1. An organization switch keeps the previous organization's planning
data.** (Decides the organization-switch finding: option (a), keep.)

- `PlanningSyncController.handleActiveContextChanged` deletes nothing on a
  boundary change. The previous `(userId, organizationId)` projection and
  mutation rows stay on the device. The new boundary is established exactly
  as today (refresh generation invalidated, state set, refresh started).
- Both are kept, not only the outbox: the merged overlay, Keep mine
  (`_currentBaseVersionFor`, `_projectedKeyItem`) and the D9 retry rebase all
  read the projection. A kept outbox without its projection could not be
  resolved.
- The kept rows sync when that organization is the active context again.
  Nothing sends them while another organization is active: the write
  scheduler, manual sync and retry act on the active context only.
- They are destroyed only by a `PurgeReason` (all four are user-wide), never
  by a switch. An organization switch is not a purge reason (ADR-035
  amendment).
- **Accepted gap (user decision, 2026-10-21):** while another organization
  is active, the previous organization's pending work is invisible in the
  header and the sync popup. Only the sign-out warning counts it
  (`countPlanningPendingWork` is user-wide), and so do the different-user
  reauth wipe and the D5 purge. PR 1 records this as a deferred entry whose
  trigger is an organization switcher or a field report.
- **Known behavior (pinned):** an offline cold start after a switch whose
  first pull failed, with a last known identity that carries no organization,
  falls back to `readLatestCachedOrganizationId` and so lands on the previous
  organization; this matches the song side and "cached data may outlive a
  revocation".
- `PlanningLocalStore.deletePlanningData` loses its only production caller
  and is removed from the interface, the Drift store and the test doubles. A
  destructive primitive outside the gate with no caller is not kept.
- The song side already behaves this way (`SongCatalogStore.deleteCatalog`
  has no production caller); no song change.
- `docs/architecture/architecture.md` ("purges the previous active
  organization data when the active organization changes") is corrected.
- Storage: the projection is never evicted (ADR-028 D4); a second
  organization's projection is small text and counts against the same
  budget.
- Rejected: (b) an audited `organizationSwitched` purge with a warning. The
  switch is automatic, so the user cannot decline it; a "Cancel" would have
  to keep the data anyway. (b) is (a) plus a new `PurgeReason`, a dialog and
  a lost-work path.

**MG2. A planning mutation sync run stops when its context moves.** (O2.)

The same-context predicate answers "is the active planning context still the
run's `(userId, organizationId)`". It becomes **synchronous**: the async
`PlanningAcceptedMutationGuard` (`Future<bool> Function(context)`) is replaced
by `bool Function(ActivePlanningReadContext context)`, which the provider
answers from `activePlanningContextProvider` without awaiting. An awaited
predicate yields a microtask turn, so it could not guard C2. `_run` evaluates
it at named check points:

| Check | Where | On "moved" |
|---|---|---|
| C1 | before a candidate's `sending` write | stop the loop; this and every later candidate stay as they are |
| C2 | after the `sending` write, synchronously before `syncMutation` (no await between C2 and the call) | the call is known not to have left: for a cancellable create, `resolveCancelledCreate(created: false)` (a delete that tombstoned the row meanwhile is a plain collapse); then a reset to `pending` gated on the `sending` revision (a miss means a fold already reset it); stop the loop |
| C6 | after a failed call, before its failure-status write | if moved: tombstone resolution as today, then the same gated reset to `pending` instead of the failure status; stop the loop. A failure answered under a changed identity is not this row's verdict |
| C3 | after the loop, before the batch-end refresh | skip the refresh and take the refresh-failed branch |
| C4 | after the refresh returns | the refresh counts only if it stored a pull for the run's context that started after the request (MG5) |
| C5 | per accepted record at batch end | skip rule 1a (MG4) and the reconcile for that record; the clear still runs |

- A stopped run is not a failure: nothing is marked terminal, and the next
  run in that context picks the rows up.
  - `retryMutation`'s observer still hears it: a retry whose own record a
    stop left unsent must not return as if it had worked. The stop reports a
    connectivity-class failure for every candidate it leaves unsent (the C2
    and C6 rows included: a C6 verdict is discarded), the rule the
    connectivity `break` already follows (ADR-030, fourth review round).
- A user switch releases the active context (XU2), so every check fails for
  it. An organization-only switch by the same user also stops the run; the
  rows simply wait for their context (MG1).
- **Residual (the token is bound inside the call).** `AuthHttpClient.send`
  awaits `_getAccessToken()`, which awaits `auth.getSession()` (supabase
  2.16.5, `auth_http_client.dart:24`, `supabase_client.dart:277-285`), so the
  identity is read after C2. A user switch inside that await can still send
  one row of the previous user with the new token. A failure then lands on
  C6 and the row stays `pending`; a success is accepted under the new user's
  identity (a misattributed write, not a lost one). PR 1 narrows O2 in
  `docs/deferred/2026-10-05-gate-cross-user-leaks.md` to this residual
  instead of removing it.

**MG3. A song mutation sync run stops when its catalog context moves.** (O2,
song side.)

- `SongMutationSyncController` gets an injected predicate: the active catalog
  context equals the run's `SongMutationContext`.
- Checks mirror MG2: before `markCreateSending` (creates) or before the
  send (updates, deletes); synchronously before `syncSong` (a create already
  marked `sending` is resolved as not created if it was tombstoned, and
  otherwise reset to `pendingCreate`, gated on the `sending` revision); and
  after a failed call, before the failure-status write (no `conflict` is
  written for a call answered under a changed identity; the row keeps its
  pending status). On "moved" the loop stops.
- On the song side C1 and C2 coincide for an update and a delete: those
  have no `sending` marker, so there is no await between the two checks and
  both run in the same synchronous turn. C1 is observable only as the
  skipped create marker (`markCreateSending`), pinned by the test 'a context
  that has already moved writes no sending marker for a create'.
- `keepMine` is out of scope: it is a single, user-initiated call.
- The per-record reconcile (`reconcileSyncedSong`) is already gated on the
  mutation row's revision, so a purge that removed the row also skips the
  snapshot upsert; no change there.

**MG4. Rule 1a runs only after a successful reconcile of the same record.**
(Content-version advance: option (a), refined.)

- Rule 1a leaves `applyAcceptedWriteEffects` entirely. That call keeps rules
  1b, 2 and 3 (pending delete rebases), the PS15 fold rebase and the D8
  purges, which act on rows of the run's own context, and it runs exactly
  where it runs today (post-RPC and at batch end, unconditionally).
- (Superseded by decision F1, PR 2.) Rule 1a becomes its own store call, `advanceAcceptedPlanContentVersion`
  (it wraps `PlanningLocalStore.advanceSyncedPlanContentVersion`, only for a
  `remoteResponse` record whose kind `bumpsPlanContent`, with the PS15
  own-write gate for key edits unchanged). The store keeps the moved
  rule-1a block verbatim: the target plan is the accepted record's
  `aggregateId` for plan kinds (`kind.aggregateType == 'plan'`) and
  `accepted.planId` otherwise, and the call does nothing when that id or the
  record's `acceptedPlanContentVersion` is null (the PS15 gate nulls the
  version for a key edit that is not provably the caller's own). The
  `remoteResponse` condition stays at the controller's call site. The controller calls it only at
  batch end, in the refresh-failed branch, when C5 held for the record **and**
  that record's reconcile completed without throwing, immediately after the
  reconcile, in `acceptedRecords` order.
  - The projection therefore takes W first and the advance second. Between
    the two it holds W at R - 1 (behind its content, which I7 allows). A
    failed or skipped reconcile (C5 false, `ReconcileFieldError`, any other
    exception) means no advance: a context switch or a failed or skipped
    reconcile never leaves the projection at R without W. It does not cover
    the F1 race (a pull for the same context stored between C5 and the
    reconcile, then W written over it); decision F1 (PR 2) closes it.
  - A failed advance (an `Exception`, swallowed like the effects call) leaves
    the projection behind: at most one visible false conflict later. PR 2
    removed the separate advance (decision F1): reconcile and advance are one
    transaction, and an exception there propagates.
- In the refreshed branch the refresh stored a pull that started after the
  write (MG5); it already holds R or later, so 1a is not called.
- The same-context `planCreate` case is unchanged: the `planCreate` is
  reconciled at content version 1, then its child is reconciled and advances
  it to 2 when the refresh fails (D7 call sites).
- Why refined: option (a) gated 1a at both of today's call sites, but both
  run before the reconcile, so a context switch, or a reconcile failure,
  between the advance and the reconcile still left the projection at R
  without W (builder check, 2026-10-21).
- **Accepted narrow window (refresh-failed branch only).** Before, rule 1a
  ran inside the effects call, ahead of rule 1b, so a `planDelete` drafted
  after it read R. Now the advance follows the reconcile. A `planDelete`
  recorded at batch end between a record's effects call (rule 1b) and that
  record's advance reads R - 1 from the projection and gets no later rule-1b
  rebase for that record, so it ends in a visible false conflict (fail-safe:
  a stale base conflicts, I3 holds). A delete recorded earlier in the run
  is still rebased by the batch-end rule 1b. The window spans one reconcile.
- **Residual, pre-existing and unchanged:** when C5 fails, the accepted row is
  cleared without a reconcile, so the user's own accepted write W is not
  shown in the old context until that context refreshes. Option (b) (keep
  the row `accepted`) was rejected: it strands `accepted` rows in a context
  the user may never revisit and inflates the sign-out count with work the
  server already holds.

**MG5. A refresh requested after a write never coalesces onto an older run.**
(R3.)

- **"Refreshed" means a stored pull that started after the request.**
  `refreshPlanning`'s `idle` status is not evidence: a queued run that aborts
  before its `refreshing` write, or `handleActiveContextChanged` setting
  `idle` before its own pull, both read `idle` with no post-write pull (builder
  check, 2026-10-21). `PlanningSyncController` therefore counts pulls:
  - `_pullSequence` is incremented when a pull starts its fetch (right before
    `fetchPlanningSyncPayload`), and the run keeps its own number;
  - when that pull's projection replace succeeds and is not stale,
    `_lastStoredPull = (sequence, userId, organizationId)`.
- New entry point `Future<bool> refreshPlanningAfterWrite(ActivePlanningReadContext context)`:
  it captures `startSequence = _pullSequence`, requests a refresh that never
  coalesces onto an older run (it sets `_refreshQueued` whenever a refresh is
  in flight, whatever the generation), awaits the drain, and returns `true`
  only if `_lastStoredPull` has a sequence greater than `startSequence` and
  equals `context`. Any pull numbered after the request started after the
  write, because the write's RPC returned before the request.
  - If the queued flag is lost (it is set after the in-flight future
    completed but before the `finally` clears it), no newer pull is stored and
    the result is `false`: the refresh-failed branch then reconciles W, the
    safe outcome.
- The mutation sync's refresh trigger becomes
  `Future<bool> Function(ActivePlanningReadContext context)`, wired to
  `refreshPlanningAfterWrite`. C4 is that result.
- Cost: one extra full pull when the post-write refresh meets one already in
  flight. Other callers (manual sync, pull-to-refresh, context change) keep
  `refreshPlanning` and today's coalescing.
- Covers every versioned kind, `sessionItemKeyEdit` included.

### PR 2 — rows that never resolve

**MG6. A stale planning tombstone becomes a pending delete at run start.**
(Stranded tombstones: option (a); the session-item base overridden.)

- `_run` first calls a new store method,
  `convertStaleCreateTombstones(context)`, then reads its candidates. The
  conversion is best-effort: the call is wrapped in `try { … } on Exception
  { }` (an `Error` still propagates). A failed conversion leaves the rows
  `cancelling` and the next run retries; it never stops the run, because an
  exception escaping `_run` would fail an unrelated new write through
  `syncScheduler`. Under
  the per-context single-flight no remote call of this context is in flight
  at that moment, so every `cancelling` row is stale.
- The conversion, in one transaction per row:

  | Tombstone kind | Becomes | Base | Why it is the creation-time value |
  |---|---|---|---|
  | `planCreate` | `planDelete` | `baseVersion = 1`, `baseContentVersion = 1` | `create_plan` writes version 1 and content version 1 |
  | `sessionCreate` | `sessionDelete` | `baseVersion = 1` | `create_session` inserts version 1 (no OCC on the plan) |
  | `sessionItemCreateSong` | `sessionItemDelete` | `baseVersion = b + 1`, b = the create row's base | `create_song_session_item` moves the session b → b + 1 under OCC |

  - **Override (session items).** The roadmap default accepted a base of 1
    and its conflict noise. `delete_session_item` checks the session version
    before it looks for the item, so 1 conflicts almost always. b + 1 is the
    session version the client's own create produces: the delete can succeed
    only if the item exists (the create committed, its id is the client's)
    and nobody wrote to the session since, so I3 holds. If the create did
    not commit and the session is quiet, the delete conflicts visibly; Keep
    mine rebases onto the projection and the resend closes the row (below).
    The common stranding causes (the accept-marker write threw, an `Error`
    aborted the run) follow a committed create.
  - Status `pending`, a fresh `orderKey` (after every surviving in-flight
    child row, as D5(c)/(d) and D6 require), the create's `originSnapshot`
    kept, its `slug`/`name` dropped (ADR-038 decision 6 whitelists the RPC
    parameters anyway).
  - The conversion is a write-queue write (ADR-028 D3/D9), never
    budget-admitted: it rewrites one row as one row.
  - The row is marked **tombstone-origin**: a new
    `CachedPlanningMutations.resolvesCancelledCreate` column (boolean, not
    null, default false; planning schema 8 → 9, `onUpgrade` adds it) and a
    `PlanningMutationRecord` field. Retry keeps it; any user-recorded write
    to the aggregate replaces the record and clears it.
- **Outcomes of the converted delete:**
  - accepted → the existing D8 path (purge, reconcile, clear);
  - `*_not_found` (`plan_not_found`, `session_not_found`,
    `session_item_not_found`) on a tombstone-origin row → the row is cleared
    and the D8 child purge runs (the object never existed, so its remaining
    child rows are orphans). A user-recorded delete keeps today's visible
    `failedRemoteDelete` (D9);
  - conflict → `conflict`, visible; Keep mine rebases (MG8);
  - connectivity → stays `pending` (a connectivity failure never discards
    the intent).
- **Accepted consequence.** `plan_not_found` also means "no longer allowed".
  If the member lost the capability and the create had committed, the row
  closes and the plan comes back into the list on the next refresh. Nothing
  the user wrote is lost, and the delete could not be accepted anyway.
- **Accepted consequence.** An uncommitted item create in a session nobody
  touched shows one visible conflict before it closes.

**MG7. A stale song tombstone becomes a pending delete at run start.**
(The song side has the same gap: `cancelling` is excluded from
`readPendingSongs`, and only the run that sent the create resolves it.)

- `SongMutationSyncController._runSync` first converts every `cancelling` row
  of its context to `pendingDelete` with version 1 (`create_song` inserts
  version 1), then reads its candidates. Best-effort like MG6: wrapped in
  `try { … } on Exception { }` (an `Error` propagates); a failed conversion
  leaves the rows `cancelling` and the next run retries, so the outbox never
  stops on it.
- No marker: a `remoteDeleted` answer to a `pendingDelete` already deletes
  the local row (`_runSync`'s existing branch). A conflict ends `conflict`,
  resolved by the existing Keep mine (`overwrite_song_delete`).

**MG8. Retry rebases only from a visible conflict, for every kind that
overwrites a shared value.** (Session-rename retry: the default, extended by
the user on 2026-10-21.)

- `_currentBaseVersionFor` resolves a `sessionRename` by its `aggregateId`
  (the session id), like `sessionDelete`. That is the defect; without it Keep
  mine never rebases.
- `retryMutation` rebases onto the projection only when the row's status is
  `conflict`, for `planEdit`, `sessionRename`, `sessionReorder`,
  `sessionItemReorder`, `sessionItemKeyEdit` (already, PS16), `planDelete`
  and `sessionDelete` (already, D9). A retry from any other status resets the
  row to `pending` with its bases unchanged.
- Why: the automatic sync never rebases, so a Retry that does would silently
  overwrite a foreign value the user never saw (their own overlay hides it).
  With the rule, such a write surfaces as a conflict and Keep mine overwrites
  it knowingly. This is ADR-038 decision 5 (F1) applied to every overwrite.
- Creates (`planCreate`, `sessionCreate`, `sessionItemCreateSong`) and
  `sessionItemDelete` keep today's rebase in any status: they add or remove
  the user's own object and overwrite no foreign value.
- The shown-status guard and the in-flight rule (decision 5) are unchanged.

**MG9. Discarding a create also discards what depends on it.** (Key-edit
residual R1, generalized.)

- New store method `discardMutation`, replacing the plain `clearMutation`
  in `PlanningMutationSyncController.discardMutation`. In one transaction it
  deletes the row and, when the row is a create that is not in flight
  (`sending`, `accepted`, `cancelling`), applies exactly the ADR-028 D10
  collapse effects of that kind:
  - `sessionItemCreateSong`: the item's key-edit row (unless in flight) and
    its entry in the pending item reorder;
  - `sessionCreate`: the session's item, key-edit and item-order rows and its
    entry in the pending session reorder;
  - `planCreate`: every child row of the plan.
- A discarded in-flight create keeps its dependents: its call may commit.
  A dependent kept this way that is itself in flight (for example a `sending`
  key edit of a discarded failed item create) ends visibly if it then fails.
- Write queue only (ADR-028 D3/D9): never budget-admitted, no recovery
  boundary, like `clearMutation`.
- `clearMutation` stays for the sync's revision-gated clears.

**F1. The reconcile and rule 1a are one projection transaction, applied only
when the projection does not already hold the write.** (Design gate approved
2026-10-27; closes `docs/deferred/2026-10-22-content-version-ahead-of-content.md`.)

- New `PlanningLocalStore.applyAcceptedWrite({userId, organizationId, gate,
  apply})`. One Drift transaction reads the projected plan's content
  version `C` and the gate's versioned row, decides, runs `apply` (the
  reconciler's existing per-kind writes; their own transactions nest as
  savepoints), then performs rule 1a. A pull cannot store between the
  decision and the writes.
- The gate (`PlanningAcceptedWriteGate`) carries the rule-1a plan id (the
  moved MG4 block: `aggregateId` for a plan kind, `planId` otherwise), `R`
  (the record's `acceptedPlanContentVersion`, for a `bumpsPlanContent` kind
  only) and an optional versioned row (kind, id, the version the reconcile
  writes). Decision, in order:

  | Condition | Reconcile | Rule 1a |
  |---|---|---|
  | `R` and `C` known, `C >= R` | skipped | skipped |
  | the versioned row is projected at a version **greater** than the one the reconcile writes | skipped | skipped |
  | `R` known, `C == R - 1` | applied | `C := R` |
  | otherwise (`C < R - 1`, `C` unknown, `R` unknown) | applied | none |

  | Kind | `R` | Versioned row (written version) |
  |---|---|---|
  | `planCreate`, `planEdit` | — | plan `aggregateId` (`baseVersion ?? 1`) |
  | `planDelete` | — | — (a delete is monotone) |
  | `sessionCreate` | yes | session `aggregateId` (**1**, never `baseVersion`: `create_session` always inserts version 1 and takes no base, and MG8 can rebase a retried create onto the plan version) |
  | `sessionRename` | yes | session `aggregateId` (`baseVersion ?? 1`) |
  | `sessionDelete` | yes | — |
  | `sessionReorder` | yes | plan `planId ?? aggregateId` (`baseVersion ?? 1`) |
  | `sessionItemCreateSong`, `sessionItemDelete`, `sessionItemReorder` | yes | session `sessionId` (`baseVersion ?? 1`) |
  | `sessionItemKeyEdit` | yes | session item `aggregateId` (`baseVersion`) |

  The written version is what the reconcile already writes: the returned
  version for a backend response, the old base for a crash-resumed
  `accepted` marker, except a `sessionCreate`, which is written (and gated)
  at version 1 whatever its base: the base of a retried create is a plan
  version, not the session's (final review I-1). "Greater", not "equal": an equal version is the same
  state, and rewriting it changes nothing.
- `R` exists only on a record mapped from a backend response
  (`acceptedPlanContentVersion` is in memory only, never persisted), and the
  PS15 gate nulls it for a key edit that is not provably the caller's own.
  A crash-resumed marker and such a key edit are therefore gated by their
  versioned row only and never advance; the reconciler needs no
  `remoteResponse` flag.
- The reconciler validates every required field (LF-8) before any store
  call, so a corrupt record still ends `failedDependency` whatever the
  projection holds, and a throw never leaves a partial write.
- `PlanningMutationSyncController` makes no separate rule-1a call any more:
  `PlanningMutationStore.advanceAcceptedPlanContentVersion` and
  `PlanningLocalStore.advanceSyncedPlanContentVersion` are removed. An
  exception in the transaction rolls back the reconcile and the advance
  together and propagates like any reconcile exception: the rows stay
  `accepted`, the next run resumes them without `R`, and the projection lags
  (fail-safe). MG4's "a failed advance is swallowed" no longer applies.
- **User decisions (2026-10-27).** (1) The versioned-row check is an
  extension of the deferred entry's sketch, which gated only `planEdit` and
  `planCreate` on the plan version. It closes the same race for records
  without `R`: a pull stored after a crash, then a resumed marker's
  reconcile writing the old base over newer content (the next plan delete
  would absorb it). (2) Below `R - 1` the write is applied without the
  advance, as today. Skipping it there would hide the user's own write after
  an offline sync against a stale projection until the next successful
  refresh.
- **Residual, pre-existing.** A plan deleted by another member after an own
  `planCreate` or `planEdit`, with a pull stored before the reconcile, is
  re-inserted by the reconcile until the next refresh (plan writes do not
  bump the content version, and an absent row cannot show it is newer). It
  holds no foreign content, and a delete of it ends visibly
  (`plan_not_found`, `failedRemoteDelete`).

### PR 3 — purge and pull guards

**MG10. The D5 purge resets act only for the current user.** (O3.)

- `ActivePlanningContextController.refresh` sets its state to null after a
  purge only if `_ownership.allows(session.userId)`.
- `PlanningSyncController.handleVerifiedEmptyMembership(userId)` returns
  without resetting unless `_ownership.allows(userId)`.
- The song catalog controller's equivalent reset is guarded by its refresh
  generation; PR 3 adds the same held-purge test for it and fixes it only if
  the test fails.

**MG11. The membership-revocation purge refuses while an import writes the
user's work.** (Membership-purge import gap; ADR-035 amendment.)

- `LocalDataLifecycle.maybePurgeForMembershipRevocation` takes
  `required bool Function() isImportRunning`; the coordinator passes
  `() => importRunTracker.isRunningFor(userId)`.
- Check 1: before the initial count (so no dialog is shown for a purge that
  would be refused). Check 2: inside the final chain link, after the recount,
  synchronously before `purgeSongCatalog` (no await between).
- Either check true → decline: nothing deleted, the marker left set, a new
  `MembershipRevocationPurgeDeclineReason.importRunning` audit record. A
  later counted confirmation retries.
- `ImportRunTracker.isRunning` (user-agnostic, read only by tests) is removed;
  those tests use `isRunningFor`.

**MG12. The planning pull re-checks membership after the child streams.**
(Paged-pull R2.)

- `SupabasePlanningRepository.fetchPlanningSyncPayload` calls
  `current_organization_ids()` after the `session_items` stream (and after a
  `shouldContinue` check). If the requested organization is not in the
  result, it throws a typed `PlanningMembershipChangedException`; the refresh
  fails and the stored projection stays (ADR-041 decision 3). It is not
  reported to observability (it is an expected outcome, like an abort).
- Not the `content_version > 1` with no sessions rejection (roadmap
  2026-10-12): a plan whose sessions were all deleted has that shape.
- **Residual:** a revocation and a restore both inside the pull window still
  pass. Accepted: it needs two membership changes inside one pull.

### Cross-cutting

**MG13. `sessionItemKeyEdit` coverage.**

| Decision | Key edit |
|---|---|
| MG1 | key-edit rows are planning mutation rows: kept with the outbox |
| MG2 | stopped like every candidate |
| MG4 | `bumpsPlanContent` is true: rule 1a runs after the item's reconcile, still gated by the PS15 own-write rule; the PS15 fold rebase stays in the unconditional effects call, and its existing extra calls after a missed accept write or clear are unchanged |
| MG5 | the projection item's `version` comes from the after-write refresh, so the next edit reads it (the R3 self-conflict) |
| MG6 | an item tombstone's key-edit row was dropped at tombstone time unless in flight; the converted delete sorts after it, and its acceptance runs the existing key-edit purge |
| MG8 | already conflict-only (PS16); a PR 2 test pins it next to the rename |
| MG9 | the dependent row R1 names |
| MG10–MG12 | no key-edit-specific behavior; the pull already maps `version`, `transpose`, `capo` |

**MG14. Documentation and deploy.**

- No backend change and no hosted deploy.
- Each PR updates, in the same change: this spec's status note, the
  roadmap row, the ADR amendment's status, `docs/architecture/architecture.md`
  where it describes the changed behavior, and the deferred entries it
  resolves (removed, or narrowed to what stays open).
- PR 1 adds the MG1 gap as a deferred entry.

## Await Points in `_run` (where a fold or a context change can land)

Every gated write is listed with what a miss means after S5b:

| # | Await | A fold or delete lands here | The context moves here |
|---|---|---|---|
| A0 | `convertStaleCreateTombstones` (MG6), implemented by PR 2 | n/a (no candidate read yet) | conversion is local to the run's context; C1 stops the loop; best-effort: an `Exception` is swallowed, the rows stay `cancelling`, the next run retries |
| A1 | `readAllMutations` | the snapshot misses it; the next run sends it | C1 stops before any send |
| A2 | `sending` write (gated) | the write misses → skip (D3) | C2: resolve as not created / gated reset to `pending`; stop |
| A3 | `syncMutation` (the token is read inside it) | the accept write misses (A5) | inside the call's own `getSession` await: the MG2 residual; a failure lands on C6 |
| A4 | post-RPC effects (1b/2/3, PS15, D8; no 1a) | idempotent; repeated at A5/A8 | run's own rows; unconditional |
| A5 | accept write (gated) | miss → `resolveCancelledCreate` / PS15 re-rebase (today's rules) | the next iteration's C1 stops |
| A6 | failure path: `resolveCancelledCreate`, failure write (gated) | today's rules | C6 replaces the failure status with a gated reset to `pending` |
| A7 | batch-end refresh | a fold during it makes the clear miss (A10) | C3 before it skips it; C4 = "a pull for the run's context, started after the request, was stored" |
| A8 | batch-end effects (1b/2/3, PS15, D8) | idempotent | unconditional |
| A9 | reconcile and 1a in one transaction (F1) | the clear misses; a pull stored before the transaction makes the gate skip both | C5 checked once before the transaction; the transaction is a single projection write, so a switch cannot land between W and the advance |
| A10 | clear (gated) | miss → PS15 re-rebase for key edits | the clear still runs (rows of the run's own context) |

## Roadmap Defaults: Confirmed or Overridden

| Default (roadmap "Recommended Defaults / S5b") | S5b decision | Reason |
|---|---|---|
| Stranded tombstones: option (a), convert at run start, tombstone-origin marker | Confirmed (MG6), plus the song side (MG7) | (b) needs idempotent create RPCs; the song side has the same gap and needs no marker |
| Session items: accept the conflict noise of base 1 | **Overridden:** base b + 1 (MG6) | `delete_session_item` checks the session version first; b + 1 is the client's own create's result, so the committed case closes silently and I3 holds |
| Session-rename retry: rebase only after a visible conflict | Confirmed and **extended** to `planEdit` and both reorders (MG8) | the same silent overwrite exists for every value-overwriting kind |
| Content-version advance: option (a), gate 1a with the same-context predicate | Confirmed, **refined** (MG4): 1a moves to batch end, inside the reconcile decision | gating the post-RPC call still leaves a window before the reconcile |
| Organization switch: test first, then decide | Verified red; **keep** (MG1) | the switch cannot be declined; songs already keep |
| O2: stop the run on a context change, both controllers | Confirmed (MG2, MG3) | — |
| O3: ownership guard on the D5 resets | Confirmed (MG10) | — |
| R2: membership re-check after the child streams | Confirmed (MG12) | — |
| Import gap: `isRunningFor(userId)`, ADR-035 amendment | Confirmed (MG11) | — |
| R1, R3 (added 2026-10-20) | Confirmed (MG9, MG5) | R1 generalized to every create kind |

## PR Boundaries

All three touch the planning sync hotspots, so they run one after another,
in this order. Each PR starts with red tests and passes the full suite at
every task.

### PR 1 — context and run boundaries (`fix/planning-mutation-gaps`)

- MG1, MG2, MG3, MG4, MG5, and the MG13 rows for them.
- Files: `planning_sync_controller.dart`, `planning_mutation_sync_controller.dart`,
  `planning_providers.dart`, `drift_planning_mutation_store.dart`
  (rule 1a out of `applyAcceptedWriteEffects` into
  `advanceAcceptedPlanContentVersion`), `budgeted_planning_mutation_store.dart`
  (queued pass-through), `planning_mutation_sync_types.dart` (interface),
  `planning_local_store.dart` (`deletePlanningData` removed),
  `song_mutation_sync_controller.dart` and its provider.
- Why together: MG1 keeps the old projection, which makes the MG4 gap
  reachable on every switch; the two must land together. MG2/MG5 share the
  batch-end checks with MG4.
- Red tests first:
  - the organization-switch probe (pending rows and projection of the
    previous organization survive; the new organization does not read them);
  - a run with a remote double that blocks on candidate 1, a context switch,
    a release: candidate 2 still `pending` (planning and song);
  - C2: a switch landing during the `sending` write sends nothing and leaves
    the row `pending` (or, if it was tombstoned meanwhile, collapsed);
  - C6: a failure answered after a switch leaves the row `pending`, not
    `failedAuthorization` / `conflict` (planning and song);
  - CV, both branches: a child write accepted in A, a switch before batch
    end; A's projection still at R - 1 and nothing cleared into a state at R
    without W; a `ReconcileFieldError` on the record leaves the projection at
    R - 1; the same-context `planCreate` → child case still reaches 2;
  - R3: a refresh in flight that started before the write; the after-write
    refresh runs again and the projection holds the returned version (key
    edit and one structural kind); a queued run that aborts before its pull,
    and an `idle` set by a context change, both count as not refreshed;
  - the retry observer hears a stopped run's unsent record.
- The existing tests that pin the boundary delete are changed: "switching to
  a new active organization that fails to refresh does not expose the
  previous organization projection" is rewritten to pin the keep (the new
  organization still reads nothing of the old one, and the old one's rows
  are intact), and "stale previous-boundary delete is aborted when ownership
  returns to that organization" is deleted with its test double, because the
  aborted delete it guarded no longer exists.
- Prove the guards can fail: revert each check (C1–C6, the pull-sequence
  test, the never-coalesce queueing, the 1a-after-reconcile order, the MG1
  delete removal) one at a time and watch its test fail.
- Docs: ADR-035 amendment (MG1), ADR-038 amendment (MG4), architecture.md,
  the deferred entries for the organization switch, content-version advance,
  O2, R3; the new MG1 gap entry.

### PR 2 — rows that never resolve (`fix/planning-unresolved-rows`)

- MG6, MG7, MG8, MG9, and the F1 fix (decision F1 above;
  `docs/deferred/2026-10-22-content-version-ahead-of-content.md`, removed by
  this PR).
- Plan: `docs/plans/2026-10-27-planning-unresolved-rows.md`.
- Files: `drift_planning_mutation_store.dart`, `budgeted_planning_mutation_store.dart`,
  `planning_mutation_sync_types.dart`, `planning_local_database.dart`
  (schema 9), `planning_local_store.dart` and `planning_mutation_reconciler.dart`
  (F1), `planning_mutation_sync_controller.dart` (run start, discard, F1),
  the Supabase planning mutation repository (`*_not_found` classification
  for tombstone-origin rows, if it is done there), the song catalog store
  and `song_mutation_sync_controller.dart`.
- Red tests first: a tombstone stranded by an aborted run is resolved by the
  next run, for a committed and an uncommitted create, for plan, session and
  item (planning) and for a song; the item base is b + 1; a connectivity
  failure keeps the converted delete; a conflicted rename retried after a
  refresh is sent with the projection's version; a connectivity retry of
  `planEdit`, rename and both reorders resends the original base; discarding
  a failed item, session and plan create removes the dependents and keeps an
  in-flight one's.
- Docs: ADR-030 amendment (MG6, MG7), ADR-038 amendment (MG8, F1), ADR-028 D3
  table (`discardMutation`), the deferred entries for stranded tombstones,
  session rename, R1 and F1. The F1 tests in
  `planning_content_version_ahead_test.dart` lose their `skip:`.

### PR 3 — purge and pull guards (`fix/purge-and-pull-guards`)

- MG10, MG11, MG12.
- Files: `active_planning_context_controller.dart`, `planning_sync_controller.dart`,
  `local_data_lifecycle.dart`, `planning_providers.dart` (coordinator),
  `import_run_tracker.dart`, `supabase_planning_repository.dart`, and the
  song catalog controller only if its held-purge test fails.
- Red tests first: a D5 purge held on a gate, a switch to B, a release: B's
  planning context and sync state unchanged; an import running for the user
  at check 1 and, separately, starting between the recount and the deletion:
  nothing deleted, `importRunning` recorded; a payload whose membership
  re-check no longer lists the organization fails the refresh and keeps the
  projection.
- Docs: ADR-035 amendment (MG10, MG11), the deferred entries for O3, the
  import gap and R2.

## Deferred Entries

| Entry | After S5b |
|---|---|
| `2026-10-01-org-switch-drops-pending-planning-mutations.md` | removed by PR 1; the MG1 gap gets its own entry |
| `2026-09-30-content-version-advance-on-context-switch.md` | removed by PR 1 |
| `2026-10-05-gate-cross-user-leaks.md` | O2 narrowed by PR 1 to the token-binding residual (MG2), O3 removed by PR 3; C4, F5, N1, N2 stay |
| `2026-10-14-key-edit-residuals.md` | R3 removed by PR 1, R1 by PR 2; R2, R4 stay |
| `2026-09-30-stranded-create-tombstones.md` | removed by PR 2 (done) |
| `2026-09-30-session-rename-retry-never-rebases.md` | removed by PR 2 (done) |
| `2026-10-22-content-version-ahead-of-content.md` | added by PR 1 (F1); removed by PR 2 (done) |
| `2026-10-11-membership-purge-import-gap.md` | removed by PR 3 |
| `2026-10-12-paged-pull-residuals.md` | R2 removed by PR 3; R1, R3, R4 stay |
| `2026-10-11-session-transition-coordinator.md` | not triggered (no new writer or purge) |
| `2026-09-28-client-abandoned-committed-write-lf-t5b.md` | unchanged; MG6 does not need idempotent creates |

## Acceptance

- The organization-switch probe passes: the previous organization's pending
  rows and projection survive a switch and sync when it is active again.
- No run sends a candidate after its context moved, in either controller.
- After a mid-run switch, no projection holds a `contentVersion` ahead of its
  content (the F1 race is closed by PR 2's gated transaction; its tests no
  longer skip).
- An after-write refresh never reuses a pull that started before the write.
- No `cancelling` row survives the next run of its context.
- Keep mine works for a conflicted rename; no Retry overwrites a foreign value
  without a visible conflict first.
- Discarding a create leaves no dependent row that can only fail.
- A D5 purge never resets another user's planning state, never runs while an
  import writes that user's work, and a pull never stores children read after
  the membership ended.
- The full suite, `flutter analyze` and the architecture tests pass at every
  task of every PR.
