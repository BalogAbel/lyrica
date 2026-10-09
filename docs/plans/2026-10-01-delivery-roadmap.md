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
> identity clear targets only that user, closing O1), then S0 PR 2, then S5a.

## Purpose

On 2026-10-01 the user asked for three things:

1. **Annotations.** A user can write on a song, circle parts of it, and so on.
   An annotation is stored either at song level (shown wherever the song is
   read) or at plan level (shown only when the song is read inside that
   plan). Annotations belong to one user and are never shared with other
   users.
2. **Saved transpose and capo.** Per user, at plan level, and optionally at
   song level. The user expects this to share the abstraction that
   annotations need.
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
    and stays in S6.

## Current State That Shapes the Work

- **Transpose and capo exist only as runtime state.** They live in
  `SongReaderState.transposeOffset` and `capoOffset`. In plan-session mode
  `SessionScopedReaderRuntimeController` keeps one reader state per session,
  so a transpose deliberately carries over to the next song. That behavior
  comes from "Reader-Local State Preservation" in
  `docs/specs/2026-04-01-session-scoped-plan-reader-navigation.md`.
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
   → `docs/deferred/2026-09-30-planning-pull-unpaged-reads.md`
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
| S0 | `fix/offline-first-startup-gate` | Field-reported bug, 2 PRs. (1) The membership gate decides from the last known identity; `verifiedEmpty` closes it only after the D5 purge; first run shows a loading state; auth-stream errors are handled; an integration test uses the real gotrue client. (2) Persist the last known capabilities (S6 option (a), pulled forward) and show a visible "last synced" indicator | `2026-09-30-capability-gating-offline-cold-start.md` (option (a) only) | M | medium |
| S5a | `fix/paged-remote-pulls` | A shared paging helper: `.range()` pages ordered by a unique key, de-duplication by id, and a `count=exact` completeness check. Applied to the planning plan and session pulls and to the song catalog list | `2026-09-30-planning-pull-unpaged-reads.md` | S–M | low–medium |
| S2 | `fix/chordpro-base-directives` | Read base `{transpose}` and `{capo}` consistently before the first lyric or chord line. `{comment}` no longer closes that base boundary. The editor uses the parser-derived base values. Update the parser tests | `2026-04-22-song-reader-chordpro-modulation.md`, item 1 | S | low |
| S3 | `feat/personal-song-settings` | Personal song layer foundation, plus per-user transpose and capo at song and plan scope, in 3 PRs: (1) backend tables, RPCs, RLS and contract tests; (2) local Drift store, outbox and pull-cursor sync, integrated with the purge lifecycle, storage budget and sync overview; (3) reader resolution and UX | — (new) | L | medium |
| S4 | `feat/song-annotations` | Annotations on the personal layer. Starts with a prototype in `docs/prototypes/`, then 2–3 PRs: (1) anchor model, overlay renderer and typed notes; (2) gesture marks (circle, underline, highlight) snapped to content; (3) free ink anchored to words, if the spec keeps it. Native (tablet and phone) first; web is best-effort | — (new) | XL | high |
| S5b | `fix/planning-mutation-gaps` | Stranded create tombstones, session-rename retry rebase, content-version advance on context switch. Verify and decide the organization-switch finding | `2026-09-30-stranded-create-tombstones.md`, `2026-09-30-session-rename-retry-never-rebases.md`, `2026-09-30-content-version-advance-on-context-switch.md`, `2026-10-01-org-switch-drops-pending-planning-mutations.md` | M–L | high |
| S7 | `feat/plan-duplicate`, then `feat/session-item-move` | Each is one server RPC; v1 is online-only, recorded in an ADR | `2026-09-29-plan-duplicate.md`, `2026-09-29-session-item-move.md` | 2×M (offline-capable: 2×L) | medium |
| S6 | `fix/capability-and-telemetry` | Reword the copy for a rejected delete (option b); option (a) moved to S0. Fix the org-id telemetry leak and add the `sessionExpired` test. Centralize PII scrubbing in `beforeSend`, `beforeSendTransaction` and `beforeBreadcrumb` | `2026-09-30-capability-gating-offline-cold-start.md`, `2026-08-28-observability-remaining-use-cases.md` | M | low–medium |
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
- **S3:**
  - The transpose UI is small. A new, third sync domain is the real work:
    backend, Drift store, outbox, pull, lifecycle and purge, storage budget,
    sync overview.
  - The data has a single owner, so last-write-wins is enough and no
    conflict UI is needed. That keeps this domain much simpler than planning.
- **S4:**
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
- **S6:**
  - Moving the scrub tests to hook level. (The per-user capability store
    moved to S0.)
- **S8:**
  - Per-line effective transpose in the projection, and the UI that shows
    where it changes.
  - Directive lines the fit estimator has to account for.

## Dependencies

**Hard (merge before the dependent slice starts its code):**

- **S1 → S3.** Without revoked default privileges, the new personal-layer
  tables get DML grants for `authenticated`.
