# Local-First Lifecycle And Persistence Regression Hardening Plan

> Status: Planned

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` only if splitting isolated test/documentation tasks across workers. Do not implement production behavior changes from this plan without following the escalation rule below.

### Goal

Harden P2 local-first lifecycle and persistence regression coverage without changing production behavior:

- Song session-expiry cache policy regression tests and documentation.
- Planning mutation accepted-write fallback regression tests.
- Song pending mutation persistence across Drift database reopen regression tests.

Required deferred items covered:

- `docs/deferred/2026-05-01-song-session-expiry-cache-policy-hardening.md`
- `docs/deferred/2026-05-01-mutation-sync-regression-coverage-hardening.md`

### Assumptions

- This is a tests/docs-only hardening sweep.
- Existing behavior is intentional unless a new test exposes a real bug.
- Explicit song sign-out deletes persisted song catalog cache and song mutations for the user.
- Song session expiry clears active song catalog access and blocks cached authenticated reads while preserving persisted song cache rows.
- Offline or connectivity-unverifiable auth/session state can still use cached song fallback for the last authenticated context.
- Planning accepted-write fallback is already wired in `planningMutationSyncControllerProvider`, but needs provider/local-store integration coverage for accepted mutations when remote refresh fails.
- Song mutation records should persist across Drift database reopen for pending create, update, and delete states.

### Plan

1. A1: Add focused song session-expiry controller coverage
   - Files: `apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart`
   - Change:
     - Add tests around `CatalogSessionStatus.expired` when a persisted catalog already exists.
     - Keep these tests controller-level and store-backed with `SongCatalogDatabase.inMemory()`.
   - Expected assertions:
     - Expired session sets `controller.state.sessionStatus` to `CatalogSessionStatus.expired`.
     - Expired session clears `controller.state.context`.
     - Expired session sets `controller.state.hasCachedCatalog` to `false`.
     - Expired session does not call `deleteCatalogsForUser`; persisted rows remain readable through `store.readActiveSummaries(userId: ..., organizationId: ...)`.
     - Re-running refresh after session verification returns to `verified` and restores context allows cached/remote-backed reads again.
   - Verify:
     - `cd apps/lyron_app && flutter test test/application/song_library/song_catalog_controller_test.dart`

2. A2: Add provider/read-path session-expiry coverage
   - Files: `apps/lyron_app/test/application/providers_test.dart`
   - Change:
     - Add provider-level tests proving `AppAuthStatus.sessionExpired` does not expose cached song reads through active providers even when persisted song catalog rows exist.
     - Cover re-sign-in restoring the auth boundary before cached song access becomes available again.
   - Expected assertions:
     - When auth state is `sessionExpired`, `activeCatalogContextProvider` or the effective song catalog state has no active context.
     - Cached song summaries are not exposed through the provider read path while auth is expired.
     - Persisted song cache rows remain in the underlying `DriftSongCatalogStore`.
     - After a new `signedIn` generation with the same user and organization, provider state can expose cached/verified song data again.
   - Verify:
     - `cd apps/lyron_app && flutter test test/application/providers_test.dart`

3. A3: Document song session-expiry cache policy regression requirements
   - Files: `docs/testing/testing-strategy.md`, `docs/deferred/2026-05-01-song-session-expiry-cache-policy-hardening.md`
   - Change:
     - Add the explicit session-expiry song cache policy to testing strategy.
     - Mark the deferred item complete only after A1 and A2 tests exist and pass.
   - Expected assertions:
     - Documentation states the distinction between preserving persisted song cache rows and blocking active cached song access while auth is `sessionExpired`.
     - Documentation lists required regression coverage for explicit sign-out deletion, session-expiry access denial, connectivity-unverifiable fallback, and re-sign-in restoration.
   - Verify:
     - `rg -n "session-expiry|sessionExpired|cached song" docs/testing/testing-strategy.md docs/deferred/2026-05-01-song-session-expiry-cache-policy-hardening.md`

4. B1: Add planning accepted-write fallback provider/local-store test for plan create/edit
   - Files: `apps/lyron_app/test/application/providers_test.dart`
   - Change:
     - Add a provider integration test that uses the real `DriftPlanningLocalStore`, real `DriftPlanningMutationStore`, and `planningMutationSyncControllerProvider`.
     - Stub the remote mutation repository to accept a plan mutation with canonical data while `refreshPlanning` fails.
   - Expected assertions:
     - Accepted plan create or edit writes the canonical plan row into `planningLocalStoreProvider`.
     - Canonical `slug`, `name`, `description`, `scheduledFor`, and `version` from the accepted mutation are reflected in `planningPlanListProvider`.
     - The accepted mutation is cleared from `planningMutationEntriesProvider`.
     - `hasUnsyncedPlanningMutationsProvider` becomes `false`.
   - Verify:
     - `cd apps/lyron_app && flutter test test/application/providers_test.dart`

5. B2: Add planning accepted-write fallback provider/local-store test for session create/rename/delete
   - Files: `apps/lyron_app/test/application/providers_test.dart`
   - Change:
     - Extend provider integration coverage for accepted session mutations when refresh fails.
     - Seed a local plan projection where needed so session mutations can reconcile into an existing plan detail.
   - Expected assertions:
     - Accepted session create or rename upserts a session with canonical `id`, `planId`, `slug`, `position`, `name`, and `version`.
     - Accepted session delete removes the session from the local detail projection.
     - Cleared mutations no longer appear in the mutation review provider.
   - Verify:
     - `cd apps/lyron_app && flutter test test/application/providers_test.dart`

6. B3: Add planning accepted-write fallback provider/local-store test for session reorder
   - Files: `apps/lyron_app/test/application/providers_test.dart`
   - Change:
     - Add an accepted session reorder fallback test using the provider-owned reconciler in `planningMutationSyncControllerProvider`.
   - Expected assertions:
     - `replaceSyncedSessionOrder` effects are visible in `planningPlanDetailProvider`.
     - Session order matches accepted `orderedSiblingIds`.
     - Session positions match accepted `orderedSiblingPositions` when present.
     - Plan version is advanced to the accepted mutation `baseVersion`.
   - Verify:
     - `cd apps/lyron_app && flutter test test/application/providers_test.dart`

7. B4: Add planning accepted-write fallback provider/local-store test for session item create/delete/reorder
   - Files: `apps/lyron_app/test/application/providers_test.dart`
   - Change:
     - Add accepted-write fallback tests for song-backed session item create, session item delete, and session item reorder when refresh fails.
     - Prefer one table-driven helper if it keeps each mutation case readable; split into separate tests if assertions diverge.
   - Expected assertions:
     - Accepted session item create upserts canonical item `id`, `planId`, `sessionId`, `position`, `songId`, and `songTitle`.
     - Accepted session item create applies accepted sibling order when `orderedSiblingIds` is present.
     - Accepted session item delete removes the item and applies accepted sibling order when present.
     - Accepted session item reorder updates local item order and positions.
     - Session version is advanced to the accepted mutation `baseVersion`.
   - Verify:
     - `cd apps/lyron_app && flutter test test/application/providers_test.dart`

8. B5: Keep accepted-write fallback documentation explicit
   - Files: `docs/testing/testing-strategy.md`, `docs/deferred/2026-05-01-mutation-sync-regression-coverage-hardening.md`
   - Change:
     - Document provider/local-store accepted-write fallback as required planning mutation sync regression coverage.
     - Mark the planning accepted-write fallback part of the deferred item complete only after B1-B4 pass.
   - Expected assertions:
     - Documentation names plan, session, session item, and reorder accepted-write fallback coverage.
     - Documentation states these tests protect the provider-owned reconciler, not only the controller callback seam.
   - Verify:
     - `rg -n "accepted-write|reconcile|fallback|planning mutation" docs/testing/testing-strategy.md docs/deferred/2026-05-01-mutation-sync-regression-coverage-hardening.md`

9. C1: Add song pending create persistence across Drift reopen
   - Files: `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart`
   - Change:
     - Add a file-backed Drift reopen test for a pending song create mutation.
     - Use `Directory.systemTemp.createTemp`, `SongCatalogDatabase.connect(NativeDatabase.createInBackground(dbFile))`, and the existing Drift warning suppression pattern.
   - Expected assertions:
     - After closing and reopening the database, `readSongMutations(..., syncStatuses: [SongSyncStatus.pendingCreate])` returns one row.
     - Reopened row preserves `songId`, `slug`, `title`, `source`, `syncStatus`, and relevant version/error metadata.
     - Overlay reads still expose the pending create through `readActiveSummaries` after reopen.
   - Verify:
     - `cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`

10. C2: Add song pending update persistence across Drift reopen
    - Files: `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart`
    - Change:
      - Add a file-backed Drift reopen test for a pending song update mutation layered over a persisted snapshot row.
    - Expected assertions:
      - Reopened mutation preserves `songId`, `slug`, updated `title`, updated `source`, `SongSyncStatus.pendingUpdate`, `baseVersion`, and `syncErrorContext` if present.
      - Reopened active summary/source reads show the pending update overlay rather than the stale snapshot row.
      - Slug lookup hides the stale snapshot slug if the pending update moved the song to a new slug.
    - Verify:
      - `cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`

11. C3: Add song pending delete persistence across Drift reopen
    - Files: `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart`
    - Change:
      - Add a file-backed Drift reopen test for a pending song delete mutation layered over a persisted snapshot row.
    - Expected assertions:
      - Reopened mutation preserves `songId`, `slug`, `title`, `source`, `SongSyncStatus.pendingDelete`, `baseVersion`, and `syncErrorContext` if present.
      - Normal active summary/source reads hide the pending deleted song after reopen.
      - `readSongMutations(..., syncStatuses: [SongSyncStatus.pendingDelete])` still returns the durable pending delete row for sync replay.
    - Verify:
      - `cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`

12. C4: Keep song mutation persistence documentation explicit
    - Files: `docs/testing/testing-strategy.md`, `docs/deferred/2026-05-01-mutation-sync-regression-coverage-hardening.md`
    - Change:
      - Document pending create/update/delete song mutation persistence across Drift reopen as required regression coverage.
      - Mark the song persistence part of the deferred item complete only after C1-C3 pass.
    - Expected assertions:
      - Documentation states pending song create, update, and delete mutations must survive app/database restart.
      - Documentation ties this to local-first sync queue replay and reconciliation safety.
    - Verify:
      - `rg -n "song pending|pending create|pending update|pending delete|Drift.*reopen" docs/testing/testing-strategy.md docs/deferred/2026-05-01-mutation-sync-regression-coverage-hardening.md`

13. Final validation
    - Files: `apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart`, `apps/lyron_app/test/application/providers_test.dart`, `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart`, `docs/testing/testing-strategy.md`, `docs/deferred/2026-05-01-song-session-expiry-cache-policy-hardening.md`, `docs/deferred/2026-05-01-mutation-sync-regression-coverage-hardening.md`
    - Change:
      - Run focused validation first, then the app/doc validation appropriate for a tests/docs-only sweep.
    - Verify:
      - `cd apps/lyron_app && dart format --set-exit-if-changed test/application/song_library/song_catalog_controller_test.dart test/application/providers_test.dart test/offline/song_catalog/song_catalog_store_test.dart`
      - `cd apps/lyron_app && flutter test test/application/song_library/song_catalog_controller_test.dart`
      - `cd apps/lyron_app && flutter test test/application/providers_test.dart`
      - `cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`
      - `cd apps/lyron_app && flutter test test/application/planning/planning_mutation_sync_controller_test.dart`
      - `rg -n "session-expiry|accepted-write|Drift.*reopen|pending create|pending update|pending delete" docs/testing/testing-strategy.md docs/deferred/2026-05-01-song-session-expiry-cache-policy-hardening.md docs/deferred/2026-05-01-mutation-sync-regression-coverage-hardening.md`

### Acceptance Criteria

- Section A passes with tests proving session expiry blocks active cached song access while preserving persisted song cache rows.
- Section B passes with provider/local-store tests proving accepted planning writes reconcile into the real local projection when remote refresh fails.
- Section C passes with file-backed Drift reopen tests proving song pending create, update, and delete mutations survive database reopen and preserve read overlay semantics.
- `docs/testing/testing-strategy.md` names all three regression areas as required coverage.
- The two required P2 deferred items are either updated with completed subcoverage or explicitly retain only any remaining uncovered subitems.
- No production behavior files are changed unless a test exposes a real bug and the escalation rule is followed.

### Risks & mitigations

- Risk: Provider tests become too broad or brittle.
  - Mitigation: Keep each accepted-write case focused on one mutation kind and one local projection assertion set.
- Risk: Session-expiry tests accidentally assert private implementation details.
  - Mitigation: Assert public controller/provider state plus store-visible persisted rows, not internal fields.
- Risk: File-backed Drift reopen tests are slow or flaky.
  - Mitigation: Use existing `Directory.systemTemp` and Drift warning suppression patterns already present in store tests.
- Risk: Documentation overstates implementation if only part of the sweep lands.
  - Mitigation: Update deferred files only after the corresponding focused tests pass.

### Escalation Rule

If any planned test fails because production behavior is incorrect rather than because the test needs adjustment:

- Stop the tests/docs-only sweep.
- Do not patch production code in the same unreviewed task.
- Record the failing assertion, affected invariant, and suspected production file in the plan or deferred item.
- Create a follow-up implementation plan/spec before behavior changes.
- Require stronger review before changing auth/session lifecycle, sync reconciliation, or Drift persistence logic.
- Keep backend-enforced authorization rules unchanged unless a separate backend contract failure proves an authorization bug.

### Rollback plan

- Revert only the test and documentation files changed by the sweep.
- Leave production files untouched unless an escalated follow-up explicitly changes them.
- If a single test case is flaky, revert that case independently and keep other passing regression tests.
