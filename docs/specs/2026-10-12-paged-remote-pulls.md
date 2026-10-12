# Spec: Paged Remote Pulls

- Date: 2026-10-12
- Branch: `fix/paged-remote-pulls`
- Roadmap slice: S5a (`docs/plans/2026-10-01-delivery-roadmap.md`)
- Closes: `docs/deferred/2026-09-30-planning-pull-unpaged-reads.md` (removed in
  this change)
- Builds on: ADR-037 (local-first catalog visibility), ADR-035 D4 (the
  rejected-empty-snapshot guard), ADR-038 and invariant I7 of
  `docs/specs/2026-09-29-plan-delete-and-session-cascade.md`, ADR-036
  (observability)
- New: ADR-041 (keyset-paged full pulls)
- Plan: `docs/plans/2026-10-12-paged-remote-pulls.md`

## Problem

The two full pulls read every row of a table with single, unpaged PostgREST
requests:

- `SupabaseSongRepository.listSongs` selects all songs with no `.range()`,
  then `SongCatalogController` fetches each song's `chordpro_source` with its
  own GET, all at once through `Future.wait`.
- `SupabasePlanningRepository.fetchPlanningSyncPayload` reads the plans with
  one request, then each plan's sessions, with `session_items` embedded, with
  one request per plan.

PostgREST caps every read at `db-max-rows` (`max_rows = 1000` in
`supabase/config.toml`; hosted projects use the same default). It truncates
silently.

- **Songs.** Songs past the cap drop out of the song list and the offline
  catalog. With 1000 songs the refresh also issues 1000 concurrent source
  requests, and one failure fails the whole refresh: a large library may never
  refresh.
- **Plans and sessions.** An organization over the cap loses plans from the
  offline projection. A plan whose sessions are truncated stores its full
  `content_version` next to a partial session list, which breaks I7.
