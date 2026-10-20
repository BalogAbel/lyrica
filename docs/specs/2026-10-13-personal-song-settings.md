# Spec: Song Key Layers (S3)

> Status: Accepted (2026-10-13, design gate approved). PR 1 (backend)
> merged as #94 (`603d69b`, 2026-10-14) and deployed to the hosted project;
> PR 2 (planning client) merged as #95 (`4cbdacb`); PR 3 (reader) passed
> its UI design gate on 2026-10-20 and is planned on `feat/song-key-reader`
> (`docs/plans/2026-10-20-song-key-reader.md`). PS14–PS16 refined on
> 2026-10-14 (base values, the PS15 state rule, C11); PS5, PS7 and PS9
> refined and PS25–PS26 added on 2026-10-20 (PR 3 design gate). Amends
> `docs/specs/2026-04-01-session-scoped-plan-reader-navigation.md`
> ("Reader-Local State Preservation"). The file keeps the slice's original
> name, "personal song settings"; the brainstorm replaced the per-user
> personal layer with the shared layers below (see "Scope Change").

- Date: 2026-10-13
- Roadmap slice: S3 (`docs/plans/2026-10-01-delivery-roadmap.md`)
- Branches: `feat/personal-settings-backend` (PR 1), then one branch per PR
- ADR: ADR-042 (song key layers). PR 1 amends ADR-038; PR 2 amends ADR-028 D3.
- Decision IDs: PS1–PS26.
- Hard dependencies (merged): S1 (ADR-039 grant model), S2 (one consistent
  ChordPro base, `docs/specs/2026-10-12-chordpro-base-directives.md`).
- Next slice: S5b, because S3 re-enters the planning mutation state machine
  (the `docs/deferred/README.md` planning rule).

## Problem

Transpose and capo exist only as reader runtime state
(`SongReaderState.transposeOffset` and `capoOffset`, applied as
`song.baseTranspose + offset` in `song_reader_projection.dart`). In a plan
session, `SessionScopedReaderRuntimeController` keeps one reader state per
session, so a transpose made on one song carries over to the next one
("Reader-Local State Preservation" in the 2026-04-01 spec).

A team has no way to say "in this service, this song is in A, capo 2", and a
musician who changes the key for a moment has it follow them to the next song.

## Scope Change (decided in the brainstorm, 2026-10-13)

The roadmap planned per-user transpose and capo on a new personal layer (a
third sync domain). The user replaced it with three layers, two of them
shared:

| layer | visible to | set by | stored |
|---|---|---|---|
| Temporary | this reader screen only | anyone | nowhere |
| Plan | everyone who opens the song from that plan | `canEditSessions`, from the plan reader | server, on the session item |
| Song | everyone, everywhere | the song editor only (unchanged) | the ChordPro base `{transpose}` / `{capo}` |

Consequences:

- S3 adds no new sync domain, table, pull, outbox, `PurgeTarget`, pending-work
  source or organization-switch rule. The plan layer is two columns on
  `session_items` and one more planning mutation kind.
- The per-user personal layer moves to S4 (annotations), with the roadmap's
  former S3 defaults and the open design points recorded there.
- Per-user layers stay possible as future layers of the same chain (PS22).

## Decisions

### Layers and resolution

**PS1. Three layers, resolved per field.** Transpose and capo each resolve
independently, first non-null wins:

1. the temporary value (reader only);
2. the plan value, only when the reader was opened from a plan session item;
3. the song base (`ParsedSong.baseTranspose`, `ParsedSong.baseCapo`).

The resolution is one pure function over an ordered list of layers (PS22), so
the reader, the projection and the plan detail never re-implement it. It
returns, per field, the effective value and the layer it came from.

**PS2. Absolute values; plan fields nullable.** Every layer stores the value
the reader shows: the transpose relative to the written chords and the capo
fret. A song editor who later changes the base does not move a stored plan
value. A plan field that is `null` falls through to the song base. Rejected:
storing a delta over the base, which silently moves the plan's key whenever
the base changes.

**PS3. The song layer is the ChordPro base, written only by the song editor.**
The reader never writes `{transpose}` or `{capo}`. The editor keeps its
existing Transpose and Capo controls and the S2 base-region write (BD6).

**PS4. The plan layer belongs to the session item.** Deliberate
consequences, each one accepted:

- The same song in two sessions of one plan has two independent values.
- Removing a song from a session and adding it again loses its key (a new
  item).
