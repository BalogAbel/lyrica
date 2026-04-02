# Executable Local Supabase Authenticated Song Reading Spec

> Status: Implemented; partially superseded by `docs/specs/2026-03-25-local-first-cached-authenticated-song-reading.md`

## Goal

Deliver the first executable authenticated backend reading slice for Lyron Chords by proving that the repository-owned local Supabase workflow can run end-to-end, a local demo user can authenticate, and the existing tablet-first ChordPro reader can load organization-scoped songs from the backend through the current repository boundary.

## Scope

- Validate and, where necessary, repair the existing repository-owned local Supabase workflow.
- Prove that the current versioned schema and seed path can be executed locally.
- Define one explicit local demo authentication fixture for app development and verification.
- Add auth session bootstrap to the Flutter app.
- Add one app-level auth/bootstrap controller with explicit states:
  - `initializing`
  - `signedOut`
  - `signedIn`
  - `sessionExpired`
- Add one centralized router redirect hook driven by that controller.
- Add a Supabase-backed `SongRepository` implementation for:
  - song list summaries
  - raw ChordPro source by song ID
- Keep ChordPro parsing and reader rendering in the app.
- Keep the slice read-only.
- Verify that song visibility is enforced by backend auth and RLS rather than Flutter-side authorization logic.

## Non-Goals

- No song create, update, delete, or editing UI.
- No import/export flow.
- No offline persistence in Drift.
- No sync queue or conflict handling.
- No reader preference persistence.
- No multi-organization switching UI.
- No role-management UI.
- No plans, sessions, or setlist workflows.
- No parsed-song backend payloads.
- No attachments or FreeShow work.
- No production deployment workflow.

## Product Slice Summary

The completed tablet-first reader slice proved the reading experience, the supported ChordPro subset, and the repository boundary with bundled assets. What remains unproven is the first real runtime chain behind that reader.

This slice proves a narrow but critical claim: the repository already contains the beginnings of a backend path, and that path can be made executable locally without changing the reader architecture. The user should be able to sign in against a local Supabase-backed environment, see a backend-provided song list, open a song, and read it through the existing parser and reader flow.

This is not a general backend platform slice. It is the minimum executable backend-backed reading slice.

## Repository Baseline

The repository already contains a versioned Supabase baseline under:

- `supabase/migrations/202603210001_initial_schema.sql`
- `supabase/seed/seed.sql`

It also already documents the repository-owned Supabase workflow and wrapper expectations in `README.md`.

This slice does not treat those files as proven merely because they exist in git. The baseline is only considered valid for product work if it is executable through the repository workflow and supports the authenticated song-reading flow described here.

## Local Backend Requirements

### Executable Repository Workflow

The repository must expose one documented, repeatable local backend path using repository-owned tooling and scripts.

That path must cover:

- starting the local Supabase environment
- applying migrations
- loading seed data
- surfacing the environment values needed by the Flutter app
- resetting the local environment when state becomes stale

The slice should use repository wrappers such as `./scripts/supabase.sh` rather than introducing direct ad hoc CLI workflows.

### Demo Auth Fixture

The slice must define one explicit local demo auth fixture that is sufficient to prove the authenticated song-reading flow.

The fixture must include:

- at least one local demo user with documented sign-in credentials
- at least one active membership row linked to that user
- at least one organization-scoped visible song for that membership

The auth fixture is part of the slice, not an informal manual setup step.

For local repair safety, the repository may also need to correct previously duplicated organization-scoped demo memberships before enforcing uniqueness again. When such repair is required, the repository keeps the earliest duplicate row by `created_at, id` and removes the later duplicates.

Recommended default:

- email/password sign-in with a documented local demo account

Reason:

- simplest bootstrap path
- easiest local verification
- avoids email-delivery dependencies in the first backend slice

### Backend Catalog Parity

The local backend catalog for this slice should restore parity with the current reader slice rather than proving only a single-song happy path.

Target:

- the same three-song catalog currently used by the asset-backed reader slice, now represented in backend seed data

Reason:

- keeps the reader flow comparable across asset-backed and backend-backed modes
- reduces accidental regressions hidden by a one-song proof-of-life setup
- keeps the repository boundary honest under a realistic small catalog

## User Flows

### Local Backend Bootstrap

1. A developer starts the local Supabase environment through the repository-owned workflow.
2. The versioned schema is applied.
3. Seed data is loaded, including the local demo auth fixture and song catalog.
4. The Flutter app is configured to connect to the local Supabase instance.

### Signed-Out Launch

1. The user opens the app.
2. The app enters `initializing` while restoring or checking session state.
3. If no valid session exists, the app shows the signed-out entry screen.
4. The user signs in with the documented local demo credentials.

### Signed-In Launch

1. The user opens the app.
2. The app restores or checks session state.
3. If a valid session exists, the app routes directly to the song list.
4. The song list loads from the backend according to the user's visible organization scope.

### Song Reading

