# Plan: Paged Remote Pulls

- Spec: `docs/specs/2026-10-12-paged-remote-pulls.md` (PG1–PG11, H/S/C/P/PC/R
  acceptance criteria)
- Branch: `fix/paged-remote-pulls` (from `main` at `4dbd9de`)
- Execution: subagent-driven. Implementer Sonnet 5.5 per task, task review
  Haiku 4.5. One adversarial Opus 5.5 whole-diff review before the PR.

## Rules for every task

- Paths are relative to `apps/lyron_app/` unless they start with `docs/` or
  `scripts/`.
- Tests first. Run the new tests and watch them fail for the stated reason
  before touching `lib/`.
- After every task run the **full** suite and the analyzer:
  `flutter test` and `flutter analyze` in `apps/lyron_app/`. Both must be
  clean before the task's commit. Integration tests under `test/integration/`
  that need `SUPABASE_URL` are skipped locally; they must still compile.
- If `scripts/dependency-audit.sh` fails, fix it in a separate
  `chore(deps)` commit with a targeted `flutter pub upgrade <pkg>`.
- **Stop and report** (do not improvise) if:
  - an existing test fails and the change is not covered by the spec's
    "Intentional test changes";
  - a production caller of a method PG9 removes turns up;
  - a backend migration would be needed;
  - a code excerpt quoted here does not match the real file.
- Every paged PostgREST query passes `ascending: true` to `order()` (PG1).
- Reviewers: do not review the commit trailer lines.

## Task 1 — the keyset paging helper (PG1, PG2; H1–H10)

**Test first:** `test/shared/keyset_paging_test.dart`, one test per H1–H10.
Use an in-memory fake fetcher that records every `(after, limit)` call and
serves scripted pages. H3 simulates a server cap: a fetcher that serves at
most `cap < limit` rows per page from a sorted list, with keyset semantics.

**Implement:** `lib/src/shared/keyset_paging.dart` with exactly the API in
spec PG2:

- `KeysetPageFetcher<R, K>`, `readAllKeysetPages<R, K>`, `compareUuidKeys`;
- `PagedReadContractException` (`stream`, `pageIndex`, `reason`:
  `PagedReadContractViolation.keyNotIncreasing | pageOverLimit`; `toString`
  without keys or row data);
- `PagedReadAbortedException` (`stream`).

`compareUuidKeys`'s doc comment says it is valid only for Postgres `uuid`
columns and why (PG2). `pageSize <= 0` throws `ArgumentError`.

Commit: `feat(sync): add keyset paging helper for full pulls (PG1, PG2)`.

## Task 2 — catalog stream in the song repository (PG3, PG4, PG10; S1–S4)

**Test first:** `test/infrastructure/song_library/supabase_song_repository_test.dart`,
new group "fetchCatalog (PG3, PG4)": S1–S4. Add a reusable fake in
`test/support/keyset_pages.dart`:

```dart
/// Serves [rows] as keyset pages ordered by `id` (uuid order), the way
/// PostgREST would for `order(id.asc).gt(id, after).limit(limit)`,
/// optionally capped at [cap] rows per page.
List<Map<String, dynamic>> keysetPage(
  List<Map<String, dynamic>> rows, {
  required String? after,
  required int limit,
  int? cap,
});
```

**Implement:**

- `lib/src/application/song_library/song_catalog_remote_repository.dart`:
  `SongCatalogPayload` and `SongCatalogRemoteRepository` exactly as spec PG3.
- `SupabaseSongRepository` also implements `SongCatalogRemoteRepository`.
  New typedef
  `SongCatalogPageFetcher = Future<List<Map<String, dynamic>>> Function({required String organizationId, required String? after, required int limit})`.
  The production fetcher:

  ```dart
  var query = client
      .from('songs')
      .select('id, slug, title, version, chordpro_source')
      .eq('organization_id', organizationId);
  if (after != null) query = query.gt('id', after);
  final rows = await query.order('id', ascending: true).limit(limit);
  ```

  `fetchCatalog` runs `readAllKeysetPages` (stream `songs`, key `id`,
  `compareUuidKeys`, page size 100 by default) and maps the rows to summaries
  and sources, sorted by title, then id.
- The production constructor gains `@visibleForTesting int catalogPageSize = 100`.
- In this task `.testing` gains an optional `fetchCatalogPage` and keeps the
  old parameters, so every existing caller still compiles. Task 3 removes
  them.

Commit: `feat(catalog): read the song catalog as one org-scoped keyset stream (PG3, PG4)`.

## Task 3 — the catalog controller uses the stream (PG3, PG6, PG7, PG8, PG9; C1–C6, R1)

**Test first** in `test/application/song_library/song_catalog_controller_test.dart`:
C1–C6. C3 uses a fake whose `fetchCatalog` reads two pages through the real
`readAllKeysetPages` with the given `shouldContinue`, and bumps the generation
(for example by `handleExplicitSignOut` or a context change already used by
existing tests) between the pages.

**Implement:**

- `SongCatalogController` takes `SongCatalogRemoteRepository remoteRepository`.
  The refresh body calls
  `fetchCatalog(organizationId: context.organizationId, shouldContinue: () => !_isStale(generation))`
  inside one span `song_catalog.fetch_catalog`, then keeps the existing
  empty-snapshot branch and the `replaceActiveSnapshot` call with
  `payload.summaries` / `payload.sources`. The `Future.wait` is gone.
- The catch block becomes `catch (error, stackTrace)` and starts with
  `if (_isStale(generation)) return;`. A `PagedReadContractException` is
  reported via `_observability.captureException(error, stackTrace, extra: {...})`
  (PG8) before the existing classification.