- **Save to plan** writes only the item the reader was opened from.
- A reorder keeps the key: `reorder_session_items` updates `position` in
  place and never deletes and re-inserts rows (verified on `c713872`).
- S7 follow-ups (roadmap): a plan duplicate copies each item's key; a
  session-item move keeps it.

Rejected: a `(plan_id, song_id)` key. It would need its own table and
cascade, and a song played in two sessions could not have two keys.

**PS5. The temporary layer.**

- It lives only in reader runtime state and is never persisted.
- It is cleared on every song change: previous/next inside a session, any
  route to another song, and leaving the reader.
- This ends the session-wide transpose and capo carry-over (amends the
  2026-04-01 spec). View mode, instrument display mode, the shared font scale
  (zoom, ADR `2026-06-06-reader-zoom-local-persistence.md`), auto-fit and the
  control presentation keep their current behavior.
- A field counts as temporary only while its temporary value differs from the
  value the layers below would give. Stepping back to that value drops the
  temporary value, and the field's source label returns to `Plan` or `Song`.
  The resolver applies the same rule when a lower layer changes to equal the
  temporary value (a sync, or the user's own Save).
- **Refined 2026-10-20 (PR 3 design gate).** The temporary layer records whom
  it belongs to: the session item inside a plan, the song otherwise, plus the
  reader visit (one per reader screen opened). A reader showing another item
  or song, or the same item reopened, reads no temporary value. This also
  covers the frame between a song change or a reopen and the runtime reset
  (`startSession` runs in a post-frame callback, and the plan reader's
  runtime state outlives the screen), and a library reader whose screen
  state is reused for another song.
- **Refined 2026-10-20.** "Drops" means the value leaves the reader state,
  not only the label: when a lower layer changes to equal a temporary value
  (a sync, or the user's own Save), the reader removes that field from the
  temporary layer, so a later change of the lower layer cannot bring the old
  temporary value back.

### Reader UX

**PS6. `±` is always temporary.** Every Transpose and Capo `±` changes only
the temporary layer, in every context, for every member. Nothing is saved
automatically: a single tap on stage must never change the key on other
members' screens.

**PS7. Source labels and actions.**

- Each of Transpose and Capo shows its source: `Song`, `Plan` or `Temporary`.
- **Reset** (shown while any field is temporary) clears both temporary
  values.
- Inside a plan, for a member with `canEditSessions` on the session's group
  (the same capability check the plan detail uses for adding and removing
  songs):
  - **Save to plan**, shown inline next to the values while a field is
    temporary. It saves only the temporary fields (`set` for each of them,
    `keep` for the others) and then clears the temporary layer, so the labels
    read `Plan`.
  - **Clear plan value**, in the controls menu while the item has a plan
    value. It clears both plan fields; the song base applies again.
- Opened from the library, and for members without `canEditSessions`, the
  reader offers temporary changes and Reset only.
- No dialog anywhere in this flow. Save and Clear work offline: they record a
  planning mutation (PS14) and sync later. The reader shows the merged plan
  value (the projection plus the user's own pending edit) at once.
- **Refined 2026-10-20 (PR 3 design gate): present, enabled while
  applicable.** Reset and Save to plan do not appear and disappear; they are
  always present where they apply (Reset in every reader, Save to plan for a
  member with `canEditSessions` inside a plan) and are enabled only while a
  field is temporary (Save to plan: and every temporary field is inside the
  PS9 range). Reason: the compact control rail is vertically centered, so a
  rail that grew after the first `±` tap would move the buttons under the
  musician's finger.
- The editor preview reuses `SongReaderState`; it must render the base only,
  with no temporary or plan layer.

**PS8. The plan detail shows each song row's plan key.** Display only, from
the merged plan detail: `Transpose +2`, `Capo 2`, or both, only for fields
that have a plan value. No key name is resolved here (YAGNI).

**PS9. Value bounds.**

- Plan values: transpose −11..+11, capo 0..11. The server enforces them (PS10,
  PS11); the client never records a value outside them.
- The song base may lie outside the range (the parser accepts any integer).
  The reader shows it unchanged.
- `±` never moves away from the range and never jumps: from an out-of-range
  value only the step toward the range is enabled, one semitone or fret at a
  time; at a range edge the step outward is disabled. The capo never goes
  below 0.
- **Save to plan** is disabled while a temporary field is out of range. It
  never writes an out-of-range value.
- **Refined 2026-10-20 (PR 3 design gate).** The step rules apply to `±` in
  every reader, the library included, so every temporary value can be saved
  once it is back in range. A disabled step is a disabled button. A negative
  song base capo counts as 0, as the reader already renders it; `±` starts
  from 0.

**PS25. Reader UI placement (added 2026-10-20, PR 3 design gate).**

- **Source label colors:** `Song` uses the value chip's current neutral
  color (`surfaceContainerHighest`), `Plan` uses `primaryContainer`,
  `Temporary` uses `tertiaryContainer` (each with its `on…` foreground). The
  word is always shown; color never carries the source alone.
- **Compact (control rail):** the value chip takes the source color, and a
  caption under it reads `Song`, `Plan` or `Temporary`, in a fixed-width slot
  that scales the text down rather than widening the rail. A new rail group
  sits between the capo group and the font group: Reset (icon), then Save to
  plan (icon, only for a member with `canEditSessions` inside a plan), each
  with a tooltip. The rail's size does not change when a field becomes
  temporary.
- **Expanded (tools panel):** each control section's label row shows the
  source as a badge at its end. A button row sits under the capo section and
  above Scale: `Reset` (text button) and `Save to plan` (tonal button, same
  condition as above).
- **Clear plan value:** an item in the reader's overflow menu, which both
  layouts share, after the guitar/piano items and before the theme item, set
  apart by dividers. Shown only inside a plan, for a member with
  `canEditSessions`, while the item has a plan value in either field.
- **Plan detail (PS8):** a row of small chips under the song title,
  `Transpose +2` and `Capo 2`, one per field that has a plan value. Under the
  title rather than at the row's end, so a phone row keeps its title width
  next to the drag handle, the chevron and the delete button. A row without
  a plan value is unchanged.
- **No other feedback:** no snackbar and no dialog. The label change to
  `Plan` is the confirmation; a pending or failed edit shows in the sync
  popup (PS18). The bottom bar is unchanged.

**PS26. Reader wiring (added 2026-10-20, PR 3 design gate).**

- **Resolver (PS1, PS22):** a pure domain function over an ordered layer
  list (`resolveSongKey` in `lib/src/domain/song/song_key_layers.dart`). A
  layer has an id (`temporary`, `plan`, `song`), nullable values, and a
  transient flag; a transient layer claims a field only while its value
  differs from what the layers below give (the PS5 rule). The last layer must
  give both fields. The PS9 step rules live next to it. The reader builds the
  list in one place (`SongReaderKeyLayers`): temporary (transient), plan
  (only inside a plan), song (base values, capo floored at 0). A new layer is
  a new entry there and a new id with its label.
- **State:** `SongReaderState` drops `transposeOffset` and `capoOffset` and
  holds the temporary layer (owner id plus nullable absolute values).
  `SongReaderProjection` takes the resolved key; without one it renders the
  song base (the editor preview).
- **Plan value source:** the live merged plan detail
  (`planningPlanDetailProvider`, read directly, not through a derived async
  provider that would lag it by a frame), never the route's warm plan
  detail, which the reader keeps passing along on previous/next and which is
  not refreshed after a Save. The warm detail's item is used only while the
  live read has no value yet. When the live detail has no such item, the
  reader has no plan layer and no Save to plan or Clear plan value.
- **Capability:** the same organization-level `canEditSessions` check the
  plan detail uses: the cached `CapabilityResolver.hasCapabilitySync` result
  when there is one (so Save to plan is in place on the first frame), else
  `hasCapability`; fail-closed (unknown or failed means no Save and no
  Clear). The server enforces the group scope (PS11).
- **Save sequence:** build the edit from the resolver output (`set` for each
  temporary field, `keep` otherwise, whatever the instrument view: a capo
  changed in guitar view and still temporary in piano view is saved, as Reset
  also clears it); record it through `PlanningWriteService.setSessionItemKey`,
  which calls the reader back once the edit is recorded and before its sync
  attempt (the sync can take seconds online and longer offline); refresh the
  plan detail at that point, through a provider container captured before the
  write, so a reader closed in between still refreshes the plan detail. The
  temporary value then drops by the PS5 rule as soon as the plan layer shows
  it; a `±` tap during the save stays temporary, because it no longer equals
  the plan value. If the write throws, nothing changes. While a write of this
  reader is in flight, Save to plan is disabled and Clear plan value is not
  offered.

### Backend (PR 1)

**PS10. Schema.** `session_items` gains:

- `transpose smallint null`, `check (transpose between -11 and 11)`;
- `capo smallint null`, `check (capo between 0 and 11)`.

Both default to `null`. `authenticated` reads them through the existing
table-level `SELECT` grant (ADR-039); no grant changes. No existing RPC writes
them: `create_song_session_item` inserts an explicit column list, so a new
item starts with `null`, `null`; `reorder_session_items` writes only
`position`; `delete_session_item`, `delete_session` and `delete_plan` remove
rows. `session_items.version` keeps its default of 1 and from now on counts
key edits only (PS13).

**PS11. RPC `set_session_item_key`.**

```sql
public.set_session_item_key(
  p_organization_id uuid,
  p_session_id uuid,
  p_session_item_id uuid,
  p_base_version bigint,      -- the item's version the edit was made against
  p_transpose_mode text,      -- 'keep' | 'set' | 'clear'
  p_transpose integer,        -- required for 'set', null otherwise
  p_capo_mode text,           -- 'keep' | 'set' | 'clear'
  p_capo integer              -- required for 'set', null otherwise
)
returns table (
  id uuid,
  plan_id uuid,
  session_id uuid,
  organization_id uuid,
  version bigint,
  transpose integer,
  capo integer,
  plan_content_version bigint
)
```

- `security definer`, owned by `postgres`, `set search_path = public`.
- `revoke all ... from public, anon, authenticated`; `grant execute ... to
  authenticated`. No `service_role` grant (no operation calls it).
- Authorization: the session must be visible to the caller with
  `has_capability(session.organization_id, 'canEditSessions',
  session.group_id)`, the same rule as every session-item RPC. Read-only
  members, non-members and other organizations get `session_not_found`.

**PS12. RPC semantics, in this order.**

1. **Validate the payload.** Each mode is one of `keep`, `set`, `clear`;
   `set` requires a non-null value inside the PS9 range; `keep` and `clear`
   require `null`. Otherwise raise `invalid_session_item_key` (SQLSTATE
   `22023`). Nothing is read or locked.
2. **Require a base.** A null `p_base_version` raises
   `session_item_version_conflict` (`P0001`), like the other planning RPCs.
3. **Authorize** (PS11). Not found or not allowed: `session_not_found`
   (`P0002`).
4. **Lock the owning plan row** (`select ... for update`), without bumping it
   yet. This keeps ADR-038's lock order (plan, then session, then item), so
   the RPC serializes with every child write and cascade delete of the plan.
   A plan that is gone raises `plan_not_found` (`P0002`).
5. **Re-read the item** in `p_session_id` after the lock (`for update`),
   song items only (`item_type = 'song'`). Missing, or an attachment or note
   item: `session_item_not_found` (`P0002`).
6. **No-op.** If every field whose mode is `set` or `clear` already holds the
   requested value (`set`: equal; `clear`: null), return the current row:
   the current item `version`, `transpose`, `capo` and the plan's current
   `content_version`. Nothing is written and nothing is bumped, whatever
   `p_base_version` is. An edit with both modes `keep` is the trivial no-op.
   This is the LF-T5b mitigation: a resend of an edit the server already
   applied succeeds.
7. **OCC.** If the item's `version` differs from `p_base_version`, raise
   `session_item_version_conflict` (`P0001`) with the expected and the
   current version in the detail. Nothing changes.
8. **Write.** Bump the plan's `content_version` through
   `bump_plan_content_version`, then update the item: the fields per mode,
   `version = version + 1`, `base_version = <old version>`,
   `sync_status = 'synced'`, `last_modified_by = auth.uid()`. The session's
   `version` is not touched. Return the new row with the new
   `plan_content_version`.

**PS13. What a key edit versions.**

- **`session_items.version`** is the key edit's OCC counter. Key edits on
  different items, and a key edit next to a structural write in the same
  session, never conflict.
- **`plans.content_version`** is bumped (ADR-038 I4 holds unchanged), so a
  plan delete recorded from a view older than the key edit conflicts.
- **`sessions.version` is not bumped.** A session's version covers its
  structure (items added, removed, reordered) and its name; a key is not
  structure. Consequence, accepted: a session delete recorded from a stale
  view still succeeds over a concurrent key edit. The deleting user removes
  the items they saw; the key edit adds no content they did not see. Bumping
  the session version instead would make every key edit conflict with the
  user's own pending structural writes in that session. PR 1 records this in
  an ADR-038 amendment.

### Planning client (PR 2)

**PS14. One new mutation kind.**

- `PlanningMutationKind.sessionItemKeyEdit`, aggregate type
  `session_item_key`, aggregate id = the session item id, with `planId` and
  `sessionId` set. A separate aggregate type keeps the row apart from the
  item's own create and delete rows (the store keeps one row per
  `(userId, organizationId, aggregateType, aggregateId)`).
- Payload: the mode and value per field, plus the **base values**: the
  item's projection `transpose` and `capo` at the base version (PS15 needs
  them). Recorded through
  `PlanningWriteService` → `BudgetedPlanningMutationStore`, a tenth
  budget-admitted `record*` method (ADR-028 D3 amended in PR 2). The store
  refuses an out-of-range value with an `ArgumentError` (a programming
  defect; the reader never offers one).
- **Base version:** the item's `version` from the merged read. An item whose
  create is still pending has none; its base is 1, the version
  `create_song_session_item` writes.
- **Fold:** a second edit of the same item while the row is not in flight
  merges into it: a later `set` or `clear` replaces that field's intent, a
  later `keep` leaves it. The first captured base is kept (ADR-028 squash
  rule).
- `bumpsPlanContent` is true, so the existing rule 1a and the pending plan
  delete contiguity rebase (ADR-038 D4) apply, but only to a response that
  passes the PS15 own-write state rule. A no-op or foreign-state response
  returns the CURRENT content version without a bump of this write, and that
  value can include foreign bumps, so the client discards it: it never feeds
  rule 1a or 1b (the projection lags and a stale plan delete conflicts, the
  fail-safe direction).
- **Interactions:**
  - The row is sent after the item's own pending create (order key).
  - Deleting the item locally drops a pending key-edit row that is not in
    flight. One in flight is left to finish; the delete follows. When that
    delete is accepted, a key-edit row of the item that has since ended
    `conflict` or `failed*` is removed with it (a still in-flight one stays).
  - Collapsing a pending create drops its key-edit row.
  - An accepted session or plan delete removes the key-edit rows of its
    items, through the existing child-mutation cleanup, which must match the
    new aggregate type.

**PS15. No self-conflict.**

- **Reconcile after an accepted edit or a no-op success:** the projection's
  item takes the returned `version`, `transpose` and `capo`: through the
  post-sync refresh, or, when that refresh fails, through the reconciler, in
  the same order as every other kind (rule 1a, then the reconcile). The next
  edit reads the new version.
- **An edit folded into a row whose previous content was in flight or
  accepted but not yet cleared** resets the row to pending with the first
  base. When the earlier send's response is applied, the row is rebased only
  if the server state is provably the one the client's own write produced:
  the returned version `R` equals the sent base `b` + 1, and the returned
  `transpose` and `capo` equal the sent payload applied to the sent base
  values. Then the row's base becomes `R` and its base values the returned
  values. A plain version check (`R == b + 1`) is not enough, because a no-op
  success (PS12 step 6) can return `b + 1` after a foreign write; the state
  check makes such a case either identical to the client's own write (safe to
  build on) or a visible conflict. Anything else keeps the base, and a stale
  base conflicts, the fail-safe direction. The rule runs in
  `applyAcceptedWriteEffects`, which the sync run calls right after the
  response and again before the batch-end clear, and, for this kind, again
  after the accept write or the clear misses its revision, so a fold landing
  between any two awaits is covered; a crash-resumed `accepted` marker
  carries no response and never rebases. The same state rule gates the
  response's `plan_content_version`: a response that is not the client's own
  write contributes no content version to D7 rules 1a and 1b.
