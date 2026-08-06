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
| LF-T2 | Local-first | No offline token refresh → refresh-token TTL is the real "1 week" ceiling. **Deferred with trigger condition (offline-durability-phase4, S15)** — see `docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md`. | Critical |
| LF-1 | Local-first | At-least-once delivery, no dedup: crash between accept↔clear re-sends | High |
| LF-2 | Local-first | Per-mutation full refresh inside the sync loop (N refreshes for N mutations) | High |
| LF-3 | Local-first | No internal single-flight guard on mutation sync | High |
| LF-4 | Local-first | Failed/conflicted local edits silently revert in the main UI | High |
| ~~SEC-1~~ | Security | ~~`redeem_invitation` token is bearer-only, no email binding, no rate limit~~ **Done (security-read-boundary-phase3).** | High |
| ~~UX-1~~ | UI/UX | ~~Mobile reader wraps lyric lines mid-word, breaking chord alignment~~ **Done (ui-decomposition-phase2).** | High |
| ~~UX-2~~ | UI/UX | ~~Plan date edited as raw ISO-8601 text field (no picker)~~ **Done (ui-decomposition-phase2).** | High |
| UX-8 | UI/UX | Failed local edits silently revert in the main UI (same mechanism as LF-4) | High |
| ARCH-1 | Architecture | `providers.dart` god-file (762 lines) incl. 110-line inline reconcile switch | High |
| ~~SEC-4~~ | Security | ~~Song shadow fields client-authoritative, not backend-derived from ChordPro~~ **Done (read-boundary-and-derived-song-metadata).** | Medium |
| SEC-5 | Security | No DB `unique(session_id, song_id)`; "song once per session" only RPC-enforced | Medium |
| LF-5 | Local-first | `planEdit` merge blanks `description`/`scheduledFor` (asymmetric vs `name`) | Medium |
| LF-6 | Local-first | Optimistic merge can show a duplicate song in a session | Medium |
| ~~LF-7~~ | Local-first | ~~`discard`/`retry` require connectivity (can't drop a stuck mutation offline)~~ **Done (offline-durability-phase4).** | Medium |
| LF-8 | Local-first | Reconcile silent null-coercion (`?? ''`×11, `?? 0`×2) into the projection | Medium |
| ~~LF-T3~~ | Local-first | ~~Mutation store grows unbounded over long offline~~ **Done (offline-durability-phase4).** | High |
| ~~LF-T4~~ | Local-first | ~~No storage quota / eviction policy (web IndexedDB silent eviction risk)~~ **Done (offline-durability-phase4), native-only verification.** | High |
| ARCH-2 | Architecture | `planningDataRevisionProvider` coarse global invalidation → over-rebuild | Medium |
| ~~ARCH-3~~ | Architecture | ~~UI god-components: plan_detail 1240, song_editor 1088, song_reader 998~~ **Done (ui-decomposition-phase2).** | Medium |
| UX-3 | UI/UX | New-song default body is a copyrighted song's full lyrics, hardcoded | Medium |
| UX-4 | UI/UX | List density inconsistent: plan rows rich, song rows title-only | Medium |
| UX-6 | UI/UX | CanvasKit render → no text select / find / copy; weak screen-reader support | Medium |
| UX-7 | UI/UX | No dark theme (only `theme:`); relevant for dim-stage use | Medium |
| SEC-2 | Security | `create_invitation` null-caller admin gate relies on grant scope only | Low |
| SEC-3 | Security | `has_capability`/`current_organization_ids`/`get_my_capabilities` lack `set search_path` | Low |
| ~~LF-9~~ | Local-first | ~~Slug-by-slug lookup re-merges all mutations (N+1 reads)~~ **Done (offline-durability-phase4).** | Low |
| LF-T5 | Local-first | OCC divergence grows with offline duration → larger conflict surface on reconnect. **Deferred with trigger condition (offline-durability-phase4, S15)** — see `docs/deferred/2026-07-31-occ-divergence-lf-t5.md`. | Low |
| LF-T6 | Local-first | Freshness/ordering use device clock (`DateTime.now().toUtc()` in reconcile). **Characterized + deferred; re-confirmed still deferred (offline-durability-phase4, S15)** — see `docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md`. | Low |
| ~~LF-T7~~ | Local-first | ~~No structural-migration playbook~~ **Fixed (catalog) + validated (planning) (local-first-validation).** | Low–Med |
| ~~LF-T8~~ | Local-first | ~~Server-side TTL cleanup (`pg_cron`) deletes unredeemed users >24h and expires invitations (30d)~~ **Validated — audited, no gap found (offline-durability-phase4, S15).** | Low |
| ARCH-4 | Architecture | Melos monorepo overhead for a single package | Low |
| ARCH-5 | Architecture | Active-organization resolution spread across providers (high implicit coupling) | Medium |
| UX-5 | UI/UX | Internal gap positions ("10.", "20.") shown to user | Low |
| UX-9 | UI/UX | Inconsistent content-width caps (sign-in 420, song-list 720, invite none) | Low |
| UX-10 | UI/UX | i18n leak: inline English in discard-all message vs centralized `AppStrings` | Low |
| UX-11 | UI/UX | Forms silently no-op on empty/invalid input (sign-in, invite) | Low–Med |
| ~~DX-1~~ | Tooling | ~~`file_picker` 3 majors behind; riverpod/go_router 1 major; supabase/gotrue minor~~ **Done (security-read-boundary-phase3), riverpod deferred.** | Medium |
| ~~DX-2~~ | Tooling | ~~No dependency-audit / coverage gate in CI~~ **Done (security-read-boundary-phase3).** | Medium |

### Resolution status (updated 2026-08-02)

Findings closed since the 2026-06-22 review, by slice. Per-section status blocks
carry the detail; this is the digest.

**Fixed**
- **LF-T1** (offline-session-resilience slice, PR #55) — session expiry is now
  **non-destructive**: offline cold-start maps to `sessionExpired` (not `signedOut`),
  offline-authenticated users stay in the app behind a re-auth banner, local data is
  retained. ADR + architecture recorded. ~~Residual: different-user re-auth **live dialog
  wiring** is deferred.~~ **Done (offline-durability-phase4, S14).** `resolveReauth` and
  `showReauthDifferentUserDialog` are now wired to the live `signedIn` edge behind a
  `ReauthPromptController`/`ReauthPromptHost` seam. ADR-029.
- **SEC-5** (planning write-contract hardening slice, PR #57) — partial unique index
  `unique(session_id, song_id) where item_type='song'` added
  (`supabase/migrations/202606290002_session_item_unique_song_index.sql`), DB-pinned by a
  failing-then-passing contract test.
- **UX-3** (arch-spine-phase0-1 slice) — the copyrighted worship-song
  `defaultSource` in the song editor is replaced with an original,
  non-copyrighted ChordPro sample that doubles as a syntax hint
  (`apps/lyron_app/lib/src/presentation/song_editor/song_editor_controller.dart`).
  Pinned by a failing-then-passing characterization test.
- **SEC-3** (arch-spine-phase0-1 slice) — `has_capability` and
  `get_my_capabilities` now pin `set search_path = public`
  (`supabase/migrations/202607080001_capability_search_path_hardening.sql`),
  matching `current_organization_ids`. A backend contract test
  (`scripts/tests/capability-search-path-contract-test.sh`, wired into the
  `backend_write_contracts` job) guards all three helpers against silent
  regression.
- **ARCH-1** (arch-spine-phase0-1 slice) — the `PlanningMutationReconciler` was
  already extracted (`b2d1053`, tested, injectable clock); the remaining
  `providers.dart` god-file (776 lines) is now split into four domain-scoped
  files (`core_providers`, `auth_providers`, `song_catalog_providers`,
  `planning_providers`) behind a re-export barrel. ADR-021. Zero call-site churn;
  the full provider surface is pinned by a characterization test.
- **ARCH-5** (arch-spine-phase0-1 slice) — active-organization resolution is
  consolidated into a single `ActiveOrganizationResolver` (application layer)
  that owns the raw / cached-fallback / organization-id flavors; the three
  resolution providers delegate to it with identical seams. ADR-022 (extends
  ADR-016; completes the identity seam ADR-020 began). The different-user
  re-auth wiring intersection noted here is now closed (S14, ADR-029).
- **ARCH-2** (arch-spine-phase0-1 slice) — planning invalidation is split into an
  aggregate signal (`planningDataRevisionProvider`) and a mutation signal
  (`planningMutationRevisionProvider`) watched only by the mutation-facing
  readers, so within-plan session/item edits no longer rebuild other plans'
  details or by-slug summaries. The accepted cross-plan post-sync staleness
  trade-off is documented in `architecture.md`.
- **LF-3** (song path), **LF-6**, **LF-8**, **LF-T7** (local-first-validation slice, PR #56)
  — see §6 status blocks.
- **SEC-1** (security-read-boundary-phase3 slice) — `redeem_invitation` is now
  hybrid email-bound (email-bound when the invitation carries an address, bearer
  otherwise), rate limited per caller on `not_found`/`email_mismatch` outcomes, and
  attempts are audited in `public.invitation_redemption_attempts`, with repeated
  terminal outcomes collapsed to one row per caller, token and window
  (`supabase/migrations/202607290001_invitation_redemption_audit.sql`,
  `supabase/migrations/202607290002_invitation_redemption_contract.sql`). The RPC
  returns a `jsonb` status envelope instead of raising for business outcomes, which
  is what makes both the audit trail and the rate limit possible. ADR-025 records
  the model and the rejected alternatives; pinned by
  `scripts/tests/invitation-redemption-contract-test.sh`.
- **SEC-4** (read-boundary-and-derived-song-metadata slice) — `create_song`
  and `song_write_update_common` now derive `title`, `artist`,
  `key_signature`, `tempo_bpm`, and `tags` from canonical ChordPro at the
  write-acceptance boundary instead of accepting them from the client; the
  original finding's severity was also corrected, since five of the six
  named fields were never written by the client at all rather than
  client-authoritative and drifting. ADR-027. Pinned by
  `scripts/tests/song-derived-metadata-contract-test.sh`.

- **LF-T3, LF-T4** (offline-durability-phase4 slice) — the local mutation store now
  carries an explicit content-derived byte budget (`BudgetedPlanningMutationStore`)
  that refuses new writes past a hard threshold, and a stated eviction protection
  order (pending mutations, the planning projection, and cached catalog summaries are
  never evicted; only cached catalog sources for songs with no pending mutation are
  droppable) enforced on an actual storage write failure. Two correctness gaps in the
  underlying mutation fold were fixed in the same slice: base-version rebasing now
  agrees across all fold paths, and collapsing a still-pending `sessionCreate` no
  longer orphans that session's pending item mutations. See
  [ADR-028](decisions/ADR-028-local-storage-budget-and-eviction-policy.md), pinned by
  `test/offline/adversarial/planning_squash_contract_test.dart`,
  `test/offline/adversarial/storage_pressure_contract_test.dart` (promoted from the
  prior probe), and the `test/application/storage/` and
  `test/application/planning/budgeted_planning_mutation_store_test.dart` suites.
  Every threshold is verified against native Drift/sqlite3 only; the web/IndexedDB
  assumptions remain unverified (`docs/deferred/2026-06-29-web-offline-e2e.md`).
  The PR #64 review then found the eviction/recovery half of this had only ever
  been wired to the planning-mutation write path; it is now a single shared
  boundary covering every local write that can grow stored bytes, the budget's
  measure-check-write sequence is serialised per `(userId, organizationId)`, and
  a delete that collapses a still-pending create is admitted regardless of
  budget — see the 2026-08-04 status block below.

- **LF-7, LF-9** (offline-durability-phase4 slice) — see §6.2 status block. LF-7's live
  violation was on the **song** side (`SongMutationSyncController.discardMine`), not the
  planning file the original finding cited; the planning half was already local-first as
  a side effect of PR #62/#63. LF-9's fix is a correctness fix to an interface method
  with **no live caller** today, not a measured performance win.

**Validated (already shipped under ADR-019, now guarded by adversarial tests)**
- **LF-1, LF-2, LF-4, LF-5** — see §6.2 status block.

**Validated (audited, no gap found)**
- **LF-T8** (offline-durability-phase4 slice, S15) — the server-side `pg_cron` TTL
  cleanup was audited against the actual migrations and code: no membership status
  other than `active` is ever written, no authorship foreign key cascades from
  `auth.users` (all are `on delete set null`), and invitation expiry is a read-time
  check, not a sweep. Pinned by
  `scripts/tests/pg-cron-orphan-cleanup-contract-test.sh`. See §6.1 status block.
  This was never a live defect; do not read it as a fix.

**Deferred (trigger condition stated)**
- **LF-T6** (`docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md`) —
  characterized via probe (local-first-validation slice); re-confirmed still
  deferred in offline-durability-phase4, S15, since its trigger condition (a
  trusted server-time source) was not introduced by S12 or S13.
- **LF-T5** (`docs/deferred/2026-07-31-occ-divergence-lf-t5.md`, offline-durability-
  phase4, S15) — this finding had no deferred doc before this phase. Finer merge
  granularity remains out of scope, but the S12 mutation budget and footprint
  monitor now bound and surface the divergence this finding describes, and the S12
  squash contract fixed a real base-version-fold defect found in the same slice.
  See §6.1 status block.
- **LF-T2** (`docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md`, offline-
  durability-phase4, S15) — this finding also had no deferred doc before this
  phase, and was the last LF-* id this review could not place cleanly into a
  closed state. The "decouple local access from live session validity" half is
  delivered by LF-T1/ADR-020; the refresh-token TTL hard wall itself is unchanged
  and cannot be fixed client-side, since it is a property of the auth provider's
  token lifetime/session policy. Established while writing the deferred doc: the
  loss when the TTL is exhausted offline is to **sync only**, not to local read or
  write access — cached data stays fully readable and new edits keep queuing
  locally regardless of live session validity, per ADR-020's non-destructive
  policy. See §6.1 status block.

**Corrected**
- **SEC-3** — previously tracked here as "2 of 3 open" after the 2026-06-29
  over-count correction; now fully closed (see **Fixed** above).

**Still open** (unchanged): SEC-2, all ARCH-*, all UX-*, and the deferred items in
`docs/deferred/` other than LF-T5, LF-T6, and LF-T2, which are deferred-with-trigger
rather than open. Every LF-* and LF-T* id is now fixed, validated, or deferred with a
trigger condition; none remain open or partial.

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

**Fixed (arch-spine-phase0-1)**: `PlanningMutationReconciler` extracted earlier
in `b2d1053`; the file split into domain-scoped `*_providers.dart` behind a
barrel landed in this slice (ADR-021).

**ARCH-2 — coarse invalidation.** Every planning write bumps a single
`planningDataRevisionProvider` counter (`providers.dart:355`), forcing broad rebuilds
(e.g. full plan-detail) for small edits. **Recommendation**: aggregate-scoped
invalidation (at least per plan id).
**Fixed (arch-spine-phase0-1)**: within-plan edits now bump a mutation-scoped
revision (`planningMutationRevisionProvider`) watched only by the mutation-facing
readers; only aggregate events (plan-summary edit, sync completion, discard/retry)
bump the global signal, so a small edit no longer rebuilds unrelated plan details.

**ARCH-3 — UI god-components.** `presentation/planning/plan_detail_screen.dart` (1240),
`presentation/song_editor/song_editor_screen.dart` (1088),
`presentation/song_reader/song_reader_screen.dart` (998). **Recommendation**: extract
sub-widgets per responsibility.

**Done (ui-decomposition-phase2).** plan_detail 1232 → 362, song_editor 1088 → 380,
song_reader 998 → 462. Sub-widgets live under each area's `widgets/` directory and the
reader's behaviour (immersive mode, zoom persistence, song actions, command dispatch,
scoped navigation) moved into plain classes beside the screen. What remains in each
screen is state lifecycle and the provider watches that must stay there. Behaviour
preservation was proven by characterization tests written before the extraction and
passing unchanged after it, plus a provider-call drift check per screen; every extracted
widget now has a test that builds it directly.

**ARCH-5 — active-organization resolution** is threaded through
`activeOrganizationResolutionProvider`, `membershipResolutionProvider`, cached-fallback,
and several controllers with auth-generation coupling — a large implicit state surface.

**Fixed (arch-spine-phase0-1)**: consolidated into `ActiveOrganizationResolver`
with the providers delegating (ADR-022); controller per-outcome fallback policy
retained per ADR-016.

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
~~**Recommendation**: bind redemption to the invited email (or explicitly document and
accept the "link == entry ticket" model), add rate limiting + an audit trail, and write
an ADR.~~
**Status (2026-07-29, security read-boundary phase 3, SEC-1): fixed.** Redemption is
email-bound when the invitation carries an address
(`supabase/migrations/202607290002_invitation_redemption_contract.sql`), rate limited
per caller, and audited in `public.invitation_redemption_attempts`
(`supabase/migrations/202607290001_invitation_redemption_audit.sql`). Model and
rejected alternatives recorded in ADR-025; pinned by
`scripts/tests/invitation-redemption-contract-test.sh`.

**SEC-4 [verified] — corrected and fixed.** The original finding overstated
the problem for five of the six named fields. Verified against the code:
`SongMutationRecord` and the sync payload never carried `artist`,
`key_signature`, `tempo_bpm`, `tags`, or `metadata_json` at all — those four
shadow fields were simply never written by the application (they stayed null
or empty for every app-created song), not "client-authoritative and
drifting." Only `title` was genuinely client-supplied and could drift from
its source. `metadata_json` has no ChordPro origin to derive from and
remains out of scope.
**Status (2026-07-29, read-boundary-and-derived-song-metadata slice):
fixed.** `create_song` and `song_write_update_common`
(`supabase/migrations/202607290004_derive_song_metadata.sql`) now derive
`title`, `artist`, `key_signature`, `tempo_bpm`, and `tags` from canonical
ChordPro inside the `security definer` write boundary; the corresponding
client-supplied RPC parameters (plus `p_metadata_json`) are removed. See
[ADR-027](decisions/ADR-027-backend-derived-song-metadata.md), pinned by
`scripts/tests/song-derived-metadata-contract-test.sh`.

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
without it in `202605250002_organization_read_only_role_constraints.sql`.
**Fixed (arch-spine-phase0-1)**: `has_capability` and `get_my_capabilities`
now pin `set search_path = public` (`supabase/migrations/202607080001_capability_search_path_hardening.sql`),
guarded by `scripts/tests/capability-search-path-contract-test.sh`. **Correction (2026-07-29):**
`202607080001` closed only the `search_path` half — the same `202605250002` redefinition
also dropped `security definer` on `has_capability`, which broke the RLS recursion fix from
`20260323220000` and was missed at the time. Consequence: the "memberships are manageable
by capability" ALL policy calls `can_manage_membership` → `has_capability`, which reads
`public.memberships` as invoker and re-enters the same policy, so any authenticated read of
`memberships` — and the `get_my_capabilities` RPC, which reads `memberships` as invoker —
failed with `stack depth limit exceeded`. Restored on 2026-07-29 in
`supabase/migrations/202607290000_has_capability_security_definer_restore.sql`, now pinned
by `scripts/tests/capability-search-path-contract-test.sh` asserting both `proconfig`
(`search_path=public`) and `prosecdef` (security definer). All 3 helpers closed.

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
| ~~**LF-T3**~~ | ~~Mutation store grows unbounded over long offline; compaction only helps collection edits~~ **Done (offline-durability-phase4).** | `application/planning/drift_planning_mutation_store.dart` (compaction); no size cap | Not time-keyed, but unbounded growth | Mutation size budget + squash + threshold warning |
| ~~**LF-T4**~~ | ~~No storage quota / eviction; full catalog snapshot + projection + mutations can exceed web IndexedDB quota → **silent browser eviction**~~ **Done (offline-durability-phase4), native-only verification.** | `architecture.md` Offline Strategy ("one active snapshot") | Finite storage | Size monitor + eviction policy (mutations protected, snapshot pieces droppable) |
| LF-T5 | OCC divergence grows with offline duration → larger conflict surface on reconnect. **Deferred with trigger condition (offline-durability-phase4, S15)** — see below. | base_version capture in write contracts | Conflict probability ∝ offline time | Incremental/partial sync, finer merge |
| LF-T6 | Freshness/ordering use device clock (`DateTime.now().toUtc()` in reconcile). **Characterized + deferred; re-confirmed still deferred (offline-durability-phase4, S15)** — see below. | `providers.dart` reconcile | Skew accumulates offline | Server-clock anchor on reconnect |
| LF-T7 | Long offline spans app upgrades; planning migration is additive (good) but no structural-change strategy; catalog DB has `schemaVersion 2` with **no** MigrationStrategy | `offline/planning/planning_local_database.dart:33-64`; `offline/song_catalog/song_catalog_database.dart:32` | More versions crossed over time | Structural-migration playbook + migration test with pending mutations present |
| LF-T8 | Server-side TTL cleanup (`pg_cron`) deletes unredeemed users >24h and expires invitations (30d). **Validated — audited, no gap found (offline-durability-phase4, S15)** — see below. | `supabase/migrations/202605160006_pg_cron_orphan_cleanup.sql` | Server TTLs outside client horizon | Audit: active-member data must never be TTL-collected |

**Headline**: the key to "indefinite" was **LF-T1** — convert session expiry from
destructive to non-destructive. **LF-T1 is now done** (offline-session-resilience slice,
PR #55). **LF-T3/LF-T4 are now done too** (offline-durability-phase4 slice, native-only
verification — see below). **LF-T5, LF-T6, LF-T8 and LF-T2 were resolved to a closed
state in S15** (LF-T5, LF-T6 and LF-T2 deferred with a stated trigger condition, LF-T8
validated) — see the S15 status block below. Every LF-T* finding is now fixed,
validated, or deferred with a trigger condition; none remain merely open.

**Status (2026-06-29, offline-session-resilience slice, PR #55)**:
- `LF-T1` — **fixed**. Session expiry no longer wipes authenticated local data. Offline
  cold-start maps to `sessionExpired` (not `signedOut`); offline-authenticated users stay
  in the app behind a re-auth banner with writes gated; explicit sign-out and authoritative
  verified-empty-membership revocation still delete immediately. ADR + architecture recorded;
  e2e-covered by `apps/lyron_app/test/integration/offline_edit_relaunch_sync_flow_test.dart`.
  ~~Residual deferred: different-user re-auth **live dialog wiring**.~~
  **Done (offline-durability-phase4, S14).** See ADR-029.
- `LF-T2` — ~~**partial**. The "decouple local access from live session validity" half is
  delivered by LF-T1 (offline cold-start = `sessionExpired`). The refresh-token TTL hard
  wall itself (longer/rotating refresh token) is unchanged.~~ **Deferred with a stated
  trigger condition (offline-durability-phase4, S15).** See the S15 status block below
  and `docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md`.

**Status (2026-06-29, local-first-validation slice)**:
- `LF-T4` — **characterized (probe) + deferred at the time**. `storage_pressure_probe_test.dart`
  confirmed a storage write failure propagates rather than being silently swallowed; the
  size-monitor and eviction policy itself were deferred
  (`docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md`). Superseded below.
- `LF-T6` — **characterized (probe) + deferred**. `clock_skew_probe_test.dart` plus an
  injectable clock seam on `PlanningMutationReconciler` confirm device-clock skew flows
  through uncorrected; the server-clock anchor remains deferred
  (`docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md`).
- `LF-T7` — **fixed (catalog) + validated (planning)**. `song_catalog_migration_test.dart`
  added an explicit `MigrationStrategy` to `SongCatalogDatabase` (previously `schemaVersion 2`
  with none) and confirmed reopen survival; `planning_migration_test.dart` validated existing
  reopen survival for pending planning mutations.

**Status (2026-07-30, offline-durability-phase4 slice)**:
- `LF-T3` — **fixed**. `BudgetedPlanningMutationStore` measures the mutation store's
  content-derived byte footprint before every write that can grow it and refuses new
  writes at or past a hard threshold (`PlanningMutationBudgetExceededException`); a
  refused write, including a refused **fold** into an already-pending aggregate, never
  destroys or partially applies anything, and `clearMutation`/`retryMutation` stay
  unguarded so a full store can always be drained. Pinned by
  `test/application/planning/budgeted_planning_mutation_store_test.dart` and
  `test/application/storage/`. ADR-028.
- `LF-T4` — **fixed, native-only verification**. A stated eviction protection order
  (pending planning and song mutations, the planning projection, and cached catalog
  summaries are never evicted; only cached catalog sources for songs with no pending
  mutation are droppable) is enforced by `SongCatalogEvictor` when a local write fails
  at the storage layer: evict once, retry once, else surface a typed
  `LocalStorageWriteFailure`. `storage_pressure_probe_test.dart` is promoted from
  characterization probe to the enforced contract
  `test/offline/adversarial/storage_pressure_contract_test.dart`.
  `docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md` is resolved and removed.
  Accounting is content-derived (SQL `length(...)` over row content), so the logic is
  platform-independent, but every threshold and the eviction trigger are verified
  against native Drift/sqlite3 only — whether the browser evicts underneath this policy
  regardless, and whether the byte estimate tracks real IndexedDB usage, remain
  unverified. `docs/deferred/2026-06-29-web-offline-e2e.md` stays open as the
  prerequisite for relying on IndexedDB capacity assumptions. ADR-028.
- Two correctness gaps in the mutation fold, found while specifying the budget, were
  fixed in the same slice: base-version rebasing on a fold now agrees across all fold
  paths (previously the reorder paths kept the first-captured base version while
  `planEdit`/`sessionRename`/`sessionDelete`/`sessionItemDelete` let a later draft
  overwrite it, which could silently suppress a real OCC conflict), and collapsing a
  still-pending `sessionCreate` now deletes that session's pending `session_item` and
  `session_item_order` mutations in the same transaction instead of orphaning them.
  Pinned by `test/offline/adversarial/planning_squash_contract_test.dart`.

**Status (2026-08-02, offline-durability-phase4 slice, S15)**:
- `LF-T8` — **validated**. Audited against the actual migrations and code rather than
  assumed: `membership_status` is `active | invited | suspended`, but every membership
  insert in the codebase — including both versions of `redeem_invitation`
  (`supabase/migrations/202605160002_invitations_functions.sql`,
  `supabase/migrations/202607290002_invitation_redemption_contract.sql`) — writes
  `'active'` directly, so there is no transient membership state the cleanup's
  `status = 'active'` predicate could wrongly treat as gone. The indirect risk (a
  revoked member's `auth.users` row being TTL-collected and cascading into
  organization content) does not exist: of every foreign key referencing
  `auth.users`, only `memberships.user_id` is `on delete cascade`, and it removes
  only that user's own membership row. Every authorship link — `songs`, `plans`,
  `sessions`, `session_items`, `attachments` (`last_modified_by`, closed earlier by
  `202605160004_last_modified_by_on_delete_set_null.sql`), plus
  `invitations.issued_by`/`redeemed_by` and
  `invitation_redemption_attempts.actor_user_id` — is `on delete set null`, so
  organization content is keyed on `organization_id` and survives its author's
  deletion. The 30-day invitation expiry is a read-time check inside
  `redeem_invitation` (`expires_at <= now()`), not a sweep; no migration deletes
  from `public.invitations`. Exactly two `cron.job` rows are registered — this job
  and a 90-day retention sweep on the redemption-attempt audit log
  (`202607290001_invitation_redemption_audit.sql`) — and the new
  `scripts/tests/pg-cron-orphan-cleanup-contract-test.sh` (wired into
  `scripts/backend-write-contracts.sh`) asserts the live `cron.job` set equals that
  allowlist, drives the cleanup's exact delete statement against fixtures for every
  membership status, and asserts the authorship survives with `last_modified_by`/
  `issued_by` nulled. This was never a live defect; it is now audited and pinned
  rather than merely asserted.
- `LF-T6` — **re-confirmed still deferred; trigger condition not met.** S12 and S13
  (this same phase) introduced no trusted server-time source: the mutation store
  still stamps every write with `DateTime.now().toUtc()`
  (`drift_planning_mutation_store.dart`), and the S12 storage accounting is
  content-derived and time-independent, so neither slice moves the trigger
  condition closer. The characterization probe
  (`test/offline/adversarial/clock_skew_probe_test.dart`) and the injectable `now`
  seam on `PlanningMutationReconciler` both still stand unchanged. Decision recorded
  in `docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md` (Update, 2026-08-02).
- `LF-T5` — **deferred with a stated trigger condition (new deferred doc; this
  finding had none before).** Finer merge granularity (incremental/partial sync) is
  a sync-protocol change, out of Phase 4's remit of making offline durable and
  bounded rather than reducing divergence. What Phase 4 did instead: the S12
  mutation budget (`local_storage_budget.dart`) caps how much unsynced intent can
  accumulate, so the conflict surface can no longer grow without limit; the S12
  footprint monitor surfaces the pending mutation count and storage-pressure level
  in the unified sync overview (`unified_sync_providers.dart`), making a long
  offline span visible before reconnect turns it into a pile of conflicts; and the
  S12 squash contract suite fixed a real defect found while specifying the budget —
  four mutation fold paths (`sessionRename`, `sessionDelete`, `sessionItemDelete`,
  one `planEdit` path) were letting a later local edit's base version overwrite the
  first-captured one on fold, which could silently suppress a real OCC conflict.
  Divergence itself is unchanged, but it is now correctly detected and bounded
  where before this phase it was neither. See
  `docs/deferred/2026-07-31-occ-divergence-lf-t5.md` for the full analysis and the
  trigger condition (the S12 mutation warn threshold firing for real users, or a
  future slice introducing field-level merge for an independent reason).
- `LF-T2` — **deferred with a stated trigger condition (new deferred doc; this
  finding had none before).** The finding's own text splits into two halves: the
  "decouple local access from live session validity" half was already delivered by
  LF-T1/ADR-020; the refresh-token TTL hard wall itself is unchanged and is not
  fixable client-side, since it is a property of the auth provider's token
  lifetime/session policy configured on the hosted Supabase project, not a value
  this repository controls. Writing the deferred doc required establishing what a
  user actually loses once that TTL is exhausted while offline, rather than
  trusting the original "1 week ceiling" framing: `AppAuthController` maps the
  resulting `null` session to `sessionExpired`, not `signedOut`
  (`app_auth_controller.dart:168-206`), and both
  `PlanningSyncController.handleSessionExpired` and
  `SongCatalogController.handleSessionExpired` reset only transient sync state,
  leaving the projection and cache untouched
  (`planning_sync_controller.dart:255-263`,
  `song_catalog_controller.dart:322-325`) — no read or write path in the app gates
  on live session validity. The loss is to **sync only**: cached data stays fully
  readable and new edits keep queuing locally, but pushing pending mutations and
  pulling remote changes stays blocked until the user completes an interactive
  re-auth, which itself requires connectivity. See
  `docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md` for the full analysis and
  the trigger condition (a product commitment to a continuous offline span longer
  than the configured refresh-token TTL, or a decision to extend/restructure that
  TTL on the Supabase side).

Every LF-T* finding is now **fixed** (LF-T1, LF-T3, LF-T4, LF-T7), **validated**
(LF-T8), or **deferred with a stated trigger condition** (LF-T5, LF-T6, LF-T2) —
none remain open or partial. LF-T2's non-destructive-expiry half was fixed via
LF-T1; its residual, the refresh-token TTL hard wall, now has a deferred doc with
a stated trigger condition rather than being called out as the one id this review
could not place cleanly into a closed state.

**Status (2026-08-04, PR #64 review remediation)**:

The PR #64 review of the offline-durability-phase4 slice (itself reviewing the
LF-T3/LF-T4 work recorded in the 2026-07-30 status block above) found the ADR-028
recovery guarantee narrower than stated, not wrong in direction. Three findings,
`docs/specs/2026-08-04-storage-recovery-boundary-and-budget-admission.md`:

- **P1a** — `SongCatalogEvictor.evictDroppable()` was reachable from exactly one
  write path, `BudgetedPlanningMutationStore._guardedWrite`. Song mutation
  writes, catalog snapshot replacement, and planning projection writes went
  straight to Drift, so a storage failure on any of them surfaced a raw Drift
  exception instead of the typed `LocalStorageWriteFailure` ADR-028 claimed for
  local writes generally.
- **P1b** — the budget's measure-check-write sequence was not serialised, so
  concurrent `record*` calls for different aggregates in the same context could
  all measure the same pre-write footprint and all pass, overshooting the
  documented "at most one mutation past the threshold" bound.
- **P2** — `recordSessionDelete`/`recordSessionItemDelete` were budget-guarded
  like every other write even when they would *shrink* the store by collapsing
  a still-pending create, so an exhausted budget could refuse the very delete
  that would have freed room for it.

- `LF-T4` — **stays fixed, now on the accurate basis instead of the broader one
  originally claimed.** P1a is closed: the eviction-once/retry-once/typed-failure
  policy is now `LocalStorageWriteRecovery.guard`, one shared boundary injected
  into `DriftSongCatalogStore` and `DriftPlanningLocalStore` the same way
  `onStorageFootprintChanged` already was, so every local write that can grow
  stored bytes gets the same recovery — not only planning mutation `record*`
  calls. Two more exceptions needed the `LocalStorageDomainRejection` marker so
  the shared guard does not misreport them as storage pressure:
  `LocalSongSlugConflictException`, and `PlanningProjectionAbortedException` — a
  cooperative-cancellation signal a superseded projection refresh throws, not a
  failure, already caught explicitly by `PlanningSyncController`. Pinned by
  `test/application/storage/local_storage_write_recovery_test.dart` (the
  boundary itself) and the new `DriftPlanningLocalStore storage recovery (D1)` /
  `DriftSongCatalogStore storage recovery (D1)` groups in
  `test/offline/planning/planning_local_store_test.dart` and
  `test/offline/song_catalog/song_catalog_store_test.dart` (fault-injected
  recovery on `replaceActiveProjection`, `upsertSyncedPlan`,
  `upsertSyncedSession`, `upsertSyncedSessionItem`, `saveSongMutation`,
  `replaceActiveSnapshot`, and `reconcileSyncedSong` — every write path the
  guard covers now has a dedicated fault-injection recovery test). Native-only
  verification is unchanged; `docs/deferred/2026-06-29-web-offline-e2e.md`
  stays open. ADR-028 D8.
- `LF-T3` — **stays fixed, with P1b and P2 now closed.** The measure/check/
  delegated-write sequence runs inside a per-`(userId, organizationId)` FIFO
  write queue, so the documented overshoot bound holds under concurrency
  without one user/organization's writes blocking another's (ADR-028 D9).
  `recordSessionDelete`/`recordSessionItemDelete` now read the target
  aggregate's existing mutation and admit the write regardless of budget when
  it collapses a still-pending create, deciding from store state rather than
  the method name, so an exhausted budget can no longer trap a store that is
  actually shrinkable (ADR-028 D10). Pinned by new tests in
  `test/application/planning/budgeted_planning_mutation_store_test.dart`: a
  three-way concurrent-write race against a budget that admits only one lands
  exactly one success; two different `(userId, organizationId)` contexts do not
  block each other; a collapsing `recordSessionDelete`/`recordSessionItemDelete`
  succeeds at an exhausted budget; and a non-collapsing `recordSessionDelete`
  still stays refused at that same exhausted budget.

**Status (2026-08-04, PR #64 second re-review round)**:

A more targeted re-review of the same PR #64 diff, after the remediation
above had already landed, found two further gaps in the same two decisions
(D1 and D2 of
`docs/specs/2026-08-04-storage-recovery-boundary-and-budget-admission.md`),
both scoped to `BudgetedPlanningMutationStore.saveSyncAttemptResult`. Closed
by commits `ba62067`, `dc6a401`, `2b84978`, `39da44f`.

- **D1 gap** — the shared recovery boundary (D8 above) never reached
  `saveSyncAttemptResult`, even though it can grow the stored record
  (`errorCode`/`errorMessage`) exactly like the writes D1 already covered. A
  storage failure on it surfaced the raw exception instead of a typed
  `LocalStorageWriteFailure`. This one write matters more than an ordinary
  D1 gap: `saveSyncAttemptResult` is the durable marker
  `PlanningMutationSyncController._run` writes immediately after a
  successful remote send, so an unrecovered failure leaves the record
  `pending` and the next sync resends a mutation the backend already
  accepted — an ADR-019 exactly-once violation reached through a storage
  failure rather than a sync-logic bug.
- **D2 gap** — the per-context write queue (D9 above) serialised the nine
  `record*` admissions against each other, but not against
  `saveSyncAttemptResult`, `retryMutation`, or `clearMutation`. That left a
  race the D9 remediation's own language claimed was closed: a `record*`
  call's collapse decision (an early `readMutation`) and the delegate's own
  re-check of the same aggregate (a late `readMutation`, inside its own
  transaction) are two separate reads, and an unqueued `clearMutation` —
  exactly what sync calls for that aggregate immediately after a mutation is
  accepted — could land between them, so the delegate found nothing to
  collapse and wrote a brand-new delete row that had never passed a budget
  check. A falsification test reproduced this deterministically against a
  Completer-gated fake delegate.

Both are now closed:

- `saveSyncAttemptResult` is routed through `LocalStorageWriteRecovery.guard`
  via a new `_recoveredWrite` helper, with deliberately no budget admission
  (refusing it would strand the exactly-once marker it exists to protect).
- `saveSyncAttemptResult`, `retryMutation`, and `clearMutation` all now join
  the same per-context `_writeQueue` the nine `record*` admissions use, via a
  shared `_enqueue` helper — `_queuedWrite` for the two that only need
  ordering, `_recoveredWrite` for the one that also needs recovery.

Pinned by `test/application/planning/budgeted_planning_mutation_store_test.dart`:
a `saveSyncAttemptResult` is never refused for budget reasons test; a
`BudgetedPlanningMutationStore.saveSyncAttemptResult recovery (finding 1)`
group covering both the evict-once/retry-once/typed-failure path and the
transient-failure-recovers-on-retry path; and "the collapse race" test,
which fails against the pre-fix unqueued writes and passes after. See
ADR-028 D3 (corrected), D8 and D9 (both extended), and
`docs/specs/2026-08-04-storage-recovery-boundary-and-budget-admission.md`'s
"Second re-review round" section for the full account.

**Status (2026-08-05, PR #64 sync-snapshot-identity remediation, planning
half)**:

The same second re-review round also found the most serious defect in this
phase: `PlanningMutationSyncController._run` reads a snapshot of a pending
mutation, sends it, and awaits the backend outside the per-context write
queue (deliberately — holding a local write lock across a network call
would block every local edit for the duration of a sync). On success it
writes `saveSyncAttemptResult(..., accepted)` and later `clearMutation`,
both keyed only by aggregate identity, never checking that the local row is
still the one that was sent. Because `CachedPlanningMutations` folds
repeated intent into one row per aggregate, a local edit landing on the
same aggregate during that remote wait lands in the very row the sync is
about to mark accepted and delete — the user's later edit is destroyed,
never sent, with no error, no conflict, and no trace. Confirmed by a test
against the pre-fix code: the mutation was read back as `null` (deleted
outright by the unconditional `clearMutation`) after the race, not merely
stale. `docs/specs/2026-08-05-sync-snapshot-identity.md`, ADR-030.

Closed for the planning half (the song/catalog half of the same spec landed
separately — see the 2026-08-05 song/catalog status block below):

- **D1** — `CachedPlanningMutations` gains a `localRevision` integer column
  (schemaVersion 5 → 6), incremented by the store on every local write to a
  row (every `record*` write, `retryMutation`, `saveSyncAttemptResult`).
  Local bookkeeping only — never sent to the backend, never part of OCC, and
  unrelated to `baseVersion`/`version`, which track the server's view. Not
  derived from `updatedAt`: LF-T6 already documents the device clock as
  unanchored, and two writes in the same millisecond would collide anyway.
- **D2** — `saveSyncAttemptResult` and `clearMutation` each gained an
  optional `expectedRevision` parameter. The sync captures a mutation's
  `localRevision` at snapshot time and passes it back in; both writes are
  now targeted `UPDATE`/`DELETE` statements with `WHERE localRevision = ?`
  in the statement itself, not a preceding `SELECT` compared in Dart, which
  would reopen the same race. Only the accepted-status write and the clears
  that follow it are gated — the failure-status writes in the same
  controller never claim the backend accepted anything, so they are out of
  this specific defect's scope.
- **D3** — a stale outcome (the row's revision moved) is not an error:
  `saveSyncAttemptResult` returns the new revision or `null`, `clearMutation`
  returns `bool`; neither throws, marks a conflict, or retries. The
  controller checks the return value and moves on — the row is already
  exactly where it needs to be, since the local write that caused the
  staleness already reset `syncStatus` to `pending`.

A related but distinct gap surfaced during implementation and was
deliberately left open, not fixed here: `recordPlanEdit` folding onto a
`planCreate` row copies forward whatever `syncStatus` that row currently has
rather than resetting it to `pending`, so an edit landing in the narrow
window where a `planCreate` mutation is `accepted` but not yet cleared (the
same window ADR-019's LF-1 already names) keeps the row `accepted` with
unsent content — the `localRevision` gate still protects the row from
deletion, but a later sync's durable-marker branch could still reconcile the
unsent content as if it were server-confirmed. See ADR-030's "Known
Follow-Up" section.

Pinned by
`test/offline/adversarial/planning_sync_snapshot_identity_test.dart`
(the gated-remote-call race, watched failing before the fix, and a
companion unchanged-case regression check), the
`PlanningMutationStore.localRevision` group in
`test/offline/planning/planning_mutation_store_test.dart` (monotonic
increment across every local write path, including the fold and a status
write, and the conditional-write contract itself), and an extended
`planning_migration_test.dart` (a genuine pre-migration v5 database, built
by hand against the schema Drift generated before this column existed,
gains it on open with a sane starting value and keeps its pending row
intact). See ADR-030 for the full account.

**Status (2026-08-05, PR #64 sync-snapshot-identity remediation, song/catalog
half and fold-status follow-up)**:

The song/catalog half of the same finding closed the same day, same shape:
`SongMutationSyncController._runSync` reads a snapshot of a pending song,
sends it, and awaits the backend; on success `reconcileSyncedSong` deleted
the mutation row and reconciled the cached snapshot unconditionally, keyed
only by song identity. A local edit to the same song during that remote wait
was destroyed the same way — confirmed by the same style of gated-`Completer`
test against the real `DriftSongCatalogStore`/`DriftSongMutationStore`, not a
fake.

- **D1** — `CachedCatalogSongMutations` gains the identical `localRevision`
  integer column (schemaVersion 2 → 3), incremented by
  `DriftSongCatalogStore._saveSongMutation` — the store's one write path for
  the mutation table's content, so every local writer (including the status
  write `DriftSongMutationStore.saveSyncAttemptResult` makes through it)
  advances it through a single call site.
- **D2/D3** — `reconcileSyncedSong` gained an optional `expectedRevision` and
  now returns `Future<bool>` rather than `void`. Because song has no
  separate accept-status write to gate the way planning's
  `saveSyncAttemptResult` is gated — the delete and the summary/source
  snapshot upsert are one combined operation — the gate lives on the
  mutation row's own `DELETE ... WHERE localRevision = ?`; when it removes
  zero rows, the *entire* reconcile is skipped, not merely the delete, and
  `false` reports the stale outcome rather than throwing. `bool` (not
  planning's `int?`) is the complete answer here because there is no
  intermediate accept-write revision left to report back. Deliberately still
  unconditional: `clearSongMutation` (the discard path, no remote round trip
  to race) and the `pendingDelete` → `deleteSong` branch in
  `_applySuccessfulSync` (a converged delete has no newer content for a fold
  to preserve).

Pinned by
`test/offline/adversarial/song_sync_snapshot_identity_test.dart` (the
gated-remote-call race, watched failing before the fix, and a companion
unchanged-case regression check), the `SongCatalogStore.localRevision` group
in `test/offline/song_catalog/song_catalog_store_test.dart` (monotonic
increment across the single `saveSongMutation` write path, and the
conditional-`reconcileSyncedSong` contract itself, including that a stale
call skips the snapshot upsert too), and an extended
`song_catalog_migration_test.dart` (a genuine pre-migration schemaVersion-2
database, built by hand via raw `sqlite3` against the exact `CREATE TABLE`
text Drift generated before this column existed, gains it on open with a
sane starting value and keeps its pending row intact).

Separately, the fold-status gap ADR-030 flagged as a known follow-up on the
planning half (above) was resolved the same day
(`a98c496`/`8f45988`): a fold that carries an existing mutation row forward
with `copyWith` must not carry the row's current `syncStatus` along with it,
or a row `accepted` but not yet cleared (the ADR-019 durable-marker window)
stays labelled `accepted` after new, unsent content lands in it, and a later
sync's durable-marker branch reconciles that content as server-confirmed
without ever having sent it. Fixed in every planning fold write that carries
a row forward via `copyWith`: `recordPlanEdit` onto a pending `planCreate`,
`recordSessionRename` onto a pending `sessionCreate`, and both reorder-trim
folds (`_removeSessionFromPendingReorder`/
`_removeSessionItemFromPendingReorder`); each now resets `syncStatus` to
`pending` and clears any stale `errorCode`/`errorMessage`. `retryMutation`
and `saveSyncAttemptResult` are deliberately untouched — they compute
`syncStatus` as their entire purpose, not as a side effect of carrying
content forward. Verified, not assumed, that the song side has no equivalent
gap: `SongSyncStatus` has no two-phase accepted-but-not-cleared marker, so
the window this follow-up closes does not exist there. Pinned by the
`PlanningMutationStore content folds reset status (ADR-030 follow-up)` group
in `planning_mutation_store_test.dart` (all four fold paths, plus a
stale-error-does-not-survive-a-fold case) and a controller-level test in
`planning_sync_snapshot_identity_test.dart` proving the edited content is
actually sent on the next sync rather than skipped by the durable-marker
shortcut. See ADR-030 (now covering both domains and this follow-up) for the
full account.

**Status (2026-08-05/06, PR #64 in-flight create cancellation remediation,
both domains)**:

A follow-up finding on the same PR #64 diff: the `localRevision` gate above
(sync-snapshot-identity) assumes newer local intent arriving during a remote
round trip leaves the pending row at a *higher* revision, which holds for an
edit but not for a delete of a still-pending create, since ADR-028 D10's
collapse admission physically removes the row instead of bumping it. If the
create's own send was in flight at the exact moment of that delete, the
collapse destroyed the only local record of the delete before the create's
outcome was known — if the create then succeeded, the object existed on the
server with nothing left locally that would ever delete it. A distinct second
harm rode along on the planning side: `saveSyncAttemptResult`/`retryMutation`
threw `StateError` for a row that had vanished this way, and because `Error`
is rethrown untouched by the storage-recovery boundary (by design), that
escaped the sync controller's loop uncaught and killed the entire sync pass,
discarding every unrelated mutation or song queued behind it.
`docs/specs/2026-08-06-in-flight-create-cancellation.md`.

Closed, across both domains:

- **D1** — the sync now writes a durable `sending` marker to a candidate's
  row immediately before its remote call, the mirror of the `accepted`
  marker ADR-030/ADR-019 already write immediately after. Reuses the
  existing free-text `syncStatus` column, no migration. A record left
  `sending` by a crash carries the same reach-or-didn't-reach-the-backend
  uncertainty the `accepted` marker exists to bound, so it is treated as
  pending and resent on the next pass rather than skipped or stranded.
- **D2** — deleting a `sending` create (planning: `sessionCreate`/
  `sessionItemCreateSong`; song: `pendingCreate`) keeps the row as a
  `cancelling` tombstone at a bumped revision instead of physically
  collapsing it. Every other state still collapses exactly as before
  (ADR-028 D10 unchanged). `cancelling` is excluded from every
  actionable/merged read and from the sync candidate filter, so the
  tombstone disappears from the UI immediately, before its create's outcome
  is even known.
- **D3** — once the in-flight create's remote call concludes, the tombstone
  resolves in one atomic read-check-write
  (`DriftPlanningMutationStore.resolveCancelledCreate` /
  `DriftSongCatalogStore.resolveCancelledSongCreate`): a succeeded create
  converts it to a real pending delete (rebased on the backend-assigned
  version) that the next sync sends; a failed create discards it outright
  with no backend call, exactly as a plain collapse would have. Both
  controllers resolve the tombstone *before* the unconditional
  failure-status write that follows a failed call — an ordering trap found
  while wiring this: that status write is deliberately ungated by revision,
  so writing it first would clobber `cancelling` and strand the tombstone
  permanently, since the resolver only acts on a row still marked
  `cancelling`.
- **D4** — the vanished-record `StateError`s above are now a non-throwing
  "did not apply" result, in the vocabulary D3 of ADR-030 already
  established for a stale revision: `saveSyncAttemptResult` returns
  `null`/`false`, `retryMutation` returns `Future<bool>` instead of
  `Future<void>`. The sync loop's existing stale-revision skip now covers a
  vanished row for free, so the rest of the pass is no longer at risk.
  `SongLibraryService.deleteSong`/`updateSong` and
  `SongMutationSyncController._requireSong` deliberately keep throwing for a
  target absent from local storage — single-record, user-initiated calls
  with no batch behind them to protect, pinned by regression tests so this
  scope does not silently widen later.

Two gaps surfaced during implementation, beyond what the spec's Decisions
section named:

- **The accepted-but-uncleared window (planning only)** — the identical
  defect one state over: a create already `accepted` (ADR-019's own
  durable-marker window) but not yet locally cleared has no live remote call
  to race, so `recordSessionDelete`/`recordSessionItemDelete` convert it
  straight to a real pending delete with no tombstone needed.
  `baseVersion` uses the existing `existing.baseVersion ?? draft.baseVersion`
  fallback every other delete path already uses, deliberately, not as a
  placeholder: the accept write never persists the backend-assigned version
  onto the row, so a stale value is left to fail safe into a visible,
  recoverable `conflict` on the backend's own version guard rather than the
  code guessing. Verified absent on the song side (`reconcileSyncedSong` has
  no accept-then-clear step for a delete to land between), not assumed.
- **The `updateSong` fold gap (known limitation, not fixed)** —
  `SongLibraryService.updateSong`'s status ternary does not treat `sending`
  as create-like the way it treats `pendingCreate`, so an edit landing during
  the `sending` window becomes `pendingUpdate` rather than folding into the
  create. Traced, not merely suspected: not data loss
  (`resolveCancelledSongCreate` no-ops on a non-tombstone row, so the edit
  survives and syncs next round), only an extra create-then-update round
  trip where planning's fold handling would have carried it in one create.
  Left deliberately out of scope, recorded rather than fixed.

Pinned by `test/offline/adversarial/planning_in_flight_create_cancellation_test.dart`
and `test/offline/adversarial/song_in_flight_create_cancellation_test.dart`
(the tombstone-survives/converts/resolves-locally/no-regression/crash-recovery
shapes for both domains, plus the accepted-window case for planning, all
driven against the real Drift stores with the remote call gated on a
`Completer`); `test/offline/adversarial/planning_vanished_record_sync_test.dart`
and `test/offline/adversarial/song_vanished_record_sync_test.dart` (D4,
watched failing pre-fix with the exact predicted `StateError` escaping the
sync loop and aborting records/songs queued behind the vanished one); the D4
store-level "row not found" coverage in `planning_mutation_store_test.dart`
and `song_catalog_store_test.dart`; and the deliberate-scope regression tests
in `song_library_service_test.dart`. See ADR-030's in-flight create
cancellation follow-up for the full account.

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

**Status (2026-07-30, offline-durability-phase4 slice)**:
- `LF-7` — **fixed on the song side; the finding's file pointer was stale.** The finding
  as recorded pointed at `planning_mutation_sync_controller.dart:92,109`. By the time
  this slice started that pointer was already wrong: the planning-side refactors in
  PR #62 and PR #63 had made `PlanningMutationSyncController.discardMutation` clear the
  mutation before attempting any sync, so the planning half of LF-7 was resolved as a
  side effect of unrelated work, not by this slice. The live violation was on the
  **song** side, and it was worse than the original finding described:
  `SongMutationSyncController.discardMine` fetched the server record before touching
  local storage, so an offline discard did not merely fail — the connectivity error fell
  through to the generic handler and wrote `SongSyncStatus.conflict` onto the record the
  user asked to throw away, and `UnifiedDiscardController.discardAll` swallowed that
  per entry, so nothing reached the user at all. `discardMine` is now local-first: a
  pending create or a remote-deleted conflict deletes the local song, and any other
  state (pending update, pending delete, conflict) clears the mutation so the read falls
  back to the cached catalog snapshot — the last known server copy — with no network
  call required either way, and a discard never writes `SongSyncStatus.conflict`. A
  best-effort catalog refresh follows the local discard to pick up server freshness; its
  failure is swallowed and never undoes the completed discard. Accepted trade-off:
  discarding a **pending delete** now clears the mutation without confirming the song is
  still live on the server, so if it really was deleted remotely and the cached snapshot
  is stale, the song can reappear locally until the next successful refresh removes it
  again — a bounded, self-healing window. Retry stays online-only, since it genuinely
  needs the backend, but now reports rather than failing silently:
  `PlanningMutationSyncController.retryMutation` re-reads the record after syncing and
  throws `PlanningMutationSyncException` when the sync left a `connectivityFailure`
  error code, so a user-initiated retry no longer returns as if it had worked;
  background `syncPendingMutations` keeps swallowing connectivity failures, since
  finding no network in the background is routine, not an error worth surfacing. Guarded
  by `apps/lyron_app/test/application/song_library/song_mutation_sync_controller_test.dart`
  and `apps/lyron_app/test/application/planning/planning_mutation_sync_controller_test.dart`.
- `LF-9` — **fixed; no live caller today.** `getPlanDetailBySlug` and
  `getPlanSummaryBySlug` now read the actionable mutation set once per call, resolve the
  slug against pending `planCreate` mutations first (so a plan created offline, whose
  slug exists only in its pending mutation, stays findable) and otherwise via
  `PlanningLocalStore.readPlanSummaryBySlug`, and never fall back to a full plan
  listing. This is a correctness fix to an interface method, not a measured performance
  win: nothing in `lib/` watches `planningPlanBySlugProvider` or
  `planningPlanDetailBySlugProvider` today — the slug routes resolve through
  `planningPlanListProvider` and fetch detail by id — so the path being fixed has no
  live caller. Guarded by
  `apps/lyron_app/test/application/planning/planning_local_read_repository_test.dart`.

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
| ~~UX-1~~ | ~~Mobile reader wraps long lyric lines mid-word ("...porciká" / "m,") and the chord drifts onto the wrong syllable~~ **Done (ui-decomposition-phase2).** The cause was not text wrapping: ChordPro splits a lyric line at chord positions, so a chord inside a word yields two segments with no whitespace between them, and the line's `Wrap` was free to break there. Adjacent segments of the same word are now grouped, and the fit estimator packs the same groups. | reader @375px |
| ~~UX-2~~ | ~~Plan `scheduled_for` edited as a raw ISO-8601 string field (`2026-04-05T08:30:00.000Z`), no date/time picker~~ **Done (ui-decomposition-phase2).** Both the edit **and** the create dialog used the raw field; both now use a shared date/time picker that stores UTC and displays local. | edit-plan dialog |
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

**Update (2026-07-27, ui-decomposition-phase2)**: the **estimate/render consistency** half is
now covered by `test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart`.
It pumps the real compact surface at 375 px, asserts the fit calculator and the render grid
receive the same padding-adjusted dimensions, and bounds the gap between the estimated and
the actually rendered content height (measured at 2.0% on an eleven-line, four-section
fixture; bounded at 5% relative plus one `lyricRowHeight` per line absolute). The bound was
verified to bite by inflating `chordRowHeight` 50% and watching the test fail. The estimator
itself was corrected in the same slice: it now packs the same word groups the renderer lays
out, charges a chord row for every wrapped run rather than once per line, adds the
renderer's run spacing, and no longer reserves 24 px the renderer never reserves.
The fit-layout **performance** regression test, and the accessibility/contrast and
screen-reader gaps, remain open.

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
   harness half is deferred (`docs/deferred/2026-06-29-web-offline-e2e.md`). LF-T4 and
   LF-T6 were characterized via probes at the time; LF-T4 has since been fixed
   (offline-durability-phase4 slice, ADR-028, see §6.1), while LF-T6 remains deferred
   for the full fix (`docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md`). The two
   new integration suites have since been verified against a live Supabase stack (see
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
state, rather than relying on the transient `WidgetRef`/`context.mounted`), and planning
reorder optimistic-overlay cleanup. Per `docs/deferred/README.md`, these become priority
work when a slice re-enters their area. ~~SEC-4 (song shadow fields)~~ **Done
(read-boundary-and-derived-song-metadata)** — see ADR-027.

## 12. Dependencies (DX-1)

Direct deps behind latest: `file_picker` 8.3.7 → 11.0.2 (**3 majors**),
`flutter_riverpod`/`riverpod` 2.6.1 → 3.3.2 (1 major, *resolvable* via constraint bump),
`go_router` 16.3.0 → 17.3.0 (1 major), `supabase_flutter`/`gotrue`/`supabase`
2.12/2.18/2.10 → 2.15/2.22/2.13 (minor — **auth, security-relevant**). No known CVEs in
the audit output; the risk is staleness. **DX-2**: no `pub`-audit or coverage gate in CI.

**Status (2026-07-30, security read-boundary phase 3, DX-1 and DX-2): fixed, with
one item deferred.** The figures above were measured on 2026-06-22 and were stale
by the time the work ran; they were re-measured rather than trusted.

DX-1, in priority order rather than by version distance: `supabase_flutter`
2.12.0 → 2.16.0, which carries `gotrue` 2.18.0 → 2.26.0, `postgrest` 2.6.0 →
2.8.0, `realtime_client` 2.7.0 → 2.11.0 and `functions_client` 2.5.0 → 2.6.4;
`app_links` 6.3.2 → 7.0.0, which the review did not list at all and which carries
the invite deep-link path; `go_router` 16.3.0 → 17.3.0; `file_picker` 8.3.7 →
11.0.2; and a lockfile refresh of thirty-five in-constraint packages including
`drift` 2.32.0 → 2.34.3. `app_links` is pinned to `^7.0.0` rather than 7.2.1
because 7.1.1 requires Dart SDK 3.12 and this toolchain is on 3.11.3.

`flutter_riverpod`/`riverpod` 3.x is **deferred** —
`docs/deferred/2026-07-30-riverpod-3-migration.md`. The mechanical migration was
completed and then reverted: Riverpod 3 wraps provider errors, which breaks nine
tests on the song reader's error paths, one of them a production-visible symptom.
That is the surface ADR-023/024 stabilised, so it needs its own slice.

DX-2: `./scripts/coverage-gate.sh` ratchets line coverage from the measured 72%,
`./scripts/dependency-audit.sh` fails on published advisories, retracted or
discontinued packages and on a lockfile behind its own constraints, and both run
from `./scripts/verify.sh`. A `web_build` job was also added to
`.github/workflows/ci.yml`: no job built the web target before, which is how the
`Platform.environment` break in `276a052` reached `main`.

## 13. Prioritized Roadmap

**Quick wins (1-2 days)**
- ~~SEC-5: add `unique(session_id, song_id) where item_type='song'`.~~ **Done (PR #57).**
- ~~SEC-3: `set search_path = public` on the two remaining invoker-rights helpers (`has_capability`, `get_my_capabilities`); `current_organization_ids` already has it.~~ **Done (arch-spine-phase0-1).**
- ~~LF-8: replace silent `?? ''`/`?? 0` with invariant asserts / explicit rejection + tests.~~
  **Done (local-first-validation, PR #56).** The reconciler now throws a typed
  `ReconcileFieldError` instead of coercing; see §6.2 status block.
- ~~UX-3: replace the copyrighted default song body with a non-copyrighted placeholder/hint.~~ **Done (arch-spine-phase0-1).**
- A11y: add the missing `semanticLabel`/`Semantics` on the few non-tooltip surfaces.

**Medium (1-2 weeks)**
- ~~LF-T1: make session expiry non-destructive (the "indefinite offline" keystone).~~
  **Done (PR #55).** ~~Residual: different-user re-auth live dialog wiring (deferred).~~
  **Done (offline-durability-phase4, S14, ADR-029).**
- ~~LF-1 + LF-3: idempotency key / accepted-but-uncleared marker + single-flight guard.~~
  **LF-1 validated, already shipped under ADR-019 (local-first-validation, PR #56).
  LF-3 fixed for the song path** (planning side was already guarded by ADR-019);
  see §6.2 status block.
- ~~LF-2: hoist refresh out of the per-mutation loop (sync all, then refresh once).~~
  **Validated, already shipped under ADR-019 (local-first-validation, PR #56).** See
  §6.2 status block.
- ~~LF-4: surface failed local edits in the main UI instead of silently reverting.~~
  **Validated, already shipped under ADR-019 (local-first-validation, PR #56).** See
  §6.2 status block.
- ~~ARCH-1: split `providers.dart`; extract `PlanningMutationReconciler`.~~ **Done (arch-spine-phase0-1).**
- ~~UX-1: reader line-wrap/chord-alignment on narrow widths; UX-2: date picker.~~ **Done (ui-decomposition-phase2).**
- ~~SEC-1: invite email-binding + rate limit + audit + ADR.~~ **Done (security-read-boundary-phase3).**
- ~~DX-1/DX-2: bump auth packages; add pub-audit + coverage gates.~~ **Done (security-read-boundary-phase3); riverpod 3 deferred.**

**Strategic (1+ month)**
- ~~LF-T3/LF-T4: mutation budget + storage eviction policy for indefinite offline.~~
  **Done (offline-durability-phase4).** Native-only verification; web/IndexedDB
  assumptions remain unverified (`docs/deferred/2026-06-29-web-offline-e2e.md`).
- ~~ARCH-2: aggregate-scoped invalidation.~~ **Done (arch-spine-phase0-1).**
- ~~ARCH-3: decompose plan_detail / song_editor.~~ **Done (ui-decomposition-phase2).**
- ~~SEC-4: backend-derived shadow metadata.~~ **Done (read-boundary-and-derived-song-metadata).**
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
