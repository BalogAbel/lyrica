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
- Planning repository boundary behavior, including plan ordering and plan-detail mapping
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
- Persistent song-catalog status surfaces for online, offline, refreshing, and refresh-failed modes
- Song list and reader controls, including view mode, transposition, font scaling, and warning surfaces
- Planning list/detail loading, empty, and failure states plus signed-in navigation affordances into planning

### Integration Tests

Cover:

- App bootstrap and routing
- Local-first flows
- Sync queue lifecycle
- Auth session bootstrap against test doubles or integration backends
- Authenticated backend song reads against the local Supabase stack, including organization-scope isolation
- Authenticated backend planning reads against the local Supabase stack, including ordered plan/session expansion and hidden-organization isolation
- Persistent cache reopen from the latest authenticated cached catalog in automation, plus cache removal on explicit sign-out

### Backend Verification

Cover:

- Migration validity
- Migration application in a local Supabase stack through `./scripts/supabase.sh`
- SQL function behavior
- RLS policy expectations
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

`./scripts/check-migrations.sh` is the canonical migration lint entrypoint for both local development and CI. It starts or reuses local Supabase through the repository-managed wrapper before invoking `db lint`, so migration verification does not depend on hidden workflow-specific database bootstrap steps.

`./scripts/verify.sh` is the preferred local entrypoint because it runs the Flutter checks first and delegates migration lint bootstrap to `./scripts/check-migrations.sh`. Without `--skip-migrations`, it continues from that started or reused local Supabase stack, resets the local database, provisions the documented demo user, runs the manual-validation script contract test, and runs the authenticated backend song-reading integration test, the local-first authenticated reader integration test, and the planning read integration test with repository-discovered `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SERVICE_ROLE_KEY` values where required. The backend-backed integration gate now proves manual refresh and periodic refresh against the real local Supabase stack, the planning read path against the same local stack, and persistent cache reopen behavior plus periodic refresh failure cache preservation and explicit sign-out cleanup after database close/reopen. Native manual validation still covers true offline relaunch acceptance. Use `./scripts/verify.sh --skip-migrations` only when the change is confined to app and documentation work and does not affect backend-backed song reading, backend-backed planning reads, or local Supabase workflow behavior.

## AI-Assisted Development Rules

- AI may accelerate implementation, but it does not replace tests.
- If a new behavior is introduced, at least one test must demonstrate the intended behavior.
- Repository documentation must be updated when tests reveal changed assumptions.
- If backend tooling is unavailable locally, CI must still keep the corresponding verification path enforced, and pull requests must not bypass the backend-backed `./scripts/verify.sh` gate for the authenticated song-reader and planning read slices.