- **Inherited gap, accepted:** when a context switch skips the reconcile
  (`docs/deferred/2026-09-30-content-version-advance-on-context-switch.md`),
  the projection keeps the old item version. The next key edit on that item
  then shows one visible false conflict, which Keep mine resolves. S5b covers
  the new kind with the rule it picks.

**PS16. Keep mine and Discard mine.**

- A conflicted key edit shows the plan row's existing recovery actions.
- **Keep mine** rebases only from a visible `conflict`: the base becomes the
  session item's `version` in the current projection, and the base values
  its `transpose` and `capo`. `_currentBaseVersionFor`
  resolves `sessionItemKeyEdit` to that item, never to the session or the
  plan. This is the S5b session-rename defect (a lookup by the wrong id, so
  the retry never rebases and conflicts forever), which must not repeat here.
- Any other retry resends the original base (S5b's default: rebase only after
  a visible conflict). For this kind, `retryMutation`'s rebase gate therefore
  treats it like the cascade deletes.
- **Discard mine** drops the row; the projection's value shows again.

**PS17. Projection, pull and read model.**

- `CachedPlanningSessionItems` gains `version` (integer, not null, default 1),
  `transpose` and `capo` (nullable integers): planning schema 7 → 8,
  `onUpgrade` adds the three columns.
  - Rows written before the upgrade read version 1 until the next refresh
    replaces the projection. A key edit made in that window may show one
    visible conflict; Keep mine resolves it.