- Remove from `SupabaseSongRepository`: `implements SongRepository`,
  `listSongs`, `getSongSource`, `getSongSummaryBySlug`, the access-denied
  helpers, and the old typedefs and `.testing` parameters
  (`.testing({required SongCatalogPageFetcher fetchCatalogPage})`).
  Verify with `grep` that no `lib/` code calls them first (PG9 STOP rule).
- Migrate every test listed in spec "Intentional test changes":
  the `implements SongRepository` controller fakes, every
  `SupabaseSongRepository.testing` call site, and the sentry instrumentation
  test's span names.
- `test/integration/authenticated_song_reader_flow_test.dart`: replace the
  `listSongs` / `getSongSource` assertions with `fetchCatalog` for the demo
  organization (the foreign song id `33333333-3333-3333-3333-333333333336`
  must be absent), and add **R1**: `SupabaseSongRepository(client,
  catalogPageSize: 1)` returns the same ids and sources as the default.

Commit: `fix(catalog): refresh from one paged stream, no per-song reads (PG3, PG6–PG9)`.

## Task 4 — planning repository streams (PG5, PG6, PG9, PG10; P1–P7, R2)

**Test first** in `test/infrastructure/planning/supabase_planning_repository_test.dart`:
P1–P7. P2 uses one recording log shared by the three fetchers. P6 serves 1200
items for one session through `keysetPage(..., cap: 1000)`.

**Implement:**

- `SupabasePlanningRepository` implements only
  `PlanningRemoteRefreshRepository`. Remove `implements PlanningRepository`,
  `listPlans`, `getPlanDetail`, `getPlanSummaryBySlug`, `getPlanDetailBySlug`
  and their typedefs (PG9; grep `lib/` first).
- `PlanningRemoteRefreshRepository.fetchPlanningSyncPayload` gains
  `bool Function()? shouldContinue`.
- `.testing({required PlanningPageFetcher fetchPlanPage, required PlanningPageFetcher fetchSessionPage, required PlanningPageFetcher fetchSessionItemPage})`,
  with `PlanningPageFetcher` shaped like `SongCatalogPageFetcher`.
- Production fetchers (all `.eq('organization_id', organizationId)`, optional
  `.gt('id', after)`, `.order('id', ascending: true).limit(limit)`):
  - plans: `id, organization_id, slug, name, description, scheduled_for, updated_at, version, content_version`;
  - sessions: `id, plan_id, slug, name, position, version`;
  - session_items: `id, session_id, position, song:songs(id, slug, title)`.
- `fetchPlanningSyncPayload` reads plans, then sessions, then items (each
  through `readAllKeysetPages`, streams `plans` / `sessions` /
  `session_items`, page size 500 by default via the production constructor's
  `@visibleForTesting int pageSize = 500`), drops orphans (PG5), and builds
  the payload in today's order. Replace the I7 comment: drop "Known limit",
  state the three-stream order and the orphan rule.
- Integration tests that called `getPlanDetail` / `listPlans` /
  `getPlanSummaryBySlug` on `SupabasePlanningRepository`
  (`plan_and_session_flow_test.dart`, `offline_edit_relaunch_sync_flow_test.dart`,
  `two_device_conflict_matrix_test.dart`, `local_first_planning_read_flow_test.dart`)
  use a new `test/support/backend_planning_reads.dart` helper built on
  `fetchPlanningSyncPayload` (for example
  `Future<BackendPlanDetail> readBackendPlanDetail(SupabaseClient client, {required String organizationId, required String planId})`).
  `providers_test.dart:131`'s `isA<SupabasePlanningRepository>()` stays valid.
- **R2** in `plan_and_session_flow_test.dart`: `pageSize: 1` gives the same
  payload as the default.

Commit: `fix(planning): pull plans, sessions and items as org-wide keyset streams (PG5, PG9)`.

## Task 5 — planning controller (PG6, PG8; PC1–PC3)

**Test first** in `test/application/planning/planning_sync_controller_test.dart`:
PC1–PC3.

**Implement:**

- `PlanningSyncController` passes `shouldContinue: () => !_isStale(generation)`
  to `fetchPlanningSyncPayload`.
- Optional constructor parameter `Observability? observability` (default
  `const NoopObservability()`), wired in `planning_providers.dart` from
  `observabilityProvider`. The refresh catch block becomes
  `catch (error, stackTrace)`; after its existing stale check it reports a
  `PagedReadContractException` (PG8) and keeps the `failed` state.
- Update every `PlanningRemoteRefreshRepository` fake to the new signature.

Commit: `fix(planning): stop a stale pull between pages; report paging contract breaks (PG6, PG8)`.

## Task 6 — documentation (orchestrator)

- `docs/architecture/decisions/ADR-041-keyset-paged-full-pulls.md`.
- `docs/architecture/architecture.md`: the full-pull paging rule, with an
  ADR-041 link.
- `docs/specs/2026-09-29-plan-delete-and-session-cascade.md`: remove I7's
  "Known limit" and the gate-2 deferred reference; point to this spec.
- Remove `docs/deferred/2026-09-30-planning-pull-unpaged-reads.md`.
- Roadmap: the S5a row (keyset, not `.range()`) and the status note.

Commit: `docs(sync): ADR-041 keyset-paged full pulls; close the unpaged-reads entry`.

## Final review

One Opus 5.5 adversarial whole-diff review. It must try to disprove: "a
refresh can store a catalog snapshot or planning projection that silently
misses a row the server would return to this user, or that contains a row
from another organization or user." Blocking only: silent row loss,
cross-organization or cross-user rows, a refresh that can never succeed for a
large library, I7 broken. At most one fix round; everything else is deferred
with a doc.
