# Delivery Roadmap: Personal Song Layer and Deferred Work

> Status: Accepted (2026-10-01). Sequencing plan only: every slice below
> still gets its own spec in `docs/specs/` and its own implementation plan in
> `docs/plans/`. Update this note, the slice table and the order whenever a
> slice merges or the order changes.
>
> **S1: merged** (PR https://github.com/BalogAbel/lyrica/pull/84, `1a9e7bb`;
> spec `docs/specs/2026-10-01-direct-table-dml-lockdown.md`, plan
> `docs/plans/2026-10-01-direct-table-dml-lockdown.md`, ADR-039).
>
> **2026-10-05: S0 inserted ahead of S5a.** It is a field-reported bug: after
> a long idle period the app waits 10–15 s offline before it shows anything.
> Spec: `docs/specs/2026-10-05-offline-first-startup-gate.md`. S0 also pulls
> S6 option (a) (persisted capabilities) forward. S0 PR 1 merged as #85
> (2026-10-06).
> Sequencing: the F6/F7 cross-user-leak fix PR (#86, `fix/cross-user-local-first-leaks`,
> `docs/specs/2026-10-06-cross-user-local-first-ownership.md`, which also
> closes three related paths and a planning data-loss case, F8; merged as
> `c222e44`), then the sign-out pending-work guard PR
> (`fix/sign-out-pending-work-guard`,
> `docs/specs/2026-10-07-sign-out-pending-work-guard.md`: every sign-out
> control warns from the signing-out user's user-wide pending count, and the
> identity clear targets only that user, closing O1), then a small fix PR
> for the different-user reauth wipe that does not recount rows a running
> import writes behind its prompt
> (found by the sign-out guard's review; closed by
> `docs/specs/2026-10-11-reauth-wipe-recount.md`), then a small import-run
> ownership fix (R17; `fix/import-run-ownership`,
> `docs/specs/2026-10-11-import-run-ownership.md`: a duplicate resolution
> commits into the catalog context the run analysed against, and a commit
> starts only while that context is still the active one; the final review of
> the reauth wipe fix reached the same write from the other direction), then
> S0 PR 2, then S5a.
> The sign-out guard PR merged as #87 (`d5fd3de`, 2026-10-09). The reauth
> wipe fix merged as #88 (`22864df`, 2026-10-11), ADR-029 amended
> (`docs/specs/2026-10-11-reauth-wipe-recount.md`); next is the import-run
> ownership fix, then S0 PR 2. The import-run ownership fix merged as #89
> (`02a9aa2`). S0 PR 2 merged as #90 (`4dbd9de`, 2026-10-12); S0 complete
> (PR 1 and PR 2). S5a merged as #91 (`0390d79`, 2026-10-12; ADR-041,
> `docs/specs/2026-10-12-paged-remote-pulls.md`). S2 merged as #92
> (`c561d20`, 2026-10-12;
> `docs/specs/2026-10-12-chordpro-base-directives.md`). S6a merged as #93
> (`c713872`, 2026-10-13;
> `docs/specs/2026-10-12-sync-and-account-feedback.md`); S3 in progress.
> **2026-10-13: the S3 brainstorm changed S3's scope.** S3 no longer builds a
> per-user personal layer: it adds a shared plan-level transpose and capo on
> the session item and a temporary reader layer
> (`docs/specs/2026-10-13-personal-song-settings.md`, ADR-042; see "S3 Scope
> Change (2026-10-13)"). S4 builds the per-user personal layer itself. New
> order: S3, then S5b, then S4.
> S3 PR 1 (backend) merged as #94 (`603d69b`, 2026-10-14); its migration
> `202610130001` is deployed to the hosted project. S3 PR 2 (planning client)
> merged as #95 (`4cbdacb`); S3 PR 3 (reader) merged as #96 (`d73e907`,
> 2026-10-21). S3 complete (PRs 1–3). S5b in progress on
> `fix/planning-mutation-gaps` (2026-10-21), including the key-edit residuals
> R1 and R3 (`docs/deferred/2026-10-14-key-edit-residuals.md`). The open
> deferred entries were triaged on
> 2026-10-12 (see "Deferred Triage (2026-10-12)"): S6 is split into S6a and
> S6b, and S6a runs right after S2. The
> session-transition coordinator it surfaced stays deferred
> (`docs/deferred/2026-10-11-session-transition-coordinator.md`); the
> membership-revocation purge has the same import gap RW3 closes here
> (`docs/deferred/2026-10-11-membership-purge-import-gap.md`).

## Purpose

On 2026-10-01 the user asked for three things:

1. **Annotations.** A user can write on a song, circle parts of it, and so on.
   An annotation is stored either at song level (shown wherever the song is
   read) or at plan level (shown only when the song is read inside that
   plan). Annotations belong to one user and are never shared with other
   users.
2. **Saved transpose and capo.** Per user, at plan level, and optionally at
   song level. The user expects this to share the abstraction that
   annotations need. **Revised by the user on 2026-10-13 (S3 brainstorm):** a
   shared plan-level value that everyone reading the plan sees, the song's
   existing shared base, and a temporary reader-only value. Per-user values
   stay a future extension of the same resolution chain.
3. **The work recorded in `docs/deferred/`.**

