# Local-First Cached Authenticated Song Reading Implementation Plan

> Status: Implemented; partially superseded by `docs/plans/2026-03-26-native-offline-relaunch-verification-hardening.md`, `docs/plans/2026-03-29-periodic-and-manual-song-catalog-refresh.md`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local-first authenticated song-reading path that caches the latest full visible song catalog for the current authenticated user and active organization, keeps the current reader architecture intact, and guarantees offline authenticated relaunch from the active cached snapshot on native Flutter targets.

**Architecture:** Keep the repository contract centered on `SongSummary` and raw `SongSource`, but back it with a new local catalog store and a thin refresh coordinator. A single song-catalog controller owns the active authenticated user context plus its current organization read context and the refresh lifecycle, while storage and local read behavior remain in dedicated store and repository units. The app should read from one active cached snapshot at a time, refresh the full catalog from Supabase when possible, delete cached authenticated data on explicit sign-out, and surface persistent connectivity and refresh state in the song list shell and core reader experience. Browser relaunch behavior may remain best-effort if web auth persistence proves weaker than native storage/session behavior; that should not widen this slice beyond its native-first guarantee.

**Tech Stack:** Flutter, Riverpod, Drift, SQLite, build_runner, Supabase Flutter client, Flutter widget tests, Flutter integration tests

---

### Task 1: Add Drift-Backed Song Catalog Cache Storage

**Files:**
- Create: `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_database.dart`
- Create: `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_tables.dart`
- Create: `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart`
- Create: `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`

- [ ] **Step 1: Write the failing store tests**

Create `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart` to define the storage contract:

```dart
test('replaces the active snapshot atomically for one user and organization', () async {
  final database = TestSongCatalogDatabase();
  final store = SongCatalogStore(database);

  await store.replaceActiveSnapshot(
    userId: 'user-1',
    organizationId: 'org-1',
    summaries: const [
      SongSummary(id: 'song-1', title: 'Alpha'),
    ],
    sources: const [
      SongSource(id: 'song-1', source: '{title: Alpha}'),
    ],
  );

  expect(
    await store.readActiveSummaries(userId: 'user-1', organizationId: 'org-1'),
    const [SongSummary(id: 'song-1', title: 'Alpha')],
  );
});
```

Also cover:
- replacing a previous active snapshot for the same active organization context
- isolating snapshots between different organizations
- deleting the cached snapshot for the signed-in user on sign-out
- never exposing a new song list without the matching raw sources for the same active snapshot

- [ ] **Step 2: Run the focused store test to verify it fails**

Run: `cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`

Expected: FAIL because the Drift database and store do not exist yet.

- [ ] **Step 3: Add the minimal Drift tables and database**

Create `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_tables.dart` with focused tables for:

```dart
class CachedCatalogSnapshots extends Table {
  TextColumn get userId => text()();
  TextColumn get organizationId => text()();
  IntColumn get snapshotVersion => integer()();
  DateTimeColumn get refreshedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, organizationId};
}
```

And companion tables for cached summaries and cached sources keyed by `(userId, organizationId, songId)` plus the current `snapshotVersion` column where useful for consistency checks inside one replacement transaction.

Create `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_database.dart` with a small Drift database that exposes those tables and uses a local SQLite executor.

- [ ] **Step 4: Implement the store with atomic hard-replace behavior**

Create `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart` with methods shaped like:

```dart
abstract interface class SongCatalogStore {
  Future<void> replaceActiveSnapshot({
    required String userId,
    required String organizationId,
    required List<SongSummary> summaries,
    required List<SongSource> sources,
    required DateTime refreshedAt,
  });

  Future<List<SongSummary>> readActiveSummaries({
    required String userId,
    required String organizationId,
  });

  Future<SongSource?> readActiveSource({
    required String userId,
    required String organizationId,
    required String songId,
  });

  Future<void> deleteCatalog({
    required String userId,
    required String organizationId,
  });
}
```