- The planning `session_items` stream (ADR-041) selects `version`,
  `transpose` and `capo`.
- The merged read overlays a pending key edit's fields on the item.
  `SessionItemSummary` exposes `version`, `planTranspose` and `planCapo`.

**PS18. Sync popup.** A pending or failed key edit shows under its plan row
as the nested detail `song key changed`. The reason chips are the existing
ones. No layout change:
`docs/deferred/2026-10-12-sync-popup-narrow-layout.md` stays deferred.

**PS19. Inherited, unchanged machinery.**

- **Pending-work count:** key-edit rows are `cachedPlanningMutations` rows,
  which `countPlanningPendingWork` counts without a status filter. Sign-out
  warns about them.
- **Purge:** `deletePlanningDataForUser` deletes them. No new `PurgeTarget`
  and no ADR-035 amendment.
- **Organization switch:** they follow planning's behavior, including
  `docs/deferred/2026-10-01-org-switch-drops-pending-planning-mutations.md`,
  which S5b decides.
- **Ownership and auth edges:** the existing planning guards (I3,
  `CurrentUserOwnership`, the same-context reconcile predicate) apply.

**PS20. Error mapping.** `SupabasePlanningMutationRepository._mapError`
already covers the new messages: `session_item_version_conflict` (`P0001`,
"conflict") → `conflict`; `session_not_found`, `session_item_not_found`,
`plan_not_found` (`P0002`) → `remoteMissing` (a key edit on an item removed on
the server shows "Not found on the server, or access may have ended";
Discard drops it); `invalid_session_item_key` (`22023`) → `unknown`. The
last is unreachable from the app (PS14 refuses the value first) and stays a
defense in depth.