This document fixes the order of that work, the dependencies between the
pieces, their relative complexity, and the recommended defaults for decisions
that are already understood. It is written so that any session or agent can
pick up the next slice without re-deriving this analysis. It contains no
implementation.

## Inputs

- **Codebase analysis.** graphify reverse-import analysis on the graph built
  from `d3c00b0`, targeted code reading, and `flutter pub outdated`. The
  graph holds import and definition edges but not method calls, so call-level
  facts were checked in the source.
- **Library behavior.** Supabase documentation via Context7 (default
  privileges, session lifetime).
- **User decisions (2026-10-01):**
  - This order and the recommended defaults below go into the repository.
  - Trigger-gated deferred items are re-evaluated, not overridden.
  - No organization is close to 1000 songs.
  - Web stays a best-effort target for offline use and for annotations.
  - Sentry runs in production. The org-id telemetry leak is judged low risk
    and stays in S6 (S6b since the 2026-10-12 split).

## Current State That Shapes the Work

- **Transpose and capo exist only as runtime state.** They live in
  `SongReaderState.transposeOffset` and `capoOffset`. In plan-session mode
  `SessionScopedReaderRuntimeController` keeps one reader state per session,
  so a transpose deliberately carries over to the next song. That behavior
  comes from "Reader-Local State Preservation" in
  `docs/specs/2026-04-01-session-scoped-plan-reader-navigation.md`.
  (State on 2026-10-01. S3 PR 3 replaced the offsets with the temporary,
  plan and song layers on 2026-10-21; see ADR-042.)
- **Zoom is the only persisted reader preference.** It is stored in
  `shared_preferences` under `reader_zoom:{userId}:{songId}` (ADR
  `2026-06-06-reader-zoom-local-persistence.md`). It is device-local, not
  synced, and not purged on sign-out.
- **`SongReaderState` has a wide blast radius.** 19 `lib/` files import it,
  including the song editor preview. Changing its shape affects the editor.
- **Nothing to build on for annotations.** The codebase has no annotation
  concept; the graph vocabulary has no ink, stroke or annotation terms.
- **The reader reflows in many ways.** Layout changes with:
  - viewport width and orientation;
  - zoom and auto-fit;
  - one or two columns;
  - chords and lyrics vs. lyrics only;
  - guitar vs. piano view;
  - transpose and capo, which change chord label widths;
  - the OS text scaler.

  Pixel-anchored ink would drift under every one of these. Annotations must
  anchor to song content (word, chord, line, section). They must render as
  overlays that take no layout space, which also leaves the fit estimator's
  upper-bound contract untouched
  (`docs/deferred/2026-07-28-reader-fit-conservatism-margin.md`).
- **Personal data must be server-synced.** Explicit sign-out purges local
  data, and ADR-035 treats the server as the durable store once synced.
  Annotations and saved settings stored only on the device would be lost on
  sign-out and on device change.
- **Base directives are read inconsistently.** The editor and the reader read
  the base `{transpose}` and `{capo}` differently
  (`docs/deferred/2026-04-22-song-reader-chordpro-modulation.md`). Saved
  personal transpose and capo need one consistent base, so this is fixed first.

## New Findings

Found during this analysis. Each one is recorded in `docs/deferred/`.

1. **The song catalog pull is unpaged too.** `listSongsRows` in
   `supabase_song_repository.dart` has no `.range()` and orders by title.
   Above PostgREST's `max_rows = 1000`, songs late in the alphabet silently
   drop out of the list and the offline catalog. This is far more plausible
   than 1000 sessions in one plan. A failed refresh is not an acceptable
   fail-safe for the catalog, because a large library would never refresh
   again, so the catalog must page.
   → `docs/deferred/2026-09-30-planning-pull-unpaged-reads.md` (resolved by S5a,
   removed)
2. **`memberships` also has a `for all` write policy.** The policy is
   "memberships are manageable by capability"
   (`202603210001_initial_schema.sql`). Through direct DML, a role change
   bypasses the invitation and audit contracts.
   → resolved by S1, `docs/specs/2026-10-01-direct-table-dml-lockdown.md`
3. **Supabase grants DML on every new `public` table to `authenticated` by
   default.** These are default privileges. If S1 only revokes the grants on
   existing tables, the personal-layer tables added in S3 would reopen the
   bypass. S1 therefore also revokes default privileges, and the hosted
   project turns off "Default privileges for new entities".
   → resolved by S1, `docs/specs/2026-10-01-direct-table-dml-lockdown.md`
4. **An organization switch drops pending planning mutations.** The active
   organization is the smallest organization id
   (`active_organization_resolution.dart`). When a multi-organization user
   joins an organization whose id sorts first, the context switches. The
   `!sameBoundary` branch of `PlanningSyncController.handleActiveContextChanged`
   then deletes the previous organization's planning data, including its
   pending mutations. This happens outside the ADR-035 `PurgeReason` gate,
   while the old membership is still intact. The song side keeps the old
   organization's pending mutations. Found by code reading, not reproduced.
   → `docs/deferred/2026-10-01-org-switch-drops-pending-planning-mutations.md`