Implement `replaceActiveSnapshot()` in one transaction so a partially written refresh never becomes the active catalog.

Treat the active snapshot as the full cached catalog for the current authenticated user and active organization context:
- snapshot metadata
- cached song summaries
- cached raw song sources

The invariant for this slice is:
- at most one active snapshot exists per authenticated user, representing that user's current organization context
- all list reads and song-source reads resolve only through that one active snapshot
- a new snapshot becomes active only after both summaries and raw sources for that snapshot have been written successfully
- if the transaction does not complete, the previous active snapshot remains the only readable snapshot
- no historical local snapshot archive is retained in this slice

Implement the replacement transaction to:
1. write the new snapshot metadata
2. write the new summary and source rows into replacement tables or staging rows for the same authenticated user and active organization context
3. remove the previous summary and source rows for that context
4. commit only when the replacement catalog is complete

Explicit sign-out should delete the entire cached catalog for that signed-in user, including metadata, summaries, and sources.

This is logical catalog-level consistency, not a broader sync engine design.

- [ ] **Step 5: Wire a provider seam for the local store**

Update `apps/lyron_app/lib/src/application/providers.dart` to expose one provider for the `SongCatalogStore` so tests and later tasks can override it.

- [ ] **Step 6: Re-run the focused store test to verify it passes**

Run: `cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/lyron_app/lib/src/offline/song_catalog apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart apps/lyron_app/lib/src/application/providers.dart
git commit -m "feat(offline): add song catalog cache store"
```

### Task 2: Add Local-First Catalog State And Refresh Coordination

**Files:**
- Create: `apps/lyron_app/lib/src/application/song_library/catalog_connection_status.dart`
- Create: `apps/lyron_app/lib/src/application/song_library/catalog_refresh_status.dart`
- Create: `apps/lyron_app/lib/src/application/song_library/catalog_session_status.dart`
- Create: `apps/lyron_app/lib/src/application/song_library/active_catalog_context.dart`
- Create: `apps/lyron_app/lib/src/application/song_library/catalog_snapshot_state.dart`
- Create: `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`
- Create: `apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Modify: `apps/lyron_app/lib/src/application/song_library/song_library_service.dart`

- [ ] **Step 1: Write the failing controller tests**

Create `apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart` to define the orchestration contract:

```dart
test('keeps the previous active snapshot when refresh fails', () async {
  final controller = SongCatalogController(
    store: store,
    remoteRepository: remoteRepository,
    authSessionReader: () => const AppAuthSession(userId: 'user-1'),
    organizationReader: () => 'org-1',
  );

  await controller.refreshCatalog();
  remoteRepository.failListSongs();

  await controller.refreshCatalog();

  expect(controller.state.refreshStatus, CatalogRefreshStatus.failed);
  expect(controller.state.connectionStatus, CatalogConnectionStatus.offlineCached);
});
```

Also cover:
- first successful refresh creating an active snapshot
- a fresh authenticated online state after a successful backend refresh
- persistent cache reopen reading cached summaries in automation, plus native-target manual validation for offline-relaunch acceptance
- `sessionStateUnverifiableDueToConnectivity` keeping cached reading available during unstable connectivity
- confirmed session expiry blocking cached authenticated reading
- explicit sign-out deleting the cached catalog

- [ ] **Step 2: Run the focused controller test to verify it fails**

Run: `cd apps/lyron_app && flutter test test/application/song_library/song_catalog_controller_test.dart`

Expected: FAIL because the controller and state types do not exist yet.

- [ ] **Step 3: Add explicit local-first state types**

Create focused enums and state objects:

```dart
enum CatalogConnectionStatus { online, offlineCached, unavailable }
enum CatalogRefreshStatus { idle, refreshing, failed }
enum CatalogSessionStatus {
  verified,
  unverifiableDueToConnectivity,
  expired,
}

class ActiveCatalogContext {
  const ActiveCatalogContext({
    required this.userId,
    required this.organizationId,
  });