- **S2 → S3.** Saved transpose and capo need one consistent base.
- **S2 → S8.** Modulation builds on the same parser semantics.
- **S3 → S4.** Annotations live on the personal layer.
- **S5b → S7.** Duplicate and move re-enter the same mutation machinery. The
  `docs/deferred/README.md` planning rule makes the open gaps there priority
  work first.

**Soft (preferred order, not blocking):**

- **S5a → S3.** S3's pull reuses the paging helper.
- **S1 → S7.** The new RPCs are written under the hardened grant model.
- **S3 → S7.** Duplicating a plan can copy the caller's own plan-scoped
  personal layer.

**Hotspots (never run in parallel):**

- **S3 ↔ S0 (PR 2):** `LocalDataLifecycle.clearIdentity` and the
  `LastKnownIdentity` database. S0 adds no new `PurgeTarget`: its capability
  store is cleared together with the identity.
- **S3/S4 ↔ S8:** `SongReaderProjection`.
- **S5b ↔ S7:** `drift_planning_mutation_store.dart` and
  `planning_mutation_sync_controller.dart`.

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
5. **S3:** personal song settings, in 3 PRs.
6. **S4:** annotations, as a prototype followed by 2–3 PRs.
7. **S5b:** planning mutation gaps.
8. **S7:** plan duplicate, then session-item move.
9. **S6:** rejected-delete copy and telemetry.
10. **S8:** ChordPro modulation.
11. **S9 remainder:** re-check each trigger before deciding.

**User actions:** the S1 hosted actions and the LF-T2 dashboard check are done
(2026-10-01; see "User Actions Outside the Repository").

**With several executors:**

- **Two tracks can run in parallel:**
  - Track A (reader and personal layer): S2 → S3 → S4 → S8.
  - Track B (backend and planning): S1 → S0 → S5a → S5b → S7.
- **Constraints:**
  - S3's backend migration waits for S1 to merge.
  - S0's PR 2 never runs at the same time as S3's PR 2.
  - The hotspots above stay serialized.

## Recommended Defaults

Accepted for this roadmap on 2026-10-01. Each slice spec confirms a default
or overrides it with a stated reason.

### S5b

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

### S6

- Option (a), persisted capabilities, moved to S0 on 2026-10-05
  (`docs/specs/2026-10-05-offline-first-startup-gate.md`, SG6).
- Use generic copy for a delete the backend rejects (option b).
- Add the centralized scrub hooks in the same slice: S6 is the next slice
  that touches observability, which meets that item's trigger.

### S7

- Both features are server RPCs, online-only in v1, recorded in an ADR. While
  pending local mutations touch the affected plan or sessions, the action is
  disabled.
- Duplicating a plan also copies the caller's own plan-scoped personal layer
  (settings and annotations). It never copies another user's.

### S3 (preliminary; the S3 spec finalizes these)

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
- **Plan-scope key:** `(plan_id, song_id)`, not the session item. It
  survives a session-item move and a delete followed by re-adding the song.
  Server-side cascades follow plan and song deletion.
- **What is stored:** the effective transpose, relative to the written
  chords, and the effective capo.
- **Resolution order:** plan scope, then song scope, then the ChordPro base.
- **Saving:** changes save automatically to the current scope (plan scope
  inside a plan, song scope in the library). There are "use as my default for
  this song" and "reset to my song default" actions.
- **Runtime state:**
  - The session-wide transpose and capo carry-over ends, which amends the
    2026-04-01 spec.
  - View mode, instrument and zoom keep their current behavior.
- **Organization switch:** the outbox is not deleted (see finding 4). Only an
  authoritative revocation or an explicit purge reason drops it.
- **Purge contract:**
  - The layer integrates with ADR-035: a new `PurgeTarget`, and the
    pending-local-work count.
  - Unsynced personal changes are part of what sign-out warns about.
- **Telemetry:** spans follow the ADR-036 pattern. No personal content goes
  to telemetry.

### S4 (open questions for its brainstorming session)

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
| Centralized scrub hooks | Met once S6 starts (next observability slice) | Moves into S6 |
| Remaining instrumentation | "Non-trigger" rule still applies | Only new S3 and S4 sync code gets spans, per ADR-036; nothing else is back-filled |
| Web `traceparent` gate | Still tied to the CORS gate | Stays deferred |
| Web offline e2e | Not met: web stays best-effort (user, 2026-10-01) | Stays deferred; S4 is native-first |
| Reader fit margin | No trigger | Stays deferred; S4's overlay-only rule keeps it decoupled |
| LF-T5, OCC divergence | No evidence, and nothing measures it | Stays deferred. Cheap enabler: a breadcrumb or metric when the mutation warn threshold fires (S5b or S6) |
| LF-T5b, abandoned committed write | No evidence | Stays deferred; S3 is idempotent by design and adds no new exposure |
| LF-T6, server clock anchor | No trusted server time in planning | Stays deferred; S3 orders by server sequence |

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
