# Repository Deep-Dive Review — 2026-06-22

> Consolidated architecture, security, local-first, and UI/UX review. This document
> is the canonical starting point for the next development cycle. Findings carry
> stable IDs (e.g. `SEC-1`, `LF-T1`) so plans, specs, and issues can reference them.
> Evidence is cited as `path:line`. Claims are tagged **[verified]** (read from source,
> DB, or observed live), **[inferred]** (reasoned from code), or **[assumption]**.

## 1. Scope & Method

Reviewed: `apps/lyron_app` (Flutter client, 272 Dart files), `supabase/` (18 SQL
migrations), `docs/` (22 ADRs + ~40 specs/plans + deferred), `scripts/`, CI.

Verification methods used:
- **Static**: full read of architecture-central code (DI graph, sync controllers,
  mutation store, merge repository, RLS migrations, ChordPro parser, screens).
- **Live (authenticated)**: ran the real stack via `scripts/run-authenticated-app.sh`
  (local Supabase + seeded data + provisioned demo user). Drove the Flutter **web**
  build in a preview browser by **injecting a demo session** into `localStorage`
  (`sb-127-auth-token`, the key derived at `supabase_flutter-2.12.0/.../supabase.dart:116`)
  and navigating real routes. Interaction was driven via synthetic pointer events
  (Flutter renders to a single `<canvas>`, so DOM-selector clicking is not possible).
- **Database (live)**: queried the running Postgres directly (`docker exec ... psql`)
  to confirm constraints, indexes, and RLS.

**Not covered live** (require a dedicated runtime harness): true offline relaunch,
two-device conflict convergence, screen-reader pass, and performance profiling
(`EXPLAIN`, jank, load). See §11.

## 2. System Overview

**Stack**: Flutter (3.38.5) · Riverpod · go_router · Drift · Supabase (Postgres +
Auth + RLS + RPC). Melos monorepo, currently a **single** package (`lyron_app`).

**Client layers** (`lib/src/`): `domain` (entities, value objects, repository
contracts, `Capability`), `application` (use cases, sync coordination), `infrastructure`
(Supabase + Drift adapters), `offline` (Drift DBs, stores, mutation store),
`presentation` (screens, controllers), `router` (go_router + slug resolvers).

**Local-first model**: separate Drift **projection** (read model, last synced server
state) and **mutation store** (durable local write intent with origin snapshots).
Reads merge projection + pending mutations; writes go to the mutation store and sync
to backend RPCs under optimistic concurrency. Authorization is **backend-owned**
(Postgres RLS + `security definer` RPCs); the client uses capabilities only for UX.

**Primary flows** (all observed live): invite-only auth → song list → ChordPro reader
(transpose/capo/font, immersive controls) → song CRUD; planning (plan → session →
session-item, create/edit/reorder) → unified sync UX.

## 3. Master Findings Register

Severity: **Critical** / **High** / **Medium** / **Low**.