  final String userId;
  final String organizationId;
}

class CatalogSnapshotState {
  const CatalogSnapshotState({
    required this.context,
    required this.connectionStatus,
    required this.refreshStatus,
    required this.sessionStatus,
    required this.hasCachedCatalog,
  });

  final ActiveCatalogContext? context;
  final CatalogSessionStatus sessionStatus;
}
```

Keep connectivity mode, refresh outcome, and session-verification outcome separate so:
- offline cached mode and refresh-failed state can coexist
- connectivity failure does not imply confirmed session expiry
- confirmed session expiry can force reauthentication even if cached data exists

- [ ] **Step 4: Implement the controller**

Create `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart` to own:
- deriving and holding the active authenticated user plus current-organization read context
- reading the active cached snapshot for that authenticated user context
- full-catalog backend refresh
- atomic store replacement after a successful refresh
- sign-out cache deletion
- stable fallback behavior during missing or unstable connectivity

Keep `SongLibraryService` thin and move the local-first workflow ownership into the controller instead of burying it in UI code. Do not move raw storage reads, storage writes, or parsing into the controller; it is an orchestration owner, not the storage implementation.

Require the controller contract to map session checks into explicit outcomes:
- `CatalogSessionStatus.verified`
- `CatalogSessionStatus.unverifiableDueToConnectivity`
- `CatalogSessionStatus.expired`

Use that explicit session outcome to decide whether cached authenticated reading may continue or whether the app must force reauthentication.

- [ ] **Step 5: Wire providers for the controller and its state**

Update `apps/lyron_app/lib/src/application/providers.dart` to expose:
- a remote Supabase song repository provider
- the local-first catalog controller provider
- one provider for the active authenticated catalog context derived from the controller state
- one state provider or listenable the song list and reader can consume

- [ ] **Step 6: Re-run the focused controller test to verify it passes**

Run: `cd apps/lyron_app && flutter test test/application/song_library/song_catalog_controller_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/lyron_app/lib/src/application/song_library apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart apps/lyron_app/lib/src/application/providers.dart
git commit -m "feat(song-library): add local-first catalog controller"
```

### Task 3: Route Song Reads Through The Active Cached Snapshot

**Files:**
- Create: `apps/lyron_app/lib/src/infrastructure/song_library/local_first_song_repository.dart`
- Create: `apps/lyron_app/test/infrastructure/song_library/local_first_song_repository_test.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart`
- Modify: `apps/lyron_app/lib/src/domain/song/song_not_found_exception.dart`
- Modify: `apps/lyron_app/lib/src/application/song_library/song_library_service.dart`

- [ ] **Step 1: Write the failing local-first repository tests**

Create `apps/lyron_app/test/infrastructure/song_library/local_first_song_repository_test.dart` to require:

```dart
test('lists songs from the active cached snapshot', () async {
  final repository = LocalFirstSongRepository(store);

  expect(
    await repository.listSongs(userId: 'user-1', organizationId: 'org-1'),
    const [SongSummary(id: 'song-1', title: 'Alpha')],
  );
});
```

Also cover:
- reading raw source from the active cached snapshot
- throwing `SongNotFoundException` when a song is not in the active snapshot
- not reading songs from another organization snapshot

- [ ] **Step 2: Run the focused repository test to verify it fails**

Run: `cd apps/lyron_app && flutter test test/infrastructure/song_library/local_first_song_repository_test.dart`

Expected: FAIL because the local-first repository does not exist yet.

- [ ] **Step 3: Implement the local-first repository**

Create `apps/lyron_app/lib/src/infrastructure/song_library/local_first_song_repository.dart` as a read-only repository over the active cached snapshot:

```dart
class LocalFirstSongRepository {
  const LocalFirstSongRepository(this._store);

  final SongCatalogStore _store;

  Future<List<SongSummary>> listSongs({
    required String userId,
    required String organizationId,
  }) { ... }

