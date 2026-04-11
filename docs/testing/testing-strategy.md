# Testing Strategy

## Principles

1. TDD is mandatory for behavior changes and new implementation work.
2. The repository must describe the intended test pyramid and quality gates.
3. All tests must be green before merge.
4. Critical offline, authorization, and sync behavior must be covered explicitly.
5. Song-reader slices must cover the supported ChordPro subset and recoverable parser warnings explicitly.

## Test Layers

### Unit Tests

Cover:

- Domain invariants
- Capability mapping behavior in pure application logic
- Sync orchestration decisions
- Authenticated catalog snapshot selection and refresh-state mapping
- ChordPro parsing and metadata mapping rules
- Song repository boundary behavior and backend summary/source mapping
- Song CRUD orchestration behavior, including authorization-failure handling, OCC conflict branching, slug reconciliation, and `pending_delete` filtering
- Planning repository boundary behavior, including plan ordering and plan-detail mapping
- Planning write orchestration behavior, including optimistic-concurrency base-version capture, provisional slug allocation, retryable failed mutations, empty-session delete enforcement, and session/session-item collection-edit compaction
- Slug-routing boundary behavior for route resolution, including explicit not-found surfaces for missing song, plan, and session slugs
- Slug-routing boundary behavior for scoped reader song resolution within a session, including the assumption that a song appears at most once per session
- Slug-routing boundary behavior for route generation, including canonical slug URLs and no id-based fallback when the canonical song slug is unavailable at the presentation edge
- Parser diagnostics and warning policy for the supported ChordPro subset

Current foundation baseline:

- capability code stability tests in Flutter
- offline policy tests in Flutter

### Widget Tests

Cover:

- Route-level screens
- Empty, loading, and failure states
- Capability-driven UX affordances
- Offline indicators and conflict surfaces
- Song CRUD flows, including delete-blocked messaging for referenced songs and sign-out warnings for unsynced mutations
- Persistent song-catalog status surfaces for online, offline, refreshing, and refresh-failed modes
- Song list and reader controls, including view mode, transposition, font scaling, and warning surfaces
- Planning list/detail loading, empty, and failure states plus signed-in navigation affordances into planning
- Planning create/edit, session create/rename/delete/reorder, and song-backed session-item add/delete/reorder flows, including failed-mutation review surfaces and sign-out warnings when planning mutations remain unsynced
- Route-level slug resolution behavior for songs, plans, and session-scoped reader entry, including canonical slug URLs and explicit not-found behavior

### Integration Tests

Cover:

- App bootstrap and routing
- Local-first flows
- Sync queue lifecycle
- Offline song create, update, delete, sync, and conflict-resolution flows
- Auth session bootstrap against test doubles or integration backends
- Authenticated backend song reads against the local Supabase stack, including organization-scope isolation
- Authenticated backend planning reads against the local Supabase stack, including ordered plan/session expansion and hidden-organization isolation
- Persistent cache reopen from the latest authenticated cached catalog in automation, plus cache removal on explicit sign-out
- Persistent planning-cache reopen for the active organization in automation, plus cache removal on explicit sign-out and refresh-failure offline reuse
- Local-first planning write persistence across database reopen, merged local planning write visibility for session and session-item collection edits, and explicit sign-out cleanup for both planning projection and planning mutations

### Backend Verification

Cover:

- Migration validity
- Migration application in a local Supabase stack through `./scripts/supabase.sh`
- Slug-column backfill and uniqueness verification for songs, plans, and sessions
- SQL function behavior
- RLS policy expectations
- Song write authorization enforcement for `canEditSongs`
- Planning write authorization enforcement for plan create/edit, session create/rename/delete/reorder, and song-backed session-item add/delete/reorder RPCs
- Planning optimistic-concurrency checks for plan/session update, delete, and collection-reorder RPCs
- Planning empty-session delete rejection when `session_items` still exist
- Planning duplicate-song rejection for session-item add and active-organization song-visibility enforcement for song-backed session-item creation
- Delete rejection while `session_items` still reference the song, plus attachment cleanup after accepted song deletion
- Seed script idempotency where applicable
- Local demo auth provisioning through `./scripts/provision-local-demo-user.sh`
- Regression coverage for repeated local demo auth provisioning where workflow scripts depend on idempotency
- Migration regression coverage for repair paths that must succeed on previously duplicated local membership data

## Pre-Merge Quality Gates

- `dart format --set-exit-if-changed`
- `flutter analyze`
- `flutter test`
- `./scripts/check-migrations.sh`
- local Supabase reset and demo auth provisioning when backend-backed slices change
- authenticated backend integration coverage for real Supabase song reads
- authenticated backend integration coverage for real Supabase planning reads when the planning slice changes
- local-first authenticated reader integration coverage for persistent cache reopen, hard replace, periodic refresh failure cache preservation, and explicit sign-out
- local-first authenticated planning integration coverage for persistent cache reopen, ordered detail reuse, refresh-failure cache preservation, organization-boundary invalidation, and explicit sign-out
- local-first planning write integration coverage for persisted pending mutations, merged local plan/session/session-item writes, and explicit sign-out cleanup

`./scripts/check-migrations.sh` is the canonical migration lint entrypoint for both local development and CI. It starts or reuses local Supabase through the repository-managed wrapper before invoking `db lint`, so migration verification does not depend on hidden workflow-specific database bootstrap steps.

The slug-routing slice adds a dedicated backend regression script under `scripts/tests/` that resets local Supabase and verifies the new slug columns, backfilled seed values, and scoped uniqueness constraints against the running database. Keep that style of verification close to the migration slice so route changes do not silently drift from database reality.

`./scripts/verify.sh` is the preferred local entrypoint because it runs the Flutter checks first and delegates migration lint bootstrap to `./scripts/check-migrations.sh`. Without `--skip-migrations`, it continues from that started or reused local Supabase stack, resets the local database, provisions the documented demo user, runs the manual-validation script contract test, and runs the authenticated backend song-reading integration test, the local-first authenticated reader integration test, the authenticated planning read integration test, the local-first planning read integration test, and the planning write contract regression coverage with repository-discovered `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SERVICE_ROLE_KEY` values where required. The backend-backed integration gate now proves manual refresh and periodic refresh against the real local Supabase stack, the planning read path against the same local stack, persistent cache reopen behavior plus periodic refresh failure cache preservation and explicit sign-out cleanup after database close/reopen for both song and planning reads, and the planning write contract for session reorder plus song-backed session-item add/delete/reorder. Native manual validation still covers true offline relaunch acceptance. Use `./scripts/verify.sh --skip-migrations` only when the change is confined to app and documentation work and does not affect backend-backed song reading, backend-backed planning reads, local-first planning reads, planning write contracts, or local Supabase workflow behavior.

## AI-Assisted Development Rules

- AI may accelerate implementation, but it does not replace tests.
- If a new behavior is introduced, at least one test must demonstrate the intended behavior.
- Repository documentation must be updated when tests reveal changed assumptions.
- If backend tooling is unavailable locally, CI must still keep the corresponding verification path enforced, and pull requests must not bypass the backend-backed `./scripts/verify.sh` gate for the authenticated song-reader and local-first planning read slices.