**PS21. Telemetry.** No new spans and no new sync path: the key edit runs
inside the existing planning mutation sync. Span and breadcrumb text stays
static (ADR-036).

### Extension points and process

**PS22. Extension points, kept in mind, not built and not deferred.** The
user may later want:

- a per-user song value (set once, shown only to that user, saved);
- a per-user plan value (shown only to that user, only in that plan).

Both would be further layers of the PS1 chain, stored on S4's per-user
personal layer, not as `session_items` columns. To keep that open:

- the resolver takes an ordered list of layers and reports each field's
  source as a layer id, so a new layer is a new entry, not a new branch in
  the reader or the projection;
- the source label and Reset/Save logic read the resolver's output, never a
  hard-coded layer pair;
- nothing in the schema or the RPC assumes the plan value is the only stored
  value.

Their order in the chain is decided when they are built.

**PS23. Deploy order.** PR 1's migration is applied to the hosted project in
the SQL editor (never `supabase db push`) right after PR 1 merges, and before
any PR 2 build is installed: PR 2's pull selects the new columns, and against
an older database every planning refresh would fail. After deploying, run the
read-only check in PR 1's plan.

**PS24. Documentation that changes with each PR.**

- PR 1: `docs/domain/domain-model.md` (session item key fields),
  ADR-038 amendment (PS13), this spec's status note.