  Future<SongSource> getSongSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) { ... }
}
```

Keep this repository free of auth lookup logic. It must require the resolved `(userId, organizationId)` read context from the song-catalog controller path.

- [ ] **Step 4: Switch the presentation providers to the local-first path**

Update `apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart` so song list and reader reads come from the active cached snapshot owned by the catalog controller instead of directly from Supabase.

Keep the backend repository available as the remote refresh dependency, not as the UI read path.

Make the provider seam explicit:
- read the active authenticated catalog context from the controller-owned provider
- fail closed when no active authenticated context exists
- pass `(userId, organizationId)` explicitly into local-first list and source reads
- ensure sign-out removes the active context before any cached read path remains available

- [ ] **Step 5: Re-run the focused repository and provider tests**

Run: `cd apps/lyron_app && flutter test test/infrastructure/song_library/local_first_song_repository_test.dart test/presentation/song_library/song_library_providers_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/infrastructure/song_library/local_first_song_repository.dart apps/lyron_app/test/infrastructure/song_library/local_first_song_repository_test.dart apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart apps/lyron_app/lib/src/application/song_library/song_library_service.dart apps/lyron_app/lib/src/domain/song/song_not_found_exception.dart
git commit -m "feat(song-library): read songs from cached catalog"
```

### Task 4: Surface Persistent Connectivity And Refresh State In The UI

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Test: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Test: `apps/lyron_app/test/app/lyron_app_test.dart`

- [ ] **Step 1: Write the failing widget tests for persistent state visibility**

Update `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart` to require visible status surfaces such as:

```dart
expect(find.text(AppStrings.songCatalogOnlineStatus), findsOneWidget);
expect(find.text(AppStrings.songCatalogOfflineStatus), findsOneWidget);
expect(find.text(AppStrings.songCatalogRefreshingStatus), findsOneWidget);
expect(find.text(AppStrings.songCatalogRefreshFailedStatus), findsOneWidget);
```

Also cover:
- unavailable state when no cached catalog exists
- sign-out removing access to previously visible cached catalog UI
- reader-visible cached/offline status when reading from the active snapshot
- reader-visible online/up-to-date status when reading from a freshly verified active snapshot
- refresh-failed plus offline-cached combined state visibility during unstable connectivity

- [ ] **Step 2: Run the focused widget tests to verify they fail**

Run: `cd apps/lyron_app && flutter test test/presentation/song_library/song_list_screen_test.dart test/presentation/song_reader/song_reader_screen_test.dart test/app/lyron_app_test.dart`

Expected: FAIL because the persistent local-first status surfaces do not exist yet.

- [ ] **Step 3: Add user-facing strings and minimal UI state surfaces**

Update `apps/lyron_app/lib/src/shared/app_strings.dart` with explicit status copy, for example:

```dart
static const songCatalogOnlineStatus = 'Online. Songs are up to date.';
static const songCatalogOfflineStatus = 'Offline. Showing cached songs.';
static const songCatalogRefreshingStatus = 'Refreshing song catalog...';
static const songCatalogRefreshFailedStatus =
    'Unable to refresh songs. Showing the last cached catalog.';
static const songCatalogUnavailableMessage =
    'No cached song catalog is available yet.';
