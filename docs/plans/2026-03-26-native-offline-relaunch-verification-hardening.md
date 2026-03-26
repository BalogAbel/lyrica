# Native Offline Relaunch Verification Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strengthen the local-first authenticated song-reading verification path so the repository proves persistent offline relaunch-style cache reopen behavior instead of only same-process in-memory cached reads.

**Architecture:** Keep product behavior unchanged and add the smallest possible testing seam at local song-catalog database construction so tests can open a persistent cache, close it, and reopen it from the same storage location. Use that seam to replace the weak in-memory relaunch proof with a persistent-storage reopen integration test, then align repository docs and verification wording with what the automated gate and manual validation each prove.

**Tech Stack:** Flutter, Drift, SQLite, Flutter test, Bash, Markdown

---

### Task 1: Add A Persistent Song Catalog Database Test Seam

**Files:**
- Modify: `apps/lyrica_app/lib/src/offline/song_catalog/song_catalog_database.dart`
- Modify: `apps/lyrica_app/test/offline/song_catalog/song_catalog_store_test.dart`

- [ ] **Step 1: Write the failing store test for reopening a persisted catalog**

Add a focused test in `apps/lyrica_app/test/offline/song_catalog/song_catalog_store_test.dart` that:

```dart
test('can reopen a persisted catalog from a new database instance', () async {
  final file = File(p.join(tempDir.path, 'catalog.sqlite'));
  final firstDatabase = SongCatalogDatabase.connect(
    NativeDatabase.createInBackground(file),
  );
  final firstStore = DriftSongCatalogStore(firstDatabase);

  await firstStore.replaceActiveSnapshot(
    userId: 'user-1',
    organizationId: 'org-1',
    summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
    sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
    refreshedAt: DateTime.utc(2026, 3, 26, 10),
  );

  await firstDatabase.close();

  final secondDatabase = SongCatalogDatabase.connect(
    NativeDatabase.createInBackground(file),
  );
  final secondStore = DriftSongCatalogStore(secondDatabase);

  expect(
    await secondStore.readActiveSummaries(
      userId: 'user-1',
      organizationId: 'org-1',
    ),
    const [SongSummary(id: 'song-1', title: 'Alpha')],
  );
});
```

- [ ] **Step 2: Run the focused store test to verify it fails**

Run: `cd apps/lyrica_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`

Expected: FAIL because there is no repository-owned seam for constructing the database against a caller-provided persistent executor.

- [ ] **Step 3: Add the minimal database constructor seam**

Update `apps/lyrica_app/lib/src/offline/song_catalog/song_catalog_database.dart` to expose a narrow constructor seam, for example:

```dart
factory SongCatalogDatabase.connect(QueryExecutor executor) {
  return SongCatalogDatabase._(executor);
}
```

Keep `local()` and `inMemory()` unchanged for production code.

- [ ] **Step 4: Re-run the focused store test to verify it passes**

Run: `cd apps/lyrica_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`

Expected: PASS.

### Task 2: Replace The Weak In-Memory Relaunch Integration Proof

**Files:**
- Modify: `apps/lyrica_app/test/integration/local_first_authenticated_song_reader_flow_test.dart`

- [ ] **Step 1: Write the failing persistent-relaunch integration test**

Replace the current same-process relaunch seam with a persistent-storage flow that:

1. creates a temporary SQLite file
2. syncs one authenticated catalog into a database opened on that file
3. closes the first database instance
4. creates a second database instance on the same file
5. recreates the store and controller around that reopened database
6. simulates offline refresh conditions through that reopened stack
7. proves cached list and source reads still work through the reopened store

Use the existing backend-backed online sync and offline controller pattern; only the cache storage seam should change.

- [ ] **Step 2: Run the focused integration test to verify it fails**

Run:

```bash
cd apps/lyrica_app && flutter test test/integration/local_first_authenticated_song_reader_flow_test.dart \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=test-anon-key
```

Expected: FAIL before the persistent seam is wired correctly.

- [ ] **Step 3: Implement the minimal persistent test setup**

Update `apps/lyrica_app/test/integration/local_first_authenticated_song_reader_flow_test.dart` to:

- use a temporary file-backed database for the relaunch scenario
- close the first database before constructing the second one
- recreate the store, repository, and controller using the reopened database before making offline assertions
- keep the sign-out and hard-replace integration checks intact
- leave browser-specific behavior out of the automated relaunch proof

- [ ] **Step 4: Re-run the focused integration test to verify it passes**

Run the same command as Step 2.

Expected: PASS when local Supabase credentials are valid.

### Task 3: Align Repository Verification And Workflow Docs

**Files:**
- Modify: `README.md`
- Modify: `apps/lyrica_app/README.md`
- Modify: `docs/product/vision.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/architecture/decisions/2026-03-25-local-first-authenticated-song-catalog-cache.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/workflows/development-workflow.md`
- Modify: `docs/specs/2026-03-25-local-first-cached-authenticated-song-reading.md`
- Modify: `docs/specs/2026-03-25-local-first-manual-validation-scripts.md`
- Modify: `docs/plans/2026-03-25-local-first-cached-authenticated-song-reading.md`

- [ ] **Step 1: Write the failing documentation expectation mentally against the current docs**

Confirm the docs currently overstate or blur what the automated gate proves versus what native manual validation proves.

- [ ] **Step 2: Update repository docs**

Adjust the docs so they explicitly say:

- the automated gate proves persistent cache reopen behavior
- native Flutter manual validation remains the acceptance path for authenticated offline relaunch
- browser relaunch remains best-effort only

- [ ] **Step 3: Re-read the updated docs for consistency**

Check the four modified docs together and ensure they use the same verification wording.
Check all modified docs together and ensure they use the same verification wording.

### Task 4: Re-Verify The Quality Gate

**Files:**
- Test: `apps/lyrica_app/test/offline/song_catalog/song_catalog_store_test.dart`
- Test: `apps/lyrica_app/test/integration/local_first_authenticated_song_reader_flow_test.dart`
- Test: `scripts/tests/verify-test.sh`
- Verify: `./scripts/verify.sh --skip-migrations` or `./scripts/verify.sh`

- [ ] **Step 1: Run the focused Flutter tests**

Run:

```bash
cd apps/lyrica_app && flutter test \
  test/offline/song_catalog/song_catalog_store_test.dart \
  test/integration/local_first_authenticated_song_reader_flow_test.dart
```

Expected: PASS, with the integration test still skip-gated when Supabase env is absent.

- [ ] **Step 2: Run the shell verify contract test**

Run: `bash scripts/tests/verify-test.sh`

Expected: PASS.

- [ ] **Step 3: Run the broader local gate**

Run: `./scripts/verify.sh --skip-migrations`

Expected: PASS for app/docs-safe verification.

- [ ] **Step 4: Run the full gate if the environment is available**

Run: `./scripts/verify.sh`

Expected: PASS, including the stronger persistent local-first integration proof.