- PR 2: ADR-028 D3 table (the tenth `record*` method),
  `docs/architecture/architecture.md` (planning mutation kinds),
  `docs/product/sync-ux-contract.md` (the `song key changed` detail).
- PR 3: ADR-042 status, the 2026-04-01 spec amendment's "implemented" note,
  `docs/product/vision.md` only if the reader's product summary changes.

## Advisor Findings P1–P8 (verified on `c713872`)

| # | finding | resolution |
|---|---|---|
| P1 | explicit grants after ADR-039 | No new table. The new RPC follows ADR-039's convention (definer, pinned path, revoke from `public, anon, authenticated`, grant `authenticated`); the columns are read through the existing table grant. The contract tests run as the real role. Hosted deploy is manual and precedes PR 2 (PS23). |
| P2 | cascades and RLS hide deletes from an incremental pull | Not applicable: planning uses full keyset pulls (ADR-041) that replace the projection, so a cascaded or now-invisible item disappears on the next refresh. A pending key edit for such an item gets `remoteMissing` (PS20). For S4: recorded in the roadmap's open design points. |
| P3 | pending-work accounting | Key-edit rows are planning mutation rows, already counted and purged (PS19). The membership-purge import gap moves to S5b. |
| P4 | writers versus purge | No new background writer: key edits go through `PlanningMutationSyncController` and its existing guards (PS19). The session-transition coordinator and the router-rebuild entry are not triggered (no new writer, no awaited dialog); both move to S4's open design points. |
| P5 | organization scope | Planning is already organization-scoped; the organization-switch finding applies to key edits exactly as to every planning mutation and is decided in S5b (PS19). |
| P6 | absolute or relative | Absolute, for transpose and capo (PS2). |
| P7 | reuse | The planning pull (ADR-041) gains three columns; ordering is OCC on the item version, no device clock (LF-T6); a resend is a no-op success (LF-T5b, PS12 step 6); conflicts are resolved with Keep mine, not last-write-wins, because the value is shared. |
| P8 | blast radius | `SongReaderState` (19 `lib/` importers per the roadmap; re-counted 2026-10-20 on `4cbdacb`: 18 `lib/` and 26 `test/` importers, the editor preview among them) loses its offsets; the 2026-04-01 spec is amended in this change; `SongReaderProjection` (hotspot with S8) takes resolved values instead of `base + offset`; the sync popup gets one detail label. |