```

Update the song list screen to render a persistent status banner or inline shell above the list.

Update the reader screen only as needed to keep unavailable and cached-read behavior consistent with the active snapshot.

The reader does not need a second independent state machine, but the core reader experience must still reflect the local-first operating mode required by the spec. At minimum, the reader must be able to surface cached/offline status when reading from the active local snapshot.
It must also be possible for the core reader experience to surface the explicit online/up-to-date state when reading from a freshly verified active snapshot.

- [ ] **Step 4: Re-run the focused widget tests to verify they pass**

Run: `cd apps/lyron_app && flutter test test/presentation/song_library/song_list_screen_test.dart test/presentation/song_reader/song_reader_screen_test.dart test/app/lyron_app_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart apps/lyron_app/lib/src/shared/app_strings.dart apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart apps/lyron_app/test/app/lyron_app_test.dart
git commit -m "feat(app): show local-first catalog status"
```

### Task 5: Add End-To-End Local-First Verification

**Files:**
- Modify: `apps/lyron_app/test/integration/authenticated_song_reader_flow_test.dart`
- Create: `apps/lyron_app/test/integration/local_first_authenticated_song_reader_flow_test.dart`
- Modify: `scripts/verify.sh`
- Test: `apps/lyron_app/test/integration/local_first_authenticated_song_reader_flow_test.dart`

- [ ] **Step 1: Write the failing integration test for offline relaunch**

Create `apps/lyron_app/test/integration/local_first_authenticated_song_reader_flow_test.dart` to prove:

```dart
testWidgets('relaunches offline from the cached catalog after one successful backend sync', (
  tester,
) async {
  // 1. Sign in with the local demo account
  // 2. Allow one successful catalog refresh
  // 3. Relaunch with backend reads failing
  // 4. Verify the cached catalog and cached reader still work
});
```

Also cover:
- explicit sign-out making the cached catalog unavailable
- hard replace after a successful newer full snapshot

- [ ] **Step 2: Run the focused integration test to verify it fails**

Run: `cd apps/lyron_app && flutter test test/integration/local_first_authenticated_song_reader_flow_test.dart --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=test-key`

Expected: FAIL because the local-first integration flow is not implemented yet.

- [ ] **Step 3: Add the new integration coverage to the repository verification path**

Update `scripts/verify.sh` so the backend-backed verification path runs both:

```bash
flutter test test/integration/authenticated_song_reader_flow_test.dart ...
flutter test test/integration/local_first_authenticated_song_reader_flow_test.dart ...
```

Keep the existing authenticated backend verification path intact.

- [ ] **Step 4: Re-run the focused integration flow until it passes**

Run: `./scripts/verify.sh`

Expected: PASS, including the new local-first integration flow.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/test/integration/authenticated_song_reader_flow_test.dart apps/lyron_app/test/integration/local_first_authenticated_song_reader_flow_test.dart scripts/verify.sh
git commit -m "test(app): verify local-first authenticated song reading"
```

### Task 6: Align Repository Docs With The New Executable Slice

**Files:**
- Modify: `README.md`
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/architecture/architecture.md`
- Create: `docs/architecture/decisions/2026-03-25-local-first-authenticated-song-catalog-cache.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/product/vision.md`
- Modify: `apps/lyron_app/README.md`

- [ ] **Step 1: Update repository-level docs to describe the local-first authenticated reader**

Reflect the new executable slice consistently:
- the app reads the active catalog from local cache
- backend refresh remains authorization-owned
- explicit online/offline/refreshing state exists in the UI
- explicit sign-out removes cached authenticated access
- the cached catalog is a user-owned read model for the currently active organization only
- the active snapshot rule applies to both song summaries and raw song sources

- [ ] **Step 2: Verify documentation consistency by re-reading the updated files**

Run: `sed -n '1,240p' README.md docs/domain/domain-model.md docs/architecture/architecture.md docs/testing/testing-strategy.md docs/product/vision.md apps/lyron_app/README.md docs/architecture/decisions/2026-03-25-local-first-authenticated-song-catalog-cache.md`

Expected: The docs consistently describe a local-first authenticated reader slice without widening into write sync or editing.

- [ ] **Step 3: Run the full repository verification path**

Run: `./scripts/verify.sh`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/domain/domain-model.md docs/architecture/architecture.md docs/architecture/decisions/2026-03-25-local-first-authenticated-song-catalog-cache.md docs/testing/testing-strategy.md docs/product/vision.md apps/lyron_app/README.md docs/plans/2026-03-25-local-first-cached-authenticated-song-reading.md
git commit -m "docs(repo): align local-first authenticated song reading"
```