| ID | Area | Finding | Sev |
|----|------|---------|-----|
| LF-T1 | Local-first | Session expiry is **destructive**: wipes local catalog + planning data | Critical |
| LF-T2 | Local-first | No offline token refresh → refresh-token TTL is the real "1 week" ceiling | Critical |
| LF-1 | Local-first | At-least-once delivery, no dedup: crash between accept↔clear re-sends | High |
| LF-2 | Local-first | Per-mutation full refresh inside the sync loop (N refreshes for N mutations) | High |
| LF-3 | Local-first | No internal single-flight guard on mutation sync | High |
| LF-4 | Local-first | Failed/conflicted local edits silently revert in the main UI | High |
| SEC-1 | Security | `redeem_invitation` token is bearer-only, no email binding, no rate limit | High |
| UX-1 | UI/UX | Mobile reader wraps lyric lines mid-word, breaking chord alignment | High |
| UX-2 | UI/UX | Plan date edited as raw ISO-8601 text field (no picker) | High |
| UX-8 | UI/UX | Failed local edits silently revert in the main UI (same mechanism as LF-4) | High |
| ARCH-1 | Architecture | `providers.dart` god-file (762 lines) incl. 110-line inline reconcile switch | High |
| SEC-4 | Security | Song shadow fields client-authoritative, not backend-derived from ChordPro | Medium |
| SEC-5 | Security | No DB `unique(session_id, song_id)`; "song once per session" only RPC-enforced | Medium |
| LF-5 | Local-first | `planEdit` merge blanks `description`/`scheduledFor` (asymmetric vs `name`) | Medium |
| LF-6 | Local-first | Optimistic merge can show a duplicate song in a session | Medium |
| LF-7 | Local-first | `discard`/`retry` require connectivity (can't drop a stuck mutation offline) | Medium |
| LF-8 | Local-first | Reconcile silent null-coercion (`?? ''`×11, `?? 0`×2) into the projection | Medium |
| LF-T3 | Local-first | Mutation store grows unbounded over long offline | High |
| LF-T4 | Local-first | No storage quota / eviction policy (web IndexedDB silent eviction risk) | High |
| ARCH-2 | Architecture | `planningDataRevisionProvider` coarse global invalidation → over-rebuild | Medium |
| ARCH-3 | Architecture | UI god-components: plan_detail 1240, song_editor 1088, song_reader 998 | Medium |
| UX-3 | UI/UX | New-song default body is a copyrighted song's full lyrics, hardcoded | Medium |
| UX-4 | UI/UX | List density inconsistent: plan rows rich, song rows title-only | Medium |
| UX-6 | UI/UX | CanvasKit render → no text select / find / copy; weak screen-reader support | Medium |
| UX-7 | UI/UX | No dark theme (only `theme:`); relevant for dim-stage use | Medium |
| SEC-2 | Security | `create_invitation` null-caller admin gate relies on grant scope only | Low |
| SEC-3 | Security | `has_capability`/`current_organization_ids`/`get_my_capabilities` lack `set search_path` | Low |
| LF-9 | Local-first | Slug-by-slug lookup re-merges all mutations (N+1 reads) | Low |
| LF-T5..T8 | Local-first | OCC divergence grows with offline time; clock skew; schema drift; server TTL cleanup | Low–Med |
| ARCH-4 | Architecture | Melos monorepo overhead for a single package | Low |
| ARCH-5 | Architecture | Active-organization resolution spread across providers (high implicit coupling) | Medium |
| UX-5 | UI/UX | Internal gap positions ("10.", "20.") shown to user | Low |
| UX-9 | UI/UX | Inconsistent content-width caps (sign-in 420, song-list 720, invite none) | Low |
| UX-10 | UI/UX | i18n leak: inline English in discard-all message vs centralized `AppStrings` | Low |
| UX-11 | UI/UX | Forms silently no-op on empty/invalid input (sign-in, invite) | Low–Med |
| DX-1 | Tooling | `file_picker` 3 majors behind; riverpod/go_router 1 major; supabase/gotrue minor | Medium |
| DX-2 | Tooling | No dependency-audit / coverage gate in CI | Medium |

### Resolution status (updated 2026-06-29)

Findings closed since the 2026-06-22 review, by slice. Per-section status blocks
carry the detail; this is the digest.

**Fixed**
- **LF-T1** (offline-session-resilience slice, PR #55) — session expiry is now
  **non-destructive**: offline cold-start maps to `sessionExpired` (not `signedOut`),
  offline-authenticated users stay in the app behind a re-auth banner, local data is
  retained. ADR + architecture recorded. Residual: different-user re-auth **live dialog
  wiring** is deferred (`docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`).
- **SEC-5** (planning write-contract hardening slice, PR #57) — partial unique index
  `unique(session_id, song_id) where item_type='song'` added
  (`supabase/migrations/202606290002_session_item_unique_song_index.sql`), DB-pinned by a
  failing-then-passing contract test.
- **UX-3** (arch-spine-phase0-1 slice) — the copyrighted worship-song
  `defaultSource` in the song editor is replaced with an original,
  non-copyrighted ChordPro sample that doubles as a syntax hint
  (`apps/lyron_app/lib/src/presentation/song_editor/song_editor_controller.dart`).
  Pinned by a failing-then-passing characterization test.
- **LF-3** (song path), **LF-6**, **LF-8**, **LF-T7** (local-first-validation slice, PR #56)
  — see §6 status blocks.

**Validated (already shipped under ADR-019, now guarded by adversarial tests)**
- **LF-1, LF-2, LF-4, LF-5** — see §6.2 status block.

**Characterized + still deferred** (probes added, real fix outstanding)
- **LF-T4** (`docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md`),
  **LF-T6** (`docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md`).

**Partial / corrected**
- **LF-T2** — the "decouple local access from live session validity" half is delivered
  by LF-T1; the refresh-token TTL ceiling itself is unchanged.
- **SEC-3** — `current_organization_ids` already carries `set search_path = public`
  (`20260323220000`), so the review over-counted it; `has_capability` (regressed in
  `202605250002`) and `get_my_capabilities` (`202605280001`) still lack it. 2 of 3 open.

**Still open** (unchanged): LF-7, LF-9, LF-T3, LF-T5, LF-T8, SEC-1, SEC-2, SEC-4, all
ARCH-*, all UX-*, DX-1, DX-2, and the deferred items in `docs/deferred/`.

## 4. Architecture Review

**Strengths [verified]**: clean DDD layering with one-directional dependencies and
**no import cycles** (Graphify + manual confirmation); backend-owned authorization that
the client genuinely cannot bypass (RPCs are `security definer`); a sophisticated,
MVP-proportionate local-first model (projection/mutation separation with origin
snapshots); auth-generation ownership guards against cleanup races
(`providers.dart:586-641`); `CapabilityResolver` with future-deduplication and
versioned invalidation (`application/auth/capability_resolver.dart`).

**ARCH-1 — central DI monolith.** `application/providers.dart` (762 lines) wires the
whole system and embeds business logic in provider closures — notably the ~110-line
accepted-mutation reconcile switch at `providers.dart:387-504`. Hard to test, easy to
grow. **Recommendation**: split into domain-scoped `*_providers.dart` and extract a
testable `PlanningMutationReconciler` class.

**ARCH-2 — coarse invalidation.** Every planning write bumps a single
`planningDataRevisionProvider` counter (`providers.dart:355`), forcing broad rebuilds
(e.g. full plan-detail) for small edits. **Recommendation**: aggregate-scoped
invalidation (at least per plan id).

**ARCH-3 — UI god-components.** `presentation/planning/plan_detail_screen.dart` (1240),
`presentation/song_editor/song_editor_screen.dart` (1088),
`presentation/song_reader/song_reader_screen.dart` (998). **Recommendation**: extract
sub-widgets per responsibility.

**ARCH-5 — active-organization resolution** is threaded through
`activeOrganizationResolutionProvider`, `membershipResolutionProvider`, cached-fallback,
and several controllers with auth-generation coupling — a large implicit state surface.

**ARCH-4** — `melos.yaml` manages a single package today; either grow into multiple
packages or drop the overhead.

## 5. Security Review

**Verified strengths**:
- **RLS is on for all 9 business tables** with policies — confirmed live:
  `organizations(1) groups(1) memberships(2) invitations(4) songs(2) plans(2)
  sessions(2) session_items(2) attachments(2)`.
- Write RPCs are `security definer` **with** `set search_path = public`; `anon` is
  revoked from all tables/functions; capabilities are granted to `authenticated` only
  (`supabase/migrations/202605160007_auth_boundary_hardening.sql`).
- Invitation tokens use `gen_random_bytes(32)` (strong entropy).
- Backend SQL write-contract suite is a CI gate.
- **No hardcoded secrets**; config via `String.fromEnvironment`
  (`infrastructure/config/supabase_config.dart`). The JWT in
  `scripts/manual-validation/.supabase-env` is the public Supabase local demo key.

**SEC-1 [verified] — invitation token is a pure bearer credential.**
`redeem_invitation` (`supabase/migrations/202605160002_invitations_functions.sql:48`)
stores `p_email` but never checks it against the caller; any authenticated user holding
a valid token joins the org. No rate limiting on redemption. Token entropy makes
brute force impractical, but a **leaked invite link = unintended org membership**.
**Recommendation**: bind redemption to the invited email (or explicitly document and
accept the "link == entry ticket" model), add rate limiting + an audit trail, and write
an ADR.

**SEC-4 [verified, team-known] — client-authoritative shadow metadata.** `title`,
`artist`, `key_signature`, `tempo_bpm`, `tags`, `metadata_json` are derived client-side
from canonical ChordPro and written as shadow fields, **not enforced from source at the
write-acceptance boundary**. Client/server parser drift can desync metadata from the
canonical source. Documented in `docs/deferred/2026-05-09-song-write-derived-fields.md`.
**Recommendation**: derive shadow metadata at the backend/write-acceptance boundary;
treat client shadow fields as provisional only.

**SEC-5 [verified] — missing DB invariant.** `session_items` has only
`unique(session_id, position)` — there is **no** `unique(session_id, song_id)`. The
"a song appears at most once per session" rule (relied on by slug routing at
`router/app_router.dart:145` and by the merge dedup at
`application/planning/planning_local_read_repository.dart:273`) is enforced **only** by
`create_song_session_item`. Any path bypassing that RPC, or a merge bug, yields a
duplicate and a non-deterministic `songSlug → session_item` resolution.
**Recommendation**: add a partial unique index
`unique(session_id, song_id) where item_type='song'`.
**Status (2026-06-29, planning write-contract hardening slice, PR #57): fixed.** Added in
`supabase/migrations/202606290002_session_item_unique_song_index.sql`; pinned by a
failing-then-passing DB-level contract test.

**SEC-2 [inferred]** — `create_invitation` skips the admin check when `auth.uid()` is
null (only `service_role`); safe today via grant scope, but fragile to future grant
changes. **SEC-3 [verified, corrected 2026-06-29]** — `has_capability` and
`get_my_capabilities` lack `set search_path` (invoker-rights, low risk, but inconsistent
with the hardening migration and flagged by Supabase advisors). The review's third helper,
`current_organization_ids`, **already** carries `security definer set search_path = public`
(`supabase/migrations/20260323220000_fix_membership_helper_rls_recursion.sql`) and was
over-counted; note `has_capability` had it there too but **regressed** when redefined
without it in `202605250002_organization_read_only_role_constraints.sql`. 2 of 3 open.

## 6. Local-First Review (the highest-risk subsystem)

The local-first code is the **most engineered and most test-covered on paper**, but
validation concentrates on happy-path persistence. The **runtime and failure/
convergence paths carry the most risk and least validation**. Findings split into two
axes.

### 6.1 Time-bound: "one week" → "indefinite"

ADR-008 targets "up to one week offline". This is **not a hard timer**; pure offline
keeps the cache (`catalogSessionVerifier` returns `unverifiableDueToConnectivity` on
connectivity failure → cache retained). The real ceiling is the **auth session
lifecycle**.

| ID | Problem | Evidence | Why time-bound | Needed for "indefinite" |
|----|---------|----------|----------------|-------------------------|
| **LF-T1** | Session expiry **wipes** authenticated local data (catalog + planning), even with no sign-out and possibly still offline | `application/auth/app_auth_controller.dart:75-78`; `application/planning/planning_sync_controller.dart:255-276`; `application/song_library/song_catalog_controller.dart:322`; cleanup `providers.dart:85,104` | Expiry == data wipe | Make expiry **non-destructive**: durable local "last-known membership proof"; on expiry show a re-auth banner + gate writes, keep data. Distinguish two cases: **unknown / connectivity-failed** session (offline or transient) stays non-destructive, while **authoritative revocation** (verified-empty membership, already handled by `verifiedEmptyMembershipCleanup`) and **explicit sign-out** delete local data **immediately** — do not quarantine or soft-delete revoked data, to avoid hidden-read rules, unblock semantics, and extra mutation-state handling. |
| **LF-T2** | No offline token refresh; gotrue emits null session when refresh token can't renew → triggers LF-T1 | `infrastructure/auth/supabase_auth_repository.dart:20` (`onAuthStateChange`) | Refresh-token TTL is the hard wall | Longer/rotating refresh token + decouple local access from live session validity (covered by LF-T1) |
| **LF-T3** | Mutation store grows unbounded over long offline; compaction only helps collection edits | `application/planning/drift_planning_mutation_store.dart` (compaction); no size cap | Not time-keyed, but unbounded growth | Mutation size budget + squash + threshold warning |
| **LF-T4** | No storage quota / eviction; full catalog snapshot + projection + mutations can exceed web IndexedDB quota → **silent browser eviction** | `architecture.md` Offline Strategy ("one active snapshot") | Finite storage | Size monitor + eviction policy (mutations protected, snapshot pieces droppable) |
| LF-T5 | OCC divergence grows with offline duration → larger conflict surface on reconnect | base_version capture in write contracts | Conflict probability ∝ offline time | Incremental/partial sync, finer merge |
| LF-T6 | Freshness/ordering use device clock (`DateTime.now().toUtc()` in reconcile) | `providers.dart` reconcile | Skew accumulates offline | Server-clock anchor on reconnect |
| LF-T7 | Long offline spans app upgrades; planning migration is additive (good) but no structural-change strategy; catalog DB has `schemaVersion 2` with **no** MigrationStrategy | `offline/planning/planning_local_database.dart:33-64`; `offline/song_catalog/song_catalog_database.dart:32` | More versions crossed over time | Structural-migration playbook + migration test with pending mutations present |
| LF-T8 | Server-side TTL cleanup (`pg_cron`) deletes unredeemed users >24h and expires invitations (30d) | `supabase/migrations/202605160006_pg_cron_orphan_cleanup.sql` | Server TTLs outside client horizon | Audit: active-member data must never be TTL-collected |

**Headline**: the key to "indefinite" was **LF-T1** — convert session expiry from
destructive to non-destructive. **LF-T1 is now done** (offline-session-resilience slice,
PR #55). LF-T3/LF-T4 are the remaining real blockers.

**Status (2026-06-29, offline-session-resilience slice, PR #55)**:
- `LF-T1` — **fixed**. Session expiry no longer wipes authenticated local data. Offline
  cold-start maps to `sessionExpired` (not `signedOut`); offline-authenticated users stay
  in the app behind a re-auth banner with writes gated; explicit sign-out and authoritative
  verified-empty-membership revocation still delete immediately. ADR + architecture recorded;
  e2e-covered by `apps/lyron_app/test/integration/offline_edit_relaunch_sync_flow_test.dart`.
  Residual deferred: different-user re-auth **live dialog wiring**
  (`docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`).
- `LF-T2` — **partial**. The "decouple local access from live session validity" half is
  delivered by LF-T1 (offline cold-start = `sessionExpired`). The refresh-token TTL hard
  wall itself (longer/rotating refresh token) is unchanged.

**Status (2026-06-29, local-first-validation slice)**:
- `LF-T4` — **characterized (probe) + deferred**. `storage_pressure_probe_test.dart` confirms
  a storage write failure propagates rather than being silently swallowed; the size-monitor
  and eviction policy itself remain deferred
  (`docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md`).
- `LF-T6` — **characterized (probe) + deferred**. `clock_skew_probe_test.dart` plus an
  injectable clock seam on `PlanningMutationReconciler` confirm device-clock skew flows
  through uncorrected; the server-clock anchor remains deferred
  (`docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md`).
- `LF-T7` — **fixed (catalog) + validated (planning)**. `song_catalog_migration_test.dart`
  added an explicit `MigrationStrategy` to `SongCatalogDatabase` (previously `schemaVersion 2`
  with none) and confirmed reopen survival; `planning_migration_test.dart` validated existing
  reopen survival for pending planning mutations.

### 6.2 Correctness / robustness

| ID | Problem | Evidence | Risk |
|----|---------|----------|------|
| **LF-1** | At-least-once, no dedup. Order: `syncMutation` (accepted) → `refresh` → `reconcile` → `clearMutation`. A crash between accept and clear re-sends; non-idempotent ops (rename/reorder w/ base_version) then surface a **false conflict** for an already-applied write | `application/planning/planning_mutation_sync_controller.dart:43-56`; song side same: `application/song_library/song_mutation_sync_controller.dart:24-30,143-146` | Exactly-once gap → false conflict / duplicate effect after crash |
| **LF-2** | `_refreshPlanning()` runs **inside** the per-mutation loop → N full Supabase refreshes for N mutations | `planning_mutation_sync_controller.dart:41-47`; song side `_applySuccessfulSync` per record | Slow/expensive; widens divergence window between mutations (worse with long offline) |
| **LF-3** | No internal single-flight; `syncPendingMutations` is callable concurrently (write-service scheduler + retry + discard + unified trigger) | `planning_mutation_sync_controller.dart:35`; `providers.dart:343-356` | Concurrent runs → double-send / `clearMutation` race |
| **LF-4** | `readPendingMutations` filters `syncStatus == pending` only, and the merge uses it; when an edit becomes `failed`/`conflict` it **disappears from the plan view** (reverts to server state), surfaced only in the sync popup | merge `planning_local_read_repository.dart:53`; filter `drift_planning_mutation_store.dart:423` | User's offline edit appears **lost** from the main UI on failure |
| **LF-5** | `planEdit` merge sets `description`/`scheduledFor` directly from the mutation (no `?? existing`), unlike `name` | `planning_local_read_repository.dart:143-147,211-216` | A partial edit that doesn't re-snapshot all fields blanks them locally |
| **LF-6** | `sessionItemCreateSong` dedups by item id only; same song added twice offline (different item ids) shows both until backend rejects one | `planning_local_read_repository.dart:264-283` | Local invariant violation + guaranteed sync failure for one |
| **LF-7** | `discard`/`retry` call `_refreshPlanning()` first and return on failure → cannot discard a stuck mutation **offline** | `planning_mutation_sync_controller.dart:92,109` | Dropping local intent should not need the network |
| **LF-8** | Reconcile coerces missing fields silently (`?? ''`×11, `?? 0`×2) into the projection | `providers.dart:387-504` | Unexpected null field → silent empty/zero in projection |
| LF-9 | `getPlanDetailBySlug` → `listPlans` (merge all) + `getPlanDetail` (merge again) | `planning_local_read_repository.dart:74-92` | N+1 read/merge per plan open; scales with mutation count |

**Status (2026-06-29, local-first-validation slice)**:
- `LF-1` — **validated**, already shipped (ADR-019). Guarded by
  `apps/lyron_app/test/offline/adversarial/planning_fault_injection_test.dart`.
- `LF-2` — **validated**, already shipped (ADR-019). Guarded by
  `planning_fault_injection_test.dart`.
- `LF-3` — **fixed** for the song path (planning side was already guarded by ADR-019). Guarded
  by `apps/lyron_app/test/offline/adversarial/song_single_flight_test.dart`, which added a
  single-flight guard to `SongMutationSyncController.syncPendingSongs`.
- `LF-4` — **validated**, already shipped (ADR-019). Guarded by
  `apps/lyron_app/test/offline/adversarial/planning_merge_visibility_test.dart`.
- `LF-5` — **validated**, already shipped (ADR-019). Guarded by `planning_merge_visibility_test.dart`.
- `LF-6` — **fixed**. The merge now dedups offline song-adds by `songId`. Guarded by
  `planning_merge_visibility_test.dart`.
- `LF-8` — **fixed**. The reconciler now throws a typed `ReconcileFieldError` instead of
  silently coercing a null required-on-create field to `''`/`0`. Guarded by
  `apps/lyron_app/test/offline/adversarial/planning_reconcile_nullfield_test.dart`.
- `LF-7`, `LF-9` — unchanged by this slice.

**Two root patterns**: (1) **missing exactly-once / idempotency** (LF-1, LF-3) — sync is
at-least-once with no dedup or single-flight; (2) **merge assumes mutation-record
completeness** (LF-4, LF-5, LF-6, LF-8) — a null field or a status change silently
distorts or reverts the view.

**Note**: the **song side has more mature conflict handling** than planning (remote-delete
convergence, `keepMine`/`discardMine`, pendingDelete auto-converge —
`song_mutation_sync_controller.dart:30-77`), but shares LF-1/LF-2/LF-3.

## 7. UI/UX Review (live-verified)

Verified live across desktop/tablet/mobile by injecting a demo session and navigating
real routes. The authenticated screens (song list, reader, plan list, plan detail,
edit-plan dialog, song editor) were observed with real seeded data.

**Strengths [verified]**: high-quality ChordPro reader (section labels, chords aligned
above the correct syllables, inline annotations); immersive reader with a floating
transpose/capo/font control bar; rich planning UI (drag handles, reorder, per-item
delete, navigation chevron, add-song); consistent Material 3 theme (green seed
`#0B6E4F`, cream `#F7F4EA`).

| ID | Finding | Evidence |
|----|---------|----------|
| UX-1 | Mobile reader wraps long lyric lines mid-word ("...porciká" / "m,") and the chord drifts onto the wrong syllable | reader @375px |
| UX-2 | Plan `scheduled_for` edited as a raw ISO-8601 string field (`2026-04-05T08:30:00.000Z`), no date/time picker | edit-plan dialog |
| UX-3 | Every new song is pre-filled with a real copyrighted worship song's **full lyrics** as `defaultSource` (user must clear it; copyright exposure) | `presentation/song_editor/song_editor_controller.dart:15` |
| UX-4 | Song-list rows show **title only** (no artist/key) while plan rows show title+description+date — inconsistent density | `presentation/song_library/song_list_screen.dart:263`; plan list |
| UX-5 | Internal gap-based positions ("10.", "20.") shown to the user | plan detail |
| UX-6 | CanvasKit renderer → lyrics not selectable/copyable, find-in-page fails, screen-reader support weak | all screens |
| UX-7 | No dark theme; `MaterialApp.router` sets only `theme:` | `app/lyron_app.dart:33`, `app/app_theme.dart` |
| UX-8 | Failed local edits silently revert in the main UI (same mechanism as LF-4) | see LF-4 |
| UX-9 | Inconsistent content-width caps: sign-in 420, song-list 720, invite-required none | respective screens |
| UX-10 | i18n leak: inline English in discard-all message vs centralized `AppStrings` | `presentation/sync/unified_sync_status_popup.dart:84` |
| UX-11 | Forms silently no-op on empty/invalid input (no inline error) | `sign_in_screen.dart:98`, `invite_required_screen.dart:47` |

**Accessibility — correction to first-pass**: an initial reader-only grep undercounted
this. **All 18 `IconButton`s carry `tooltip`s** (→ semantic labels), and reader controls
map to dedicated `*Semantics` strings (`song_reader_control_bar.dart:49-103`). A11y is
**better than first stated** (downgraded from "critical"). Real remaining gaps: only one
custom `Semantics` widget, and the CanvasKit screen-reader limitation (UX-6). A real
screen-reader pass is still outstanding.

## 8. Graphify Findings Validation

- **Valid**: god nodes #4-10 (`activePlanningContextProvider`, `AuthRepository`,
  `planningDataRevisionProvider`, `activeCatalogContextProvider`,
  `catalogSnapshotStateProvider`, `SongRepository`, `_SongListScreenState`); "no import
  cycles"; hyperedge clusters; community structure.
- **False positives**: god nodes #1-3 (`_`, 231/105/75 edges) are anonymous/catch-all
  noise; generated `.g.dart` files flagged as "large files".
- **Partial**: "surprising connections" are mostly doc cross-references; cohesion scores
  (0.01-0.04) are an extraction artifact, not real low cohesion.
- **Missed by Graphify**: ARCH-1 (god-file), the local-first correctness findings,
  SEC-1/SEC-5, and the a11y/UX issues.

## 9. Performance & Scalability

- **Bundle**: `main.dart.js` ≈ 3.5 MB (CanvasKit + `sqlite3.wasm` add more) — first-load
  weight, **not yet measured** for load time/jank.
- **LF-2** (per-mutation refresh) is the clearest scalability smell.
- `has_capability` RLS helper runs per row; it is `stable` so Postgres can InitPlan-cache
  it, but **`EXPLAIN` on large catalogs is unverified** — a watch item.
- `CapabilityResolver` future-dedup and single-RPC `get_my_capabilities` are good.

## 10. Testing

99 test files, strong pyramid (unit/widget/integration/backend), backend write-contract
and migration-lint CI gates, mandatory persistence stubbing, `context.mounted` discipline,
0 TODO/FIXME. **Gaps**: no accessibility/contrast tests; no screen-reader pass; no reader
fit-layout performance regression test. A fit-layout regression test must also assert
**estimate/render consistency**: the fit-to-screen calculator and the render grid must
receive the **same padding-adjusted dimensions** (resolved content padding subtracted),
and the height-estimation logic must **mirror the actual render logic exactly** (including
conditional checks such as string trimming and collapsing empty elements), or the estimated
fit and the rendered output drift apart.

**Update (2026-06-29, local-first-validation slice)**: the two gaps formerly listed here —
"no live offline/conflict e2e" and "no mutation-preservation-across-migration test
(LF-T7)" — are now covered for the **native** target. Native offline/conflict e2e is
covered by `apps/lyron_app/test/integration/offline_edit_relaunch_sync_flow_test.dart`
(`LF-T1`) and `two_device_conflict_matrix_test.dart` (both skip-gated on a live local
Supabase stack; both have since been run and pass against a live stack — see
`docs/testing/testing-strategy.md`, "Adversarial Offline/Sync Validation"). Mutation-preservation-across-migration (`LF-T7`) is covered by
`apps/lyron_app/test/offline/adversarial/planning_migration_test.dart` and
`song_catalog_migration_test.dart`. The **web**/IndexedDB e2e gap remains open and is
tracked in `docs/deferred/2026-06-29-web-offline-e2e.md`.

## 11. Open / Untested Areas (next slices)

1. **Local-First Validation slice** (adversarial, not happy-path): real offline harness
   (native + web) for edit-offline → relaunch → sync → convergence; two-device conflict
   matrix; fault injection (kill mid-sync, partial RPC success + refresh failure → the
   reconcile path); LF-8 reconcile hardening with null-field tests; Drift migration test
   with pending mutations (LF-T7); storage-pressure test (LF-T4); clock-skew (LF-T6).
   **Done (2026-06-29) for the native target** — see the adversarial suite under
   `apps/lyron_app/test/offline/adversarial/` and the two skip-gated integration suites
   under `apps/lyron_app/test/integration/`, recorded in
   `docs/testing/testing-strategy.md` ("Adversarial offline/sync validation"). The web
   harness half is deferred (`docs/deferred/2026-06-29-web-offline-e2e.md`), LF-T4/LF-T6
   were characterized via probes and remain deferred for the full fix
   (`docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md`,
   `docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md`), and the two new integration
   suites have since been verified against a live Supabase stack (see
   `docs/testing/testing-strategy.md`).
2. **Schema-vs-app gap**: DB has `groups`, group roles, `attachments`, and session-item
   `note`/`attachment` types; the app only exercises org-level membership and song items.
   Decide which are roadmap vs dead schema.
3. **FreeShow integration** (ADR-010, `docs/integrations/freeshow.md`) — stated direction,
   explicit MVP non-goal; unreviewed.
4. **i18n**: UI is hardcoded English (`AppStrings`) while content is Hungarian; no
   localization framework.
5. **Production readiness**: no crash reporting, analytics, structured prod logging,
   feature flags, or CD/release pipeline; PWA/offline-web hosting story unaudited.
6. **Performance profiling**: bundle/load/jank + `EXPLAIN` on catalog/planning reads.
7. **Screen-reader pass** (VoiceOver/TalkBack on the CanvasKit surface).

**Team-known deferred items** (`docs/deferred/`): popup-row recovery `WidgetRef` lifetime
(stale UI if popup closed mid-op — fix by delegating recovery actions to a long-lived
controller with `ProviderRef` so invalidations/refreshes fire regardless of popup mount
state, rather than relying on the transient `WidgetRef`/`context.mounted`), planning
reorder optimistic-overlay cleanup, and
SEC-4 (song shadow fields). Per `docs/deferred/README.md`, these become priority work
when a slice re-enters their area.

## 12. Dependencies (DX-1)

Direct deps behind latest: `file_picker` 8.3.7 → 11.0.2 (**3 majors**),
`flutter_riverpod`/`riverpod` 2.6.1 → 3.3.2 (1 major, *resolvable* via constraint bump),
`go_router` 16.3.0 → 17.3.0 (1 major), `supabase_flutter`/`gotrue`/`supabase`
2.12/2.18/2.10 → 2.15/2.22/2.13 (minor — **auth, security-relevant**). No known CVEs in
the audit output; the risk is staleness. **DX-2**: no `pub`-audit or coverage gate in CI.

## 13. Prioritized Roadmap

**Quick wins (1-2 days)**
- ~~SEC-5: add `unique(session_id, song_id) where item_type='song'`.~~ **Done (PR #57).**
- SEC-3: `set search_path = public` on the two remaining invoker-rights helpers
  (`has_capability`, `get_my_capabilities`); `current_organization_ids` already has it.
- LF-8: replace silent `?? ''`/`?? 0` with invariant asserts / explicit rejection + tests.
- ~~UX-3: replace the copyrighted default song body with a non-copyrighted placeholder/hint.~~ **Done (arch-spine-phase0-1).**
- A11y: add the missing `semanticLabel`/`Semantics` on the few non-tooltip surfaces.

**Medium (1-2 weeks)**
- ~~LF-T1: make session expiry non-destructive (the "indefinite offline" keystone).~~
  **Done (PR #55).** Residual: different-user re-auth live dialog wiring (deferred).
- LF-1 + LF-3: idempotency key / accepted-but-uncleared marker + single-flight guard.
- LF-2: hoist refresh out of the per-mutation loop (sync all, then refresh once).
- LF-4: surface failed local edits in the main UI instead of silently reverting.
- ARCH-1: split `providers.dart`; extract `PlanningMutationReconciler`.
- UX-1: reader line-wrap/chord-alignment on narrow widths; UX-2: date picker.
- SEC-1: invite email-binding + rate limit + audit + ADR.
- DX-1/DX-2: bump auth packages; add pub-audit + coverage gates.

**Strategic (1+ month)**
- LF-T3/LF-T4: mutation budget + storage eviction policy for indefinite offline.
- ARCH-2: aggregate-scoped invalidation.
- ARCH-3: decompose plan_detail / song_editor.
- SEC-4: backend-derived shadow metadata.
- Schema-vs-app reconciliation; FreeShow; i18n; production-readiness; design-token layer;
  dark mode (UX-7).

## 14. Evidence Appendix

- DB (live): `session_items` constraints = pkey, `unique(session_id, position)`, FKs,
  reference/version checks — **no** `unique(session_id, song_id)`. RLS on all 9 business
  tables with policies.
- Live UX: authenticated app driven via session injection + synthetic pointer events;
  observed song list, reader (desktop+mobile), immersive controls, plan list, plan
  detail, edit-plan dialog, song editor — all with seeded data.
- Deps: `flutter pub outdated` (see §12).
- Method limits: Flutter web = single `<canvas>` → no DOM-selector interaction; offline
  and screen-reader paths require a runtime harness (§11).