5. **Supabase refresh tokens never expire by default.** The LF-T2 "wall"
   exists only if the hosted project enables a session time-box, an
   inactivity timeout, or single session per user. Single session per user
   would also break multi-device use of the personal layer. The user verified
   on 2026-10-01 that all three are off ("never"); they cannot be changed on
   the Free plan. LF-T2 is closed.
   → `docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md`
6. **`sentry_flutter` 9.x still does not resolve.** `flutter pub outdated`
   on 2026-10-01 reports resolvable 8.14.2, latest 9.30.1.
   → `docs/deferred/2026-08-28-observability-remaining-use-cases.md`

## Slices

Size legend:

- **S:** one small PR, mostly one layer.
- **M:** one PR that crosses layers or includes backend contract work.
- **L:** several PRs, or a new subsystem.
- **XL:** a multi-phase effort that starts with a prototype.

| ID | Branch | Scope | Deferred sources | Size | Risk |
|---|---|---|---|---|---|
| S1 | `fix/direct-dml-write-rpc-bypass` | **Merged (PR #84).** Revoke every table privilege except `SELECT` from `anon`/`authenticated` on all ten `public` tables. Drop the six `for all` policies (each is covered by a select policy, so dropping replaces the planned narrowing). Revoke `postgres`'s default privileges in `public` from `anon`, `authenticated` and `service_role`. Contract suites impersonate the real role; fixtures moved to `postgres`. ADR-039, plus correction notes in `architecture.md`, ADR-026, ADR-027 and ADR-038 | `2026-09-30-direct-dml-bypasses-write-rpcs.md` (resolved, removed) | M | medium |
| S0 | `fix/offline-first-startup-gate` | **Merged (PRs #85, #90).** Field-reported bug, 2 PRs. (1) The membership gate decides from the last known identity; `verifiedEmpty` closes it only after the D5 purge; first run shows a loading state; auth-stream errors are handled; an integration test uses the real gotrue client. (2) Persist the last known capabilities (S6 option (a), pulled forward) and show a visible "last synced" indicator | `2026-09-30-capability-gating-offline-cold-start.md` (option (a) only; entry removed in S6a) | M | medium |
| S5a | `fix/paged-remote-pulls` | **Merged (PR #91, `0390d79`).** A shared keyset paging helper (`order(id).gt(id, last).limit(n)`, ends only on an empty page, strictly increasing keys checked), not `.range()` plus `count=exact`: offset pages can skip a row that a count check does not catch. The catalog reads summaries and sources in one organization-scoped stream (no per-song requests); planning reads plans, sessions and session items as three organization-wide streams (embedded items were truncated too). ADR-041; spec `docs/specs/2026-10-12-paged-remote-pulls.md` | `2026-09-30-planning-pull-unpaged-reads.md` (resolved, removed) | S–M | low–medium |
| S2 | `fix/chordpro-base-directives` | **Merged (PR #92, `c561d20`).** One base-region predicate shared by the parser, the editor read and the editor write: base `{transpose}`, `{capo}` and `{key}` are read before the first lyric or chord line (or the first tab content line). Comments and section markers no longer close it. The editor uses the parser-derived base values, and its write never touches in-song directives. Spec: `docs/specs/2026-10-12-chordpro-base-directives.md` | `2026-04-22-song-reader-chordpro-modulation.md`, item 1 | S | low |
| S3 | `feat/personal-settings-backend`, then one branch per PR | **Merged (#94 `603d69b`, #95 `4cbdacb`, #96 `d73e907`; complete 2026-10-21; PR 3 plan `docs/plans/2026-10-20-song-key-reader.md`).** **Scope changed 2026-10-13.** Song key layers: a temporary reader layer (never stored) over a shared plan-level transpose and capo on the session item, over the song's ChordPro base (edited only in the song editor). 3 PRs: (1) `session_items.transpose`/`capo`, the `set_session_item_key` RPC and real-role contract tests; (2) planning client: projection columns, pull mapping, the `sessionItemKeyEdit` mutation with Keep mine, a sync popup detail label; (3) reader: layered resolution, end of the session carry-over, Save to plan / Reset / Clear plan value, plan-detail key. No new sync domain, table or `PurgeTarget`. Spec `docs/specs/2026-10-13-personal-song-settings.md`, ADR-042 | added: `2026-10-21-song-key-reader-residuals.md` (PR 3 review residuals, revisit at their triggers); the membership-purge import gap moved to S5b | M–L | medium |
| S4 | `feat/song-annotations` | Annotations on a per-user personal layer, which S4 now builds itself (see "S4" under "Recommended Defaults"). Starts with a prototype in `docs/prototypes/`, then 2–3 PRs: (1) the personal layer (server-synced, single owner) with the anchor model, overlay renderer and typed notes; (2) gesture marks (circle, underline, highlight) snapped to content; (3) free ink anchored to words, if the spec keeps it. Native (tablet and phone) first; web is best-effort | — (new) | XL | high |
| S5b | `fix/planning-mutation-gaps` | **In progress (2026-10-21).** Spec `docs/specs/2026-10-21-planning-mutation-gaps.md` (MG1–MG14; 3 PRs: (1) context and run boundaries, (2) rows that never resolve, (3) purge and pull guards). Stranded create tombstones, session-rename retry rebase, content-version advance on context switch. Verify and decide the organization-switch finding. Added 2026-10-12: stop a mutation sync run when the context changes, in both the planning and the song controller (gate-cross-user-leaks O2); an ownership guard on the D5 purge resets (O3); childless plans after a mid-pull revocation, fixed with a membership re-check after the child streams (paged-pull-residuals R2). Added 2026-10-13: the membership-purge import gap (from S3; it amends ADR-035, use `isRunningFor(userId)`). Added 2026-10-20 (S3 PR 2 review residuals): discarding a failed session-item create also removes its dependent key-edit and order rows (key-edit-residuals R1), and a refresh requested after a write never coalesces onto a run that started before that write (R3, every versioned kind). Every fix also covers S3's `sessionItemKeyEdit` | `2026-09-30-stranded-create-tombstones.md`, `2026-09-30-session-rename-retry-never-rebases.md`, `2026-09-30-content-version-advance-on-context-switch.md`, `2026-10-01-org-switch-drops-pending-planning-mutations.md`, `2026-10-05-gate-cross-user-leaks.md` (O2, O3), `2026-10-12-paged-pull-residuals.md` (R2), `2026-10-11-membership-purge-import-gap.md`, `2026-10-14-key-edit-residuals.md` (R1, R3) | M–L | high |
| S7 | `feat/plan-duplicate`, then `feat/session-item-move` | Each is one server RPC; v1 is online-only, recorded in an ADR | `2026-09-29-plan-duplicate.md`, `2026-09-29-session-item-move.md` | 2×M (offline-capable: 2×L) | medium |
| S6a | `fix/sync-and-account-feedback` | **Implemented (PR pending).** Copy and feedback only. The sync popup's reason chips are phrases; one generic remote-missing phrase covers a delete the backend rejects (`plan_not_found` means both "removed" and "no longer allowed"), and `authorizationDenied` says access may have ended. A refused, failed or superseded sign-out shows one snackbar (new outcome `blockedByImport`; a throwing confirmation is `failed`), and a failed Delete account is caught and shown. A sign-out confirmation dialog lost to a router rebuild ends `failed` instead of holding the command lock (FB16; the rebuild itself is deferred). Nine dead strings removed; the two deletion-confirmation dialogs are English, with a guard test on `AppStrings`. Spec: `docs/specs/2026-10-12-sync-and-account-feedback.md` | resolved and removed: `2026-09-30-capability-gating-offline-cold-start.md`, `2026-10-12-sync-reason-chip-copy.md`; updated: `2026-10-05-membership-revoked-notice.md` (option b done), `2026-10-09-sign-out-guard-residuals.md` (R8, R15 closed); added: `2026-10-12-sync-popup-narrow-layout.md`, `2026-10-12-delete-account-session-loss-purge.md`, `2026-10-13-router-rebuild-disposes-open-dialogs.md` | S–M | low |
| S6b | `fix/capability-and-telemetry` | Fix the org-id telemetry leak and add the `sessionExpired` test. Centralize PII scrubbing in `beforeSend`, `beforeSendTransaction` and `beforeBreadcrumb`. Capability persistence residuals F3, F4 and the test-strength gaps. A throwing observability adapter leaves a refresh "refreshing" (paged-pull-residuals R3) | `2026-08-28-observability-remaining-use-cases.md`, `2026-10-12-capability-persist-residuals.md`, `2026-10-12-paged-pull-residuals.md` (R3) | M | low–medium |
| S8 | `feat/chordpro-modulation` | In-song `{transpose}` modulation | `2026-04-22-song-reader-chordpro-modulation.md`, item 2 | M | medium |
| S9 | — | The trigger-gated items, re-evaluated below | see "S9 Re-Evaluation" | varies | — |

### What drives the complexity

- **S1:**
  - Six tables, `memberships` being the most sensitive.
  - Default privileges.
  - Every fixture path that writes as `authenticated`.
  - The red contract test comes first: it impersonates a capable member and
    expects each direct `insert`, `update` and `delete` to be denied.
- **S0:**
  - The gate, the router redirect, and the D5 purge gate meet in one
    decision. A wrong row in the decision table either hides data or skips
    onboarding.
  - Capabilities live and die with the identity record. Writing them must not
    resurrect a set after a purge.
- **S5a:**
  - The catalog refresh path is sensitive: ADR-037 local-first visibility and
    the rejected-empty-snapshot guard.
  - Paging has to keep both guarantees.
- **S2:**
  - Small, but visible. Songs that put a `{comment}` before their base
    directives start showing the transposed key, as ChordPro semantics
    require.
- **S3 (since 2026-10-13):**
  - One new planning mutation kind in the existing outbox, with its own OCC
    (the session item's `version`) so that key edits never conflict with each
    other or with the session's structural writes.
  - Keep mine must rebase from the session item, not repeat the S5b rename
    defect.
  - `SongReaderState` loses the offsets that carried over between songs; the
    editor preview imports it too.
- **S4:**
  - The per-user personal layer, moved here from S3: a new, third sync
    domain (backend, Drift store, outbox, pull, lifecycle and purge, storage
    budget, sync overview). The data has a single owner, so last-write-wins is
    enough and no conflict UI is needed.
  - Word-box geometry from the `Wrap`-based line layout, in one and two
    columns.
  - Gesture arbitration between scrolling, pinch-zoom, double-tap fit, tap to
    toggle controls, and drawing.
  - Re-anchoring after another member edits the song.
  - A golden-test matrix across the reflow factors listed above.
- **S5b:**
  - Invariants I3 and I7, and the D7 contiguity rule.
  - Each of the four review gates of the plan-delete slice found defects in
    planning sync code. Gate 3 found a critical one, and gate 4 found two
    major ones.
- **S7:**
  - Offline-capable versions need overlay synthesis (duplicate) and a
    two-aggregate mutation row (move).
  - Online-only v1 removes both.
- **S6a:**
  - Copy and feedback only; no new guard, store or state machine. R8 and R15
    are feedback fixes, not session-transition guards.
- **S6b:**
  - Moving the scrub tests to hook level. (The per-user capability store
    moved to S0.)
- **S8:**
  - Per-line effective transpose in the projection, and the UI that shows
    where it changes.
  - Directive lines the fit estimator has to account for.

## Dependencies

**Hard (merge before the dependent slice starts its code):**

- **S1 → S3.** The new RPC is written under the hardened grant model
  (merged).
- **S1 → S4.** Without revoked default privileges, the new personal-layer
  tables get DML grants for `authenticated` (merged).
- **S2 → S3.** Plan-level transpose and capo resolve over one consistent base.
- **S2 → S8.** Modulation builds on the same parser semantics.
- **S5b → S7.** Duplicate and move re-enter the same mutation machinery. The
  `docs/deferred/README.md` planning rule makes the open gaps there priority
  work first.
- **S3 → S5b.** Not a code dependency: S3 re-enters the planning mutation
  state machine, so the planning rule makes S5b the very next slice. Every S5b
  fix also covers `sessionItemKeyEdit`.

The former **S3 → S4** dependency is gone (2026-10-13): S3 no longer builds a
personal layer, so S4 builds it.

**Soft (preferred order, not blocking):**

- **S5a → S4.** The personal-layer pull reuses the paging helper (ADR-041).
- **S1 → S7.** The new RPCs are written under the hardened grant model.
- **S3 → S7.** Duplicating a plan copies the session items' plan keys, and a
  session-item move keeps its key.

**Hotspots (never run in parallel):**

- **S4 ↔ S0 (PR 2):** `LocalDataLifecycle.clearIdentity` and the
  `LastKnownIdentity` database. S0 adds no new `PurgeTarget`: its capability
  store is cleared together with the identity.
- **S3/S4 ↔ S8:** `SongReaderProjection`.
- **S5b ↔ S7:** `drift_planning_mutation_store.dart` and
  `planning_mutation_sync_controller.dart`.
- **S5b ↔ S3 (PR 2):** the same two files; S3 PR 2 adds the
  `sessionItemKeyEdit` kind to them. S5b also touches the D5 purge (O3) and
  the mutation sync controllers (O2).
- **S6a ↔ S4:** the unified sync popup. S6a went first; the personal layer
  extends the popup S6a reworded. (S3 PR 2 adds only a detail label.)

**Deliberate decoupling:** annotations are overlays that take no layout space.
S4 therefore stays independent of the fit estimator and of the fit-margin
deferred item.

## Order

For a single executor:

1. **S1:** DML bypass, `memberships`, default privileges. Merged.
2. **S0:** offline-first startup gate, then persisted capabilities and the
   "last synced" indicator. A field-reported bug, so it goes first.
3. **S5a:** paged pulls, including the song catalog. Small and independent,
   and S3 reuses its helper. Not urgent: no organization is near 1000 songs.
4. **S2:** base directives.
5. **S6a:** sync and account feedback. It fixes two user-reachable gaps (an
   unhandled failed Delete account, R15, and code-shaped sync reason chips),
   and S3 PR 2 extends the same sync popup.
6. **S3:** song key layers (temporary and shared plan-level transpose and
   capo), in 3 PRs. Merged (#94, #95, #96).
7. **S5b:** planning mutation gaps, plus O2, O3, paged-pull R2, the
   membership-purge import gap and key-edit residuals R1 and R3. Right after
   S3, because S3 re-enters the planning mutation state machine (2026-10-13).
   In progress.
8. **S4:** the per-user personal layer and annotations, as a prototype
   followed by 2–3 PRs.
9. **S7:** plan duplicate, then session-item move.
10. **S6b:** capability residuals and telemetry (S6's old position).
11. **S8:** ChordPro modulation.
12. **S9 remainder:** re-check each trigger before deciding.

Short form: S1, S0, S5a, S2, S6a, S3, S5b, S4, S7, S6b, S8, S9.

**User actions:** the S1 hosted actions and the LF-T2 dashboard check are done
(2026-10-01; see "User Actions Outside the Repository").

**With several executors:**

- **Two tracks can run in parallel:**
  - Track A (reader and personal layer): S2 → S3 → S4 → S8.
  - Track B (backend, planning and feedback): S1 → S0 → S5a → S6a → S5b →
    S7 → S6b.
- **Constraints:**
  - S3's backend migration waits for S1 to merge.
  - S5b starts only after S3 PR 2 merges (the mutation store and sync
    controller hotspot), and S4 waits for S5b in the single-executor order.
  - S0's PR 2 never runs at the same time as S4's personal-layer PR.
  - The hotspots above stay serialized.

## Recommended Defaults

Accepted for this roadmap on 2026-10-01. Each slice spec confirms a default
or overrides it with a stated reason.

### S5b

Decided on 2026-10-21 in `docs/specs/2026-10-21-planning-mutation-gaps.md`
("Roadmap Defaults: Confirmed or Overridden"): the organization switch keeps
the previous organization's data (MG1); the session-item tombstone base is
`b + 1`, not 1 (MG6); the conflict-only retry rebase covers `planEdit` and
both reorders too (MG8); rule 1a moves to batch end (MG4). The rest is
confirmed as written below.

- **Stranded tombstones: option (a).**
  - At run start, convert each stale `cancelling` row into a pending delete
    with creation-time base `(1, 1)`.
  - Mark the converted row as tombstone-origin, so that a `*_not_found`
    response closes the row automatically.
  - Option (b) needs idempotent create RPCs, a backend change that would also
    pull in LF-T5b.
  - For session items, accept the visible conflict noise that a base of 1
    causes. Reaching it takes an app kill during an in-flight create followed
    by a delete.
- **Session-rename retry: rebase only after a visible conflict.** Plan-delete
  gate 3 (F1) showed that a retry which rebases in any status silently
  absorbs a foreign write.
- **Content-version advance: option (a).** Gate rule 1a with the same
  same-context predicate as `shouldReconcileAcceptedMutation`. A lagging
  projection costs at most one visible false conflict. Option (b) would create
  more stranded `accepted` rows.
- **Organization-switch finding:** first verify it with a test, then choose
  between keeping the pending mutations until they sync or are discarded, and
  routing the drop through an explicit, audited purge reason.

### S6a and S6b (S6 split on 2026-10-12)

- Option (a), persisted capabilities, moved to S0 on 2026-10-05
  (`docs/specs/2026-10-05-offline-first-startup-gate.md`, SG6).
- S6a: use generic copy for a delete the backend rejects (option b), and
  membership-revoked-notice option (b) in the same copy pass.
- S6b: add the centralized scrub hooks in the same slice: S6b is the next
  slice that touches observability, which meets that item's trigger.

### S7

- Both features are server RPCs, online-only in v1, recorded in an ADR. While
  pending local mutations touch the affected plan or sessions, the action is
  disabled.
- Duplicating a plan copies each session item's plan key (`transpose`,
  `capo`), and a session-item move keeps the item's key (S3, 2026-10-13).
- Duplicating a plan also copies the caller's own plan-scoped personal layer
  (annotations, once S4 exists). It never copies another user's.

### S3 (finalized 2026-10-13)

The preliminary defaults written here on 2026-10-01 were replaced by the S3
brainstorm. Spec: `docs/specs/2026-10-13-personal-song-settings.md` (PS1–PS24),
ADR-042. In short:

- **Three layers, per field:** temporary (reader only, never stored, cleared
  on every song change), then the plan's value on the session item (shared;
  only when the song is opened from that plan), then the song's ChordPro base
  (shared; edited only in the song editor). Values are absolute, relative to
  the written chords. Both plan fields are nullable.
- **The reader's ± is always temporary.** Inside a plan, a member with
  `canEditSessions` gets **Save to plan**, **Reset** and **Clear plan value**;
  everyone else gets temporary changes only.
- **Item scope:** the same song in two sessions has two values; removing a
  song and adding it again loses its key; a reorder keeps it.
- **Writes:** `set_session_item_key`, with keep / set / clear per field and
  OCC on `session_items.version`. A resend whose values already match is a
  no-op success (the LF-T5b lesson, for this RPC). Plans' `content_version` is
  bumped; the session `version` is not.
- **Sync:** the existing planning outbox, pull, purge, pending count and
  organization-switch behavior; one new mutation kind with Keep mine.
- **The session-wide transpose and capo carry-over ends** (amends the
  2026-04-01 spec). View mode, instrument and zoom keep their current behavior.
- **Extension points, not deferred work:** a per-user song value and a
  per-user plan value would be further layers in the same ordered resolution
  chain (ADR-042). Nothing is built for them now.

### S4 (open questions for its brainstorming session)

S4 now builds the per-user personal layer that S3 was going to build. Its
starting defaults are the old S3 preliminary ones (2026-10-01), unchanged:

- **Storage:** server-synced personal layer, single owner, last-write-wins.
- **Ordering:** a server-assigned sequence orders writes and serves as the
  pull cursor, never a device clock. This applies the LF-T6 lesson.
- **Writes:** idempotent upserts keyed by a client-generated UUID, and
  delete-wins tombstones. Applying the LF-T5b lesson, a resend of a write the
  server already applied is a no-op, not a conflict.
- **Write path:** RPC-only, consistent with S1. RLS reads are owner-only and
  also require that the caller can still read the song.
- **Who can use it:** read-only members too; personal data needs no editing
  capability.
- **Organization switch:** the outbox is not deleted (see finding 4). Only an
  authoritative revocation or an explicit purge reason drops it.
- **Purge contract:**
  - The layer integrates with ADR-035: a new `PurgeTarget`, and the
    pending-local-work count.
  - Unsynced personal changes are part of what sign-out warns about.
- **Telemetry:** spans follow the ADR-036 pattern. No personal content goes
  to telemetry.

**Open design points for S4 (from the 2026-10-13 S3 prompt).** Verified
read-only on `c713872` for S3, which no longer needs them:

- **Explicit grants (ADR-039).** New personal-layer tables get no grants:
  the migration grants `SELECT` explicitly, every write goes through a
  `security definer` RPC, the contract tests impersonate the real role, and
  the hosted deploy is manual (SQL editor) and precedes any client that needs
  it.
- **Deletes the incremental pull never sees.** A server cascade (plan or song
  deletion) removes rows physically, and losing access (RLS) hides them the
  same way, so a cursor pull never learns of them. Decide between tombstones
  in the same sequence stream, client-side garbage collection against the
  local catalog and planning projection, or a periodic full reconcile.
- **Pending-work accounting.** Unsynced personal changes must be counted in
  `pendingLocalWorkCounterProvider` (the sign-out warning, the different-user
  reauth wipe, the membership-revocation purge), with its own `PurgeTarget`
  and an ADR-035 amendment.
- **Writers versus purge.** A pull page or an outbox acknowledgement that
  lands after a purge must not resurrect the purged data (the S0
  capability-store lesson). The personal-layer writer is "a new background
  writer", the trigger of
  `docs/deferred/2026-10-11-session-transition-coordinator.md`: decide between
  a local guard and writing the coordinator spec first, and re-check the open
  reauth-host risk of `docs/deferred/2026-10-13-router-rebuild-disposes-open-dialogs.md`.
- **Organization scope.** Carry `organization_id` on each row, pull per
  active `(user, org)` and purge per `(user, org)` like the other targets; an
  organization switch never drops the outbox.

**Annotation questions:**

- **Input modes:**
  - typed notes;
  - gesture marks snapped to content (circle, underline, highlight);
  - free handwriting or drawing anchored to words.
- **Gestures:** an explicit annotation mode, or stylus-only drawing.
- **Anchor model:**
  - A text-quote selector (exact text, prefix, suffix) plus a position hint.
  - Chord anchors use the segment position, not the chord text, so they
    survive transposition.
  - A list of orphaned annotations when re-anchoring fails after an edit.
- **Layers:** the default layer per context (plan scope inside a plan, song
  scope in the library), a visibility toggle, and a visual distinction.
- **Lyrics-only mode:** chord-anchored annotations are hidden.
- **Storage:** stroke simplification and quantization keep ink small, and the
  storage budget accounts for it.
- **Telemetry:** annotation text never goes to telemetry.

## S9 Re-Evaluation

| Item | Trigger status on 2026-10-01 | Decision |
|---|---|---|
| LF-T2, refresh-token TTL | Depends only on hosted Supabase Auth settings; verified 2026-10-01: single session off, time-box and inactivity timeout both "never" (not changeable on the Free plan) | **Closed.** Reopen only if a paid plan enables any of these settings |
| `sentry_flutter` 9.x | Not resolvable (8.14.2) | Stays deferred |
| Centralized scrub hooks | Met once S6b starts (next observability slice) | Moves into S6b (was S6) |
| Remaining instrumentation | "Non-trigger" rule still applies | Only new S4 sync code gets spans, per ADR-036 (S3 adds no sync path of its own since 2026-10-13); nothing else is back-filled |
| Web `traceparent` gate | Still tied to the CORS gate | Stays deferred |
| Web offline e2e | Not met: web stays best-effort (user, 2026-10-01) | Stays deferred; S4 is native-first |
| Reader fit margin | No trigger | Stays deferred; S4's overlay-only rule keeps it decoupled |
| LF-T5, OCC divergence | No evidence, and nothing measures it | Stays deferred. Cheap enabler: a breadcrumb or metric when the mutation warn threshold fires (S5b or S6b) |
| LF-T5b, abandoned committed write | No evidence | Stays deferred. Corrected 2026-10-13: S3's key edit is an OCC write with this shape; its RPC answers a resend whose values already match with a no-op success, so it adds no new exposure. S4's personal layer is idempotent by design |
| LF-T6, server clock anchor | No trusted server time in planning | Stays deferred. Corrected 2026-10-13: S3 uses planning OCC and no device clock; S4's personal layer orders by server sequence |

## Deferred Triage (2026-10-12)

Advisor decisions of 2026-10-12, made after S5a merged. They cover the
entries that S0, the cross-user, sign-out, reauth and import-run fixes, and
S5a left open. Each affected deferred document carries a one-line
"Roadmap (2026-10-12)" note.

**S5b gains:**

- `2026-10-05-gate-cross-user-leaks.md` **O2:** stop a mutation sync run
  when the context changes, in both the planning and the song controller.
- `2026-10-05-gate-cross-user-leaks.md` **O3:** an ownership guard on the D5
  purge resets.
- `2026-10-12-paged-pull-residuals.md` **R2:** fix it with a membership
  re-check after the child streams. **Not** with the "`content_version > 1`
  and no sessions" rejection: a plan whose sessions were all deleted
  legitimately has that shape.

**S6 is split in two:**

- **S6a** `fix/sync-and-account-feedback` (S–M, copy and feedback only):
  - the rejected-delete copy (the old S6 option b,
    `2026-09-30-capability-gating-offline-cold-start.md`, removed in S6a);
  - `2026-10-12-sync-reason-chip-copy.md` (removed in S6a);
  - `2026-10-05-membership-revoked-notice.md` option (b);
  - `2026-10-09-sign-out-guard-residuals.md` R8 (no feedback for a refused
    sign-out) and R15 (a failed Delete account is unhandled).
  - **Update (S6a implemented):** all four are resolved as above. S6a added
    two trigger-gated entries (S9):
    `2026-10-12-sync-popup-narrow-layout.md` (S3 PR 2 was to extend the popup
    and pick it up; since 2026-10-13 that is S4's personal layer) and
    `2026-10-12-delete-account-session-loss-purge.md`.
- **S6b** `fix/capability-and-telemetry`:
  - the org-id telemetry leak, the `sessionExpired` test and the centralized
    scrub hooks (`2026-08-28-observability-remaining-use-cases.md`);
  - `2026-10-12-capability-persist-residuals.md` F3, F4 and the
    test-strength gaps;
  - `2026-10-12-paged-pull-residuals.md` R3.

**Order:** S6a runs right after S2 and before S3. It fixes two user-reachable
gaps (R15 and the code-shaped chips), and S3 PR 2 extends the same sync popup.
S6b keeps S6's old position. New order: S1, S0, S5a, S2, S6a, S3, S4, S5b,
S7, S6b, S8, S9. (Superseded 2026-10-13: S5b moves before S4; see "Order".)

**S3 PR 2 gains** `2026-10-11-membership-purge-import-gap.md`: it amends
ADR-035 anyway; use `isRunningFor(userId)`. The S3 brainstorm must also
decide how S3's pull and outbox writer behave around a purge (no
resurrection after a purge), and re-evaluate the session-transition
coordinator at that point, before adding another local guard.

**Update (2026-10-13, S3 brainstorm).** S3 no longer adds a pull, an outbox
writer, a purge target or an ADR-035 amendment. Consequences:

- The membership-purge import gap moves to **S5b** (O3 already touches the D5
  purge).
- The session-transition coordinator is not triggered by S3 (no new
  background writer, no new purge). The question moves to S4's personal
  layer (see "Open design points for S4").
- `2026-10-13-router-rebuild-disposes-open-dialogs.md` is not triggered: S3
  awaits no dialog.
- `2026-10-12-sync-popup-narrow-layout.md` is not triggered: S3 PR 2 adds a
  detail label only, not a new popup section. It stays S9 until the personal
  layer (S4) extends the popup.

**R8 and R15 are feedback fixes, not transition guards.** Closing them in
S6a did not trigger the session-transition coordinator
(`2026-10-11-session-transition-coordinator.md` records this).

**Stay trigger-gated (S9):**

- gate residuals C4, F5, N1, N2 (`2026-10-05-gate-cross-user-leaks.md`);
- the remaining sign-out residuals R1–R7, R9–R14, R18–R20, and the
  session-transition coordinator;
- `2026-10-05-offline-token-refresh-churn.md`;
- paged-pull residuals R1 and R4;
- membership-revoked-notice option (a).

## Execution Protocol

Per slice:

1. **Start a fresh session** from this document and the slice's deferred
   documents.
2. **Write the spec** in `docs/specs/`. It confirms or overrides the defaults
   above.
3. **Write the plan** in `docs/plans/`, with STOP-and-report conditions for
   anything that would require re-planning.
4. **Pass a design gate before any code.** Prescribe the hard part instead of
   letting it be improvised task by task.
5. **TDD:** a red test first for every behavior change. Every task is
   verified with the full suite.
6. **Run one adversarial whole-diff review per phase.** Ask it a specific
   negative claim to disprove.
7. **Open a PR, get green CI, merge.** Deploy backend migrations before
   client builds.
8. **Refresh the graph** after merge whenever file or module structure
   changed.
9. **Update the documents in the same change.** The deferred documents follow
   the tracking rule in `docs/deferred/README.md`; this roadmap's status note
   and slice table change with every merge or reordering.

S3 and S4 each start with a dedicated brainstorming session, because they
hold the largest open design space. Following the reader's prototype-first
practice, S4 starts with a prototype in `docs/prototypes/`.

## User Actions Outside the Repository

- **LF-T2 (done 2026-10-01):** the hosted session settings were checked and
  recorded in `docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md`. Keep
  them at "never" if the project ever moves to a paid plan.
- **S1 (done 2026-10-01):**
  - In the Data API settings, "Automatically expose new tables" (formerly
    "Default privileges for new entities") is off.
  - Migration `202610010001` was applied by hand in the SQL editor.
  - The D8 post-deploy check of
    `docs/specs/2026-10-01-direct-table-dml-lockdown.md` passed, and an app
    smoke test (reads plus RPC writes) passed.
- **Every slice with a migration:** apply it to the hosted project before
  building and releasing a client that depends on it. Apply it by hand in the
  SQL editor, never with `supabase db push` (see "Hosted Migration
  Deployment" in `docs/workflows/development-workflow.md`).