1. The user opens the song list.
2. The app loads minimal song summaries from the backend.
3. The user selects a song.
4. The app loads raw ChordPro source for that song from the backend.
5. The existing in-app parser converts the source into the current parsed-song model.
6. The existing reader renders the result using the current reader controls and warning behavior.

## App Auth And Routing Requirements

### Auth Bootstrap Ownership

Auth/bootstrap behavior must have one clear owner in the app.

Required structure:

- one auth/bootstrap controller in application or presentation state wiring
- one router redirect integration point driven by that controller

Auth checks must not be spread across song-list widgets, reader widgets, and route builders independently.

### Auth State Contract

The app-level auth/bootstrap controller must expose these explicit states:

- `initializing`
- `signedOut`
- `signedIn`
- `sessionExpired`

### Routing Policy

- Signed-out users must not reach the song list or reader routes.
- During `initializing`, the app should remain on a dedicated bootstrap/loading surface instead of jumping directly to sign-in.
- Signed-in users must not remain on the sign-in route after session restoration or successful sign-in.
- Redirect behavior must be centralized rather than duplicated in screens.

### Session Expiry Behavior

If a previously valid session becomes unusable:

- the app transitions to `sessionExpired`
- signed-in routes become unavailable
- the user is returned to re-authentication
- the UI shows a short explanatory message rather than a generic reader or network failure

## Data Access Boundary

This slice must preserve the existing architecture.

- The backend replaces the asset-backed repository implementation.
- The authenticated slice must not fall back to the bundled asset repository during normal auth/bootstrap flow.
- The backend does not redefine the song domain model.
- The repository contract remains centered on minimal `SongSummary` and raw `SongSource`.
- The backend does not return parsed sections, rendered lines, or reader-specific projections.
- ChordPro parsing remains in-app.
- Reader projection and rendering remain in-app.

This keeps the slice as a true repository implementation swap plus auth bootstrap, not a hidden redesign of the reading stack.

## Authorization And Failure Semantics

### Authorization Boundary

- Access control is enforced by Supabase Auth identity and Postgres RLS.
- Flutter may react to backend outcomes, but it must not implement song-visibility policy logic.
- The user only sees songs allowed by backend-enforced organization membership and capability rules.

### Failure Mapping

The app must distinguish at least these cases:

- `signedOut`
  - no valid session exists at bootstrap
  - result: show sign-in screen

- `sessionExpired`
  - an existing session becomes invalid during use
  - result: clear signed-in access and return to re-authentication

- `songNotFound`
  - requested song ID is not present in the visible backend scope
  - this also includes rows hidden by backend RLS where the repository only receives an unavailable/not-found result
  - result: show unavailable or not-found state

- `accessDenied`
  - backend returns an explicit permission-denied response for a song read
  - result: show an access-denied state, not a parser or reader error

- `transientBackendFailure`
  - network, transport, or temporary backend problem
  - result: show retryable failure state

These outcomes must be handled consistently at application boundaries rather than improvised inside individual widgets.

## Testing Requirements

TDD is mandatory.

### Unit Tests

Cover:

- auth/bootstrap state mapping
- session lifecycle orchestration through test doubles
- Supabase-backed repository contract behavior
- application-level mapping of auth and backend failures into UI-facing states

### Widget Tests

Cover:

- initializing state on app startup
- signed-out entry screen
- centralized redirect behavior
- signed-in song list loading, empty, and failure states
- unavailable or denied song load states in the reader flow

### Integration Tests

Cover:

- sign-in to song-list happy path
- session restore on app restart or bootstrap
- song selection to reader happy path using backend-provided source

### Backend Verification

This slice requires real local backend verification, not only mocks.

Must cover:

- local Supabase environment starts successfully
- migrations apply successfully
- seed path produces a usable local demo user, membership, and song catalog
- repeated local demo provisioning stays idempotent
- uniqueness-repair migrations succeed even if older local environments already contain duplicated organization-scoped demo memberships
- authenticated user can read in-scope songs
- authenticated user cannot read out-of-scope songs
- app happy path works from sign-in to reader against the local backend

### Quality Gate Expectation

For this slice, app-only verification is not sufficient. Merge readiness must include the repository's backend verification path together with Flutter verification.

## Scope Guardrails

To keep the slice thin and defensible:

- only one sign-in method
- no org chooser
- no write operations
- no parsed-song backend API
- no offline fallback claims
- no widening of the repository contract beyond summary plus raw source
- no Flutter-side authorization rules
- no backend work unrelated to making the local authenticated song-reading path executable

## Success Criteria

This slice is successful when:

- the repository-owned local Supabase workflow is executable
- a documented local demo user can authenticate
- the Flutter app restores and reacts to auth session state correctly
- the song list is loaded from Supabase rather than bundled assets
- the backend catalog provides the expected three-song reader slice parity
- opening a song loads raw backend ChordPro source
- the existing parser and reader render that source locally
- song visibility is enforced by backend auth and RLS
- denied, expired, missing, and transient failure cases behave predictably
- tests and local verification prove the real backend path rather than mocked client assumptions