## Deferred Entries

| entry | effect of S3 |
|---|---|
| `2026-10-11-membership-purge-import-gap.md` | moved to S5b (S3 no longer amends ADR-035) |
| `2026-10-11-session-transition-coordinator.md` | not triggered; moves to S4 |
| `2026-10-13-router-rebuild-disposes-open-dialogs.md` | not triggered (no awaited dialog) |
| `2026-10-12-sync-popup-narrow-layout.md` | not triggered (detail label only); trigger moves to S4 |
| `2026-10-01-org-switch-drops-pending-planning-mutations.md` | key edits follow S5b's rule |
| `2026-09-30-content-version-advance-on-context-switch.md` | inherited by the new kind (PS15); S5b covers it |
| `2026-09-30-session-rename-retry-never-rebases.md` | the defect must not repeat for the new kind (PS16) |
| `2026-09-28-client-abandoned-committed-write-lf-t5b.md` | mitigated for this RPC by the no-op success (PS12) |
| `2026-06-29-server-clock-anchor-lf-t6.md` | not widened (no device clock) |

## PR Boundaries

### PR 1 — backend (`feat/personal-settings-backend`)

- Migration: PS10 columns and checks, PS11/PS12 RPC, grants.
- Contract suite `scripts/tests/session-item-key-contract-test.sh`, wired into
  `scripts/backend-write-contracts.sh`, written before the migration. It
  covers K1–K15 below.
- ADR-038 amendment (PS13), `docs/domain/domain-model.md`.
- No client change. The app ignores the new columns until PR 2.