- **Embedded `session_items`.** Verified at the design gate: PostgREST applies
  `db-max-rows` to every node of the read plan, embedded resources included
  (`treeRestrictRange` in `src/library/PostgREST/Plan.hs`; the "works on all
  levels" case in `test/spec/Feature/Query/QueryLimitedSpec.hs`). The limit
  applies per parent row, so a session with more than 1000 items loses items
  silently. This also breaks I7. The PostgREST version that introduced this
  was not pinned down; this spec treats it as applying.

A second, independent defect surfaced while reading the catalog path:
`listSongs` is not filtered by organization. RLS
(`has_capability(organization_id, 'canViewSongs')`) returns the songs of
every organization the user can view, while the snapshot is stored under the
active `(userId, organizationId)`.

## Decisions

### PG1 — keyset paging, ended by an empty page

Every full pull reads its table in pages of
`order(<key>, ascending: true).gt(<key>, <last key>).limit(<page size>)`,
starting with no `gt` filter, and stops only when a page returns **zero**
rows.

- Not `.range()` offset paging (the roadmap's original default). An insert or
  delete before the offset between two page reads shifts every later row by
  one, so one pre-existing row is skipped or read twice. A `count=exact`
  check does not catch this: the totals can match while one row is swapped
  for another.
- A short page is not an end signal: when the server cap is below the page
  size every page is short. An empty page is the only safe end signal, and it
  is independent of the cap. Keyset paging therefore cannot truncate,
  whatever the cap, and `count=exact` is unnecessary.
- Cost: one extra request per stream (the final empty page).
- All four tables (`songs`, `plans`, `sessions`, `session_items`) have uuid
  primary keys; the key is `id`.
- **Trap, pinned by a test:** postgrest-dart's `order()` defaults to
  `ascending: false`. Every paged query passes `ascending: true` explicitly.
  (The old `.order('title')` was therefore descending. Nothing consumed the
  server order: `DriftSongCatalogStore.readActiveSummaries` sorts by title, and
  plans and sessions are sorted client-side.)
- Display order stays client-side. The catalog payload is returned sorted by
  title, then id; the planning payload keeps today's plan, session and item
  order.

### PG2 — one shared, domain-agnostic helper

`apps/lyron_app/lib/src/shared/keyset_paging.dart`:

```dart
typedef KeysetPageFetcher<R, K> =
    Future<List<R>> Function({required K? after, required int limit});

Future<List<R>> readAllKeysetPages<R, K>({
  required KeysetPageFetcher<R, K> fetchPage,
  required K Function(R row) keyOf,
  required int Function(K a, K b) compareKeys,
  required int pageSize,
  bool Function()? shouldContinue,
  String stream = 'unnamed',
});

int compareUuidKeys(String a, String b);
```

Rules:

- The first fetch passes `after: null`; each later fetch passes the key of
  the previous page's last row.
- It stops only on an empty page and then returns every row read, in read
  order.
- Every key must be strictly greater, by `compareKeys`, than the key before
  it (the cursor included). A duplicate, an overlap with an earlier page, or
  an out-of-order row throws `PagedReadContractException`.
- A page longer than `limit` throws `PagedReadContractException`.
- Any fetch error propagates unchanged. There is never a partial result.
- `shouldContinue` is checked before every fetch and after every fetch. When
  it returns false the helper throws `PagedReadAbortedException` and fetches
  nothing more.
- `pageSize` must be positive.
- The key type is generic with a mandatory comparator. S3's personal-layer
  pull will page by a server-side bigint sequence, where string order is wrong
  ("10" < "9").
- `compareUuidKeys` is `String.compareTo`. Its doc comment states that it is
  valid **only for columns of Postgres type `uuid`**. Postgres orders uuids
  by their 16 bytes, which is the order of their canonical hex text. A `text`
  column is ordered by its collation, which can differ from code-unit order,
  so the comparator must not be used for one. A test pins the equivalence
  with byte order for fixed pairs.
- `PagedReadContractException` carries `stream`, `pageIndex` and a `reason`
  enum (`keyNotIncreasing`, `pageOverLimit`). Its message contains no keys
  and no row data.

### PG3 — the catalog reads sources in the same stream

A new application-layer interface replaces the controller's use of
`SongRepository`:

```dart
// lib/src/application/song_library/song_catalog_remote_repository.dart
final class SongCatalogPayload {
  const SongCatalogPayload({required this.summaries, required this.sources});
  final List<SongSummary> summaries;
  final List<SongSource> sources;
}

abstract interface class SongCatalogRemoteRepository {
  Future<SongCatalogPayload> fetchCatalog({
    required String organizationId,
    bool Function()? shouldContinue,
  });
}
```

- `SupabaseSongRepository` implements it with one keyset stream over `songs`
  selecting `id, slug, title, version, chordpro_source`. There is no per-song
  GET and no `Future.wait`.
- A summary and its source come from the same row, so they always describe
  the same version (before, the list and the sources were separate reads).
- A row without a `chordpro_source` string fails the fetch.
- **Error classification (accepted at the gate).** A `PostgrestException`
  from the stream propagates unchanged, so a 42501/401/403 is classified by
  `_isAuthorizationFailure` as an authorization failure (`sessionStatus:
  expired`), exactly like a `listSongs` failure today. Before this change a
  denied source read raised `SongAccessDeniedException`, which the controller
  classified as a generic failure.
- The controller span `song_catalog.list_songs` and `song_catalog.fetch_sources`
  become one span, `song_catalog.fetch_catalog`.

### PG4 — the catalog is scoped to the active organization

The song stream filters `organization_id=eq.<context.organizationId>`. The
organization queried is, by construction, the organization the snapshot is
stored under.

**Multi-organization edge case.** A user who is a member of more than one
organization may hold a stored snapshot that contains other organizations'
songs (written before this change). If the active organization has zero
songs, the first scoped refresh returns empty and the D4 guard rejects it
(`implausibleEmpty`): the stored songs stay. The second, independent empty
refresh is accepted and replaces the snapshot with the empty one. This is the
intended behavior: D4's two-step convergence, unchanged. It is not a leak,
because RLS showed those rows to this user anyway. If the active organization
has songs, the first scoped refresh replaces the snapshot outright.

This keeps the single-organization model (ADR-008: one active authenticated
snapshot per user; ADR-018).

### PG5 — planning reads three organization-wide streams, in order

`fetchPlanningSyncPayload` reads, strictly in this order:

1. `plans` filtered by `organization_id`, all pages;
2. `sessions` (select includes `plan_id`) filtered by `organization_id`, all
   pages;
3. `session_items` (`id, session_id, position, song:songs(id, slug, title)`)
   filtered by `organization_id`, all pages.

- **Replaces** the per-plan session loop and the embedded `session_items`
  (the gate approved this change over the original "keep per-plan session
  reads"). The request count drops from `1 + P` to
  `ceil(P/500) + ceil(S/500) + ceil(I/500) + 3`. Per-plan paging would have
  doubled today's N+1, because every stream ends with an empty page. No N+1
  deferred note is needed.
- The `song` embed is to-one and returns at most one row per item, so
  `db-max-rows` cannot truncate it.
- **I7 holds.** Every plan row, including `content_version`, is read before
  any session row, and every session row before any item row. A concurrent
  write can only leave a plan's `content_version` behind the children read
  after it, never ahead.
- **Orphans are dropped.** A session whose `plan_id` is not in the plan set,
  and an item whose `session_id` is not in the kept session set, are left out.
  Such a child was created after its parent's stream was read, so its plan's
  `content_version` was read before the write that added it. The projection
  stays behind (safe) and the next refresh picks the child up.
- Output order is unchanged: plans sorted as today; per plan, sessions by
  `position` then `id`; per session, items by `position` then `id`.
- An item without a readable song still fails the refresh (today's
  `StateError`, unchanged).

### PG6 — staleness checks between pages

Both `fetchCatalog` and `fetchPlanningSyncPayload` take
`bool Function()? shouldContinue` and pass it to every stream. The controllers
pass `() => !_isStale(generation)`.

- An abort throws `PagedReadAbortedException`. It reaches the controllers'
  existing catch blocks, which return without a state change when the
  generation is stale. `SongCatalogController`'s catch block gains a stale
  check as its first statement, so an aborted refresh also leaves no
  "refresh failed" breadcrumb. `PlanningSyncController`'s catch block already
  starts with that check.
- The existing `_isStale(generation)` checks after every await stay.

### PG7 — replace only after the full sequence

- The catalog snapshot and the planning projection are replaced only after
  every page of every stream has been read. A failure on any page is a failed
  refresh, and the stored data stays unchanged.
- ADR-037 local-first visibility and the D4 guard are untouched. An empty
  catalog is the empty result of a complete stream: an empty first page.
- `_validateSnapshot` still rejects a summary/source mismatch; with PG3 that
  can only mean a defect.

### PG8 — a contract violation is reported

`PagedReadContractException` means that the server or the client library broke
the paging contract (ignored the order, the filter or the limit). It is not
network noise.

- Both controllers report it with `Observability.captureException`, with
  `extra: {'stream': ..., 'reason': ..., 'pageIndex': ...}` and no row data
  (ADR-036). The refresh state stays `failed`, as for any other failure.
- `PlanningSyncController` gains an optional
  `Observability observability = const NoopObservability()` constructor
  parameter; the provider passes `observabilityProvider`.
- `PagedReadAbortedException` is not reported.

### PG9 — no dead remote read path stays alive

Verified at the gate: in production, `SupabasePlanningRepository` is wired
only as `PlanningRemoteRefreshRepository` (`planning_providers.dart`), and
`SupabaseSongRepository` only as the catalog controller's remote repository
(`song_catalog_providers.dart`).

- `SupabasePlanningRepository` drops `implements PlanningRepository` with
  `listPlans`, `getPlanDetail`, `getPlanSummaryBySlug` and
  `getPlanDetailBySlug`, and the row typedefs behind them.
- `SupabaseSongRepository` drops `implements SongRepository` with `listSongs`,
  `getSongSource`, `getSongSummaryBySlug` and the access-denied mapping.
- The tests that used them read the backend through the new methods instead:
  - the integration tests that compared backend plan detail use a test-support
    helper built on `fetchPlanningSyncPayload`;
  - `authenticated_song_reader_flow_test.dart` checks cross-organization
    isolation by asserting that the foreign song id is absent from
    `fetchCatalog` instead of expecting a denied single read.
- `SongRepository` and `AssetSongRepository` stay (outside this slice).

### PG10 — page sizes

| Stream | Page size | Reason |
|---|---|---|
| `songs` with `chordpro_source` | 100 | ~2–10 KB per source, so at most about 1 MB per page; 1000 songs take 11 sequential requests instead of 1001 concurrent ones |
| `plans`, `sessions`, `session_items` | 500 | metadata only |

Both are below `max_rows`; correctness does not depend on that (PG1). The
production constructors take an optional `@visibleForTesting` page size, so
the local-Supabase integration tests can read the seed with a page size of 1
and exercise real multi-page keyset reads.

### PG11 — no backend migration

- `songs`, `plans` and `sessions` each have `unique (organization_id, id)`,
  whose index serves `organization_id = ? and id > ? order by id`.
- `session_items` has **no** organization index and no
  `(organization_id, id)` unique constraint; its only indexes are
  `session_items_session_idx (session_id, position)` and
  `session_items_unique_song_per_session (session_id, song_id)`. The items
  stream is therefore a primary-key range scan filtered by
  `organization_id`. For a database that serves a single organization this is
  acceptable. If it ever matters, an `(organization_id, id)` index is a
  separate backend chore (hosted deploys are manual).

## Acceptance criteria

Helper (`test/shared/keyset_paging_test.dart`):

- H1 An empty first page returns `[]` after one fetch with `after: null`.
- H2 Full pages are concatenated; each fetch's `after` is the previous page's
  last key.
- H3 A short page is not an end: with a simulated cap below the page size,
  every row is read and the read ends only on an empty page.
- H4 A key equal to or below the cursor (overlap, duplicate) throws
  `PagedReadContractException(keyNotIncreasing)`.
- H5 An out-of-order key inside a page throws the same.
- H6 A page longer than `limit` throws `PagedReadContractException(pageOverLimit)`.
- H7 A failure on page k propagates; no result is returned.
- H8 `shouldContinue` false between pages throws `PagedReadAbortedException`
  and fetches nothing more; false before the first fetch fetches nothing.
- H9 A generic integer key pages with an integer comparator (10 after 9).
- H10 `compareUuidKeys` agrees with byte order for fixed canonical lowercase
  uuid pairs, including digit/letter boundaries.

Song repository (`test/infrastructure/song_library/supabase_song_repository_test.dart`):

- S1 Every page request carries the organization id and the cursor.
- S2 Summaries and sources come from the same rows; output sorted by title,
  then id.
- S3 With a cap below the page size, the catalog is complete.
- S4 A page failure, or a row without `chordpro_source`, throws.

Catalog controller (`test/application/song_library/song_catalog_controller_test.dart`):

- C1 A failure mid-stream gives `refreshStatus: failed`; the stored snapshot
  is unchanged and `replaceActiveSnapshot` is not called.
- C2 A refresh makes one `fetchCatalog` call and no per-song reads.
- C3 A generation change between pages stops the stream (no further page),
  writes nothing and records no failure breadcrumb.
- C4 Multi-organization: a stored snapshot holding foreign songs and an empty
  scoped result gives `implausibleEmpty` with the snapshot kept; the second
  empty refresh replaces it.
- C5 `fetchCatalog` is called with `context.organizationId`.
- C6 A `PagedReadContractException` is reported via `captureException` and
  the state is `failed`; a `PagedReadAbortedException` is not reported.

Planning repository (`test/infrastructure/planning/supabase_planning_repository_test.dart`):

- P1 With a cap below the page size, plans, sessions and items are complete.
- P2 Order (recording fake): every plan page precedes every session page,
  which precedes every item page (I7).
- P3 A failure in any of the three streams throws.
- P4 An item whose session is unknown is dropped.
- P4b A session whose plan is unknown is dropped, and so are its items.
- P5 `shouldContinue` false aborts.
- P6 A session with more than 1000 items is complete (the embedded-truncation
  regression).
- P7 Every stream is filtered by the organization id.

Planning controller (`test/application/planning/planning_sync_controller_test.dart`):

- PC1 A page failure gives `refreshStatus: failed`; the projection is
  unchanged.
- PC2 A generation change between pages: no replace.
- PC3 A `PagedReadContractException` is reported; an abort is not.

Real PostgREST (local Supabase, `scripts/verify.sh`):

- R1 `fetchCatalog` with page size 1 against the seed returns the same songs
  as page size 100, and none of another organization's songs.
- R2 `fetchPlanningSyncPayload` with page size 1 returns the same payload as
  page size 500.

## Intentional test changes

- Test fakes that implement `SongRepository` for the catalog controller
  implement `SongCatalogRemoteRepository` instead.
- Every `SupabaseSongRepository.testing` / `SupabasePlanningRepository.testing`
  call site moves to page fetchers.
- `song_catalog_controller_sentry_instrumentation_test.dart`: the
  `song_catalog.list_songs` / `fetch_sources` spans become
  `song_catalog.fetch_catalog`.
- Tests of the removed methods (PG9) are removed or moved to the new methods.
- Integration tests that read backend plan detail use the new test-support
  helper.

## Non-goals

- Incremental (delta) pulls. Every refresh still reads everything.
- Changing what a refresh does with the data once read.
- `SongRepository` / `AssetSongRepository` cleanup.
- The `session_items` organization index (PG11).

## Residuals

- The items stream is a filtered primary-key scan (PG11).
- A refresh of a large catalog now takes `ceil(N/100) + 1` sequential
  requests. For 1000 songs that is 11 round trips; acceptable for a background
  refresh.

## Documentation updates (in the implementation PR)

- ADR-041 (new) and `docs/architecture/architecture.md`.
- `docs/specs/2026-09-29-plan-delete-and-session-cascade.md`: remove I7's
  "Known limit" and update the deferred-item reference.
- Remove `docs/deferred/2026-09-30-planning-pull-unpaged-reads.md`.
- Roadmap: the S5a row and the status note.
