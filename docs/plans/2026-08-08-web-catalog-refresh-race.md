# Web Song Catalog Refresh Race — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** A signed-in web session loads the song catalog. The refresh trigger
survives the startup ordering in which the catalog controller is built before
auth restore completes.

**Architecture:** Three narrow changes, in dependency order. The controller
learns to coalesce by session identity instead of by presence (D1). The provider
stops firing a refresh under an unknown auth state (D2). The foreground signal
stops disarming the recovery timer on a pre-settle lifecycle sample (D3).

**Tech Stack:** Dart / Flutter, Riverpod 2 (NOT 3 — see Non-Goals), `flutter_test`.

**Spec:** `docs/specs/2026-08-08-web-catalog-refresh-race.md`

---

## Non-Goals, restated because this plan invites them

- Do **not** start the Riverpod 3 migration
  (`docs/deferred/2026-07-30-riverpod-3-migration.md`).
- Do **not** add browser/`chromedriver` test infrastructure
  (`docs/deferred/2026-06-29-web-offline-e2e.md`).
- Do **not** refactor `SongCatalogController._refreshCatalog`'s state machine.
  Only its trigger/coalescing seam changes.
- Do **not** touch the planning providers' trigger shape. They are already
  correct and serve as the reference.

---

## Task 1 — Session-scoped refresh coalescing (D1)

**Files:** `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`,
`apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart`

- [ ] Write failing tests first:
  - A refresh dispatched while `authSessionReader` returns `null`, followed —
    before the first future settles — by a refresh under a real session, results
    in exactly one `listSongs()` call on the remote repository and a populated
    catalog state.
  - Two refreshes under the *same* session identity while one is in flight still
    produce exactly one `listSongs()` call (coalescing preserved).
  - At most one follow-up refresh is queued per in-flight window: three
    differing-identity triggers during one in-flight refresh must not produce
    three follow-ups.
- [ ] Implement: record the identity (`AppAuthSession?.userId`) that the
  in-flight refresh started under. Same identity → return the in-flight future
  unchanged. Different identity → set a single pending-rerun marker and return a
  future that settles only after the follow-up refresh completes.
- [ ] The existing tests named *"explicit sign-out prevents an in-flight refresh
  from restoring cached authenticated access"* and *"a stale in-flight refresh
  still prevents overlapping refresh work after explicit sign-out"* must stay
  green **without modification**. If they cannot, STOP and report — that means
  the follow-up can resurrect access after sign-out and the design needs
  rethinking, not the tests loosening.
- [ ] `flutter test test/application/song_library/song_catalog_controller_test.dart` green.

## Task 2 — Provider refreshes only under a known auth state (D2)

**Files:** `apps/lyron_app/lib/src/application/song_catalog_providers.dart`, plus a
test under `apps/lyron_app/test/application/`

- [ ] Write a failing test: building `songCatalogControllerProvider` with an
  `AppAuthController` in `initializing` issues no `listSongs()` call; driving the
  same controller to `signedIn` afterwards issues exactly one.
- [ ] Implement: delete the trailing `unawaited(controller.refreshCatalog())`
  from the provider body. `handleAuthStateChanged(authController.state)` stays as
  the single construction-time trigger, matching
  `apps/lyron_app/lib/src/application/planning_providers.dart`.
- [ ] Confirm no other provider in `apps/lyron_app/lib/src/application/` fires a
  refresh outside `handleAuthStateChanged`. Report anything found; do not fix
  outside this file without saying so.
- [ ] `flutter test` green for the touched suites.

## Task 3 — Recovery timer survives a pre-settle lifecycle sample (D3)

**Files:** `apps/lyron_app/lib/src/application/song_library/app_foreground_state.dart`,
plus a test under `apps/lyron_app/test/application/song_library/`

- [ ] Write a failing test: a `SongCatalogController` whose `AppForegroundState`
  reports a non-`resumed` lifecycle value *before any* `didChangeAppLifecycleState`
  callback still schedules its periodic refresh once a session is available.
- [ ] Implement: `WidgetsBindingAppForegroundState` treats any lifecycle value
  observed before the first `didChangeAppLifecycleState` as foreground. After the
  first real callback, current behaviour is unchanged — a genuine background
  transition must still stop the scheduler.
- [ ] `flutter test` green for the touched suites.

## Task 4 — Documentation (AGENTS.md rule 2 and 4)

**Files:** `docs/specs/2026-08-08-web-catalog-refresh-race.md`,
`docs/architecture/decisions/ADR-031-session-scoped-catalog-refresh.md`,
`docs/deferred/2026-06-29-web-offline-e2e.md`

- [ ] Add ADR-031 recording D1 as a durable invariant: refresh coalescing in the
  catalog controller is scoped to session identity, and a trigger arriving under
  a new identity is never dropped. Follow the format of the neighbouring ADRs.
- [ ] Flip the spec's `Status:` to `Implemented`.
- [ ] Append a dated note to `docs/deferred/2026-06-29-web-offline-e2e.md`: this
  bug was a web-only *behavioural* failure that the existing `web_build`
  compile gate could not catch, and it is evidence for the trigger condition
  recorded there. Do not remove or resolve the deferral.

## Task 5 — Verification

- [ ] `./scripts/run-tests.sh` (or the repository's standard suite entry point) green.
- [ ] `flutter analyze` clean for `apps/lyron_app`.
- [ ] Manual web check: rebuild `apps/lyron_app` for web against local Supabase,
  load with a real session, confirm the seeded songs render and `GET
  /rest/v1/songs` appears in the network log.