Contract tests (all calls as `authenticated` with the caller's claims):

- **K1** Function shape: `prosecdef`, `search_path=public`, executable by
  `authenticated`, not by `anon`, owned by `postgres`. The direct-table-DML
  suite stays green (it enumerates the catalog).
- **K2** Column checks reject out-of-range values written directly as
  `postgres` (`23514`); `null` is accepted.
- **K3** `set`/`set` at the current base: returns version + 1 and the values;
  the plan's `content_version` + 1; the session's `version` unchanged;
  `base_version`, `sync_status`, `last_modified_by` written.
- **K4** Three states: `keep` leaves a field, `clear` nulls it, `set` sets it,
  in every combination that matters (set/keep, keep/clear, clear/clear).
- **K5** No-op: every affected field already holds the requested value, at a
  stale base: success, the current version and values returned, item
  version, plan `content_version` and session version unchanged. Same for
  `keep`/`keep`.
- **K6** Stale base with a differing value: `session_item_version_conflict`,
  nothing changed.
- **K7** Null base: `session_item_version_conflict`.
- **K8** Invalid payload (unknown mode; `set` with null; `keep` or `clear`
  with a value; transpose ±12; capo −1 and 12): `22023`
  `invalid_session_item_key`, nothing changed.
- **K9** Authorization: a read-only member, a non-member and a foreign
  organization id get `session_not_found`; nothing changed.
- **K10** An unknown item id, an item of another session, and an attachment
  item: `session_item_not_found`.
- **K11** Existing RPCs never write the new columns: a created item has
  `null`/`null` and version 1; a reorder leaves keys and item versions
  unchanged; a rename leaves them unchanged.
- **K12** Cascade guards: a `delete_plan` with the content version from
  before a key edit gets `plan_version_conflict`; a `delete_session` with the
  session version from before a key edit succeeds (PS13).
- **K13** Lock order: a key edit that waits behind an open transaction
  holding the plan lock sees the committed result: behind a
  `delete_session_item` or a `delete_session` of its item,
  `session_item_not_found`; behind another key edit of the same item with the
  same base and a different value, `session_item_version_conflict`. (A
  matching-value resend is K5.) Key edits of two different items of one plan
  serialize on the plan row: the second waits for the first.
- **K14** Two key edits on two items of the same session, both at their own
  base, both succeed; the session version is unchanged.
- **K15** Read boundary: a member and a read-only member read `version`,
  `transpose` and `capo` through the table API; a non-member reads no row.

### PR 2 — planning client

- Projection schema 8, pull mapping, merged overlay, `SessionItemSummary`
  fields (PS17).
- `sessionItemKeyEdit`: record, fold, payload, accept, reconcile, contiguity
  rebase, Keep mine, cleanup interactions (PS14–PS16), error mapping tests
  (PS20).
- Sync popup detail label (PS18).
- Required tests, red first:
  - **C1** an accepted edit, then a second edit: the second carries the
    reconciled item version and is accepted (no self-conflict);
  - **C2** two offline edits of the same item fold into one row with the first
    base and the merged fields;
  - **C3** a resend after a commit whose response was lost returns the no-op
    success and reconciles;
  - **C4** an edit folded in while the previous send was in flight, and one
    folded onto an accepted-but-uncleared row: the earlier response rebases
    the row by the PS15 state rule, and the next send is accepted;
  - **C5** Keep mine: a conflicting key edit, then a refresh that shows a
    newer item version; the retry goes out with that version and is accepted;
  - **C6** a non-conflict retry resends the original base;
  - **C7** a local item delete drops a pending key edit; a collapsed create
    drops it; an accepted session or plan delete removes it;
  - **C8** the pending-work count includes a key-edit row, and the planning
    purge deletes it;
  - **C9** schema 7 → 8 upgrade keeps existing rows (version 1, null keys);
  - **C10** the context-switch reconcile gap is pinned as known behavior
    (one visible false conflict), referencing S5b;
  - **C11** no rebase when the response is a no-op over a foreign write
    (`R == b + 1` but a kept field differs from the sent base values): the
    folded row keeps its base and its next send is a visible conflict; its
  `plan_content_version` is discarded too, so a pending plan delete keeps its
  base (no foreign write is absorbed).

### PR 3 — reader

- The PS1 resolver and the `SongReaderState` change: the temporary layer holds
  nullable absolute values; `SongReaderProjection` takes resolved values.
- `SessionScopedReaderRuntimeController` clears the temporary layer on every
  song change and keeps the other reader state (PS5).
- Source labels, Reset, Save to plan, Clear plan value, capability gating,
  bounds (PS6, PS7, PS9); the plan detail key (PS8); placement and wiring as
  decided at the design gate (PS25, PS26).
- The editor preview renders the base only (PS7).
- Widget and golden tests for both layouts (compact and expanded), the editor
  preview unchanged, and the session navigation reset. Test IDs U1–U14 and
  the task order are in `docs/plans/2026-10-20-song-key-reader.md`.

## Non-Goals

- Per-user values (PS22; S4 builds the personal layer).
- Editing the plan key from the plan detail (display only, PS8).
- Setting the song base from the reader (PS3).
- Key names in the plan detail, a key picker, in-song modulation (S8).
- Changing the session version, any existing RPC, or the organization-switch
  behavior.
