# Executable Local Supabase Authenticated Song Reading Implementation Plan

> Status: Implemented

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the repository-owned local Supabase path executable for authenticated song reading, then connect the Flutter app to it through auth bootstrap, centralized routing, and a Supabase-backed song repository while preserving the existing local parser and reader.

**Architecture:** Keep the slice vertical but thin. First, make the existing local Supabase baseline executable with a real demo auth fixture and three-song catalog parity. Then add a small auth/bootstrap boundary in Flutter, wire a centralized router redirect policy, and swap the asset-backed repository for a Supabase-backed read implementation that still returns only `SongSummary` and raw `SongSource`. Do not add write paths, offline persistence, or backend-specific parsed song payloads.

Post-merge corrections for this slice also require:
- idempotent local demo membership provisioning
- no runtime asset fallback in the authenticated repository path
- an executable bootstrap loading surface while auth restoration is in progress
- documentation that distinguishes explicit backend permission-denied failures from RLS-hidden unavailable rows

**Tech Stack:** Flutter, Riverpod, go_router, Supabase Flutter client, local Supabase CLI via repository scripts, Flutter widget tests, Dart unit tests, Flutter integration tests, SQL migrations and seed data

---

### Task 1: Make The Local Supabase Demo Fixture Executable

**Files:**
- Modify: `supabase/config.toml`
- Modify: `supabase/seed/seed.sql`
- Create: `scripts/provision-local-demo-user.sh`
- Modify: `README.md`
- Modify: `apps/lyrica_app/README.md`

- [ ] **Step 1: Expand the seed fixture expectations in prose before editing SQL**

Add a short note to `README.md` and `apps/lyrica_app/README.md` describing the target local fixture:

```text
local Supabase development must provide:
- one documented demo user
- one active membership linked to that user
- three backend-seeded songs matching the current reader slice catalog
```

- [ ] **Step 2: Run the current local reset path to capture the starting behavior**

Run: `./scripts/supabase.sh start`

Expected: PASS or start the local stack if it is not already running.

- [ ] **Step 3: Run the database reset path to validate the current baseline**

Run: `./scripts/db-reset.sh`

Expected: PASS on schema reset, but the resulting seed still lacks an executable auth fixture and three-song parity.

- [ ] **Step 4: Fix the local Supabase config, then update the seed to create a real demo fixture and three-song catalog**

First, update `supabase/config.toml` so the repository-owned seed file is actually loaded during `db reset`. Keep the local Supabase workflow executable through the repository wrapper scripts; if an optional service blocks that path on the supported local engine, prefer the thinnest repository-documented workaround that preserves this slice.

Keep `supabase/seed/seed.sql` focused on public data and three-song parity. Create `scripts/provision-local-demo-user.sh` as the supported local auth bootstrap path.

Use a fixed demo identity:

```sql
insert into public.memberships (organization_id, user_id, scope_type, role_code, status)
values ('11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444', 'organization', 'organization_member', 'active');
```

The provisioning script should create or upsert the local auth user through a supported Supabase Auth path, then ensure the matching membership exists. Also replace the one-song seed with the same three-song catalog currently used by the asset-backed reader slice.

- [ ] **Step 5: Re-run the reset path to verify the executable fixture**

Run: `./scripts/db-reset.sh`

Then run: `./scripts/provision-local-demo-user.sh`

Expected: PASS with the updated seed applied successfully.

- [ ] **Step 6: Verify that the demo user can actually sign in before app work begins**

Run a small smoke check against local Supabase using the documented demo credentials.

Expected: PASS with a real authenticated session. If this fails, fix the provisioning path before continuing to Flutter auth work.

- [ ] **Step 7: Commit**

```bash
git add supabase/config.toml supabase/seed/seed.sql scripts/provision-local-demo-user.sh README.md apps/lyrica_app/README.md docs/plans/2026-03-23-executable-local-supabase-authenticated-song-reading.md
git commit -m "feat(supabase): add local demo auth fixture and song catalog parity"
```

### Task 2: Add Supabase Client Configuration And Bootstrap Initialization

**Files:**
- Modify: `apps/lyrica_app/pubspec.yaml`
- Modify: `apps/lyrica_app/lib/main.dart`
- Modify: `apps/lyrica_app/lib/src/bootstrap/bootstrap.dart`
- Modify: `apps/lyrica_app/lib/src/application/providers.dart`
- Create: `apps/lyrica_app/lib/src/infrastructure/config/supabase_config.dart`
- Create: `apps/lyrica_app/test/infrastructure/config/supabase_config_test.dart`
- Create: `apps/lyrica_app/test/application/providers_test.dart`

- [ ] **Step 1: Write the failing configuration tests**

Add `apps/lyrica_app/test/infrastructure/config/supabase_config_test.dart` to define the environment contract:

```dart
expect(
  SupabaseConfig.fromEnvironment(
    url: 'http://127.0.0.1:54321',
    anonKey: 'anon-key',
  ).url,
  'http://127.0.0.1:54321',
);
```

Also cover a failure when required values are missing.

- [ ] **Step 2: Run the focused configuration test to verify it fails**

Run: `cd apps/lyrica_app && flutter test test/infrastructure/config/supabase_config_test.dart`

Expected: FAIL because `SupabaseConfig` does not exist yet.

- [ ] **Step 3: Add the Supabase dependency and config model**

Modify `apps/lyrica_app/pubspec.yaml` to add `supabase_flutter`.

Create `apps/lyrica_app/lib/src/infrastructure/config/supabase_config.dart`:

```dart
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  factory SupabaseConfig.fromEnvironment({
    String url = const String.fromEnvironment('SUPABASE_URL'),
    String anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
  }) { ... }
}
```

Also add a shared `supabaseClientProvider` in `apps/lyrica_app/lib/src/application/providers.dart` so runtime code and tests have one override seam for the configured `SupabaseClient`.

- [ ] **Step 4: Initialize Supabase during app bootstrap**

Update `apps/lyrica_app/lib/src/bootstrap/bootstrap.dart` to make `bootstrap()` async and call `Supabase.initialize(...)` before `runApp`.

Update `apps/lyrica_app/lib/main.dart`:

```dart
Future<void> main() async {
  await bootstrap();
}
```

- [ ] **Step 5: Re-run the focused configuration test to verify it passes**

Run: `cd apps/lyrica_app && flutter test test/infrastructure/config/supabase_config_test.dart test/application/providers_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyrica_app/pubspec.yaml apps/lyrica_app/lib/main.dart apps/lyrica_app/lib/src/bootstrap/bootstrap.dart apps/lyrica_app/lib/src/application/providers.dart apps/lyrica_app/lib/src/infrastructure/config/supabase_config.dart apps/lyrica_app/test/infrastructure/config/supabase_config_test.dart apps/lyrica_app/test/application/providers_test.dart
git commit -m "feat(app): add Supabase config and bootstrap initialization"
```

### Task 3: Introduce A Single Auth Bootstrap Boundary

**Files:**
- Create: `apps/lyrica_app/lib/src/domain/auth/app_auth_status.dart`
- Create: `apps/lyrica_app/lib/src/domain/auth/app_auth_session.dart`
- Create: `apps/lyrica_app/lib/src/application/auth/auth_repository.dart`
- Create: `apps/lyrica_app/lib/src/application/auth/app_auth_state.dart`
- Create: `apps/lyrica_app/lib/src/application/auth/app_auth_controller.dart`
- Modify: `apps/lyrica_app/lib/src/application/providers.dart`
- Test: `apps/lyrica_app/test/application/auth/app_auth_controller_test.dart`

- [ ] **Step 1: Write the failing auth controller tests**

Add `apps/lyrica_app/test/application/auth/app_auth_controller_test.dart` to define the controller contract:

```dart
expect(controller.state.status, AppAuthStatus.initializing);
await controller.restoreSession();
expect(controller.state.status, AppAuthStatus.signedOut);
```

Also cover:
- restoring a valid session
- transitioning to `sessionExpired`
- sign-out clearing the session state

- [ ] **Step 2: Run the focused auth controller test to verify it fails**

Run: `cd apps/lyrica_app && flutter test test/application/auth/app_auth_controller_test.dart`

Expected: FAIL because the auth types and controller do not exist.

- [ ] **Step 3: Add the minimal auth boundary types**

Create:

```dart
enum AppAuthStatus { initializing, signedOut, signedIn, sessionExpired }

abstract interface class AuthRepository {
  Future<AppAuthSession?> restoreSession();
  Stream<AppAuthSession?> watchSession();
  Future<AppAuthSession> signIn({required String email, required String password});
  Future<void> signOut();
}
```

Keep `AppAuthState` focused on status plus the optional session payload.

- [ ] **Step 4: Implement the controller and provider ownership**

Add an `AppAuthController` that owns:
- initial restore
- session stream subscription
- sign-in
- sign-out
- session-expired transition

Wire it through `apps/lyrica_app/lib/src/application/providers.dart` so there is one provider tree owner for auth/bootstrap state.

- [ ] **Step 5: Re-run the focused auth controller test to verify it passes**

Run: `cd apps/lyrica_app && flutter test test/application/auth/app_auth_controller_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyrica_app/lib/src/domain/auth apps/lyrica_app/lib/src/application/auth apps/lyrica_app/lib/src/application/providers.dart apps/lyrica_app/test/application/auth/app_auth_controller_test.dart
git commit -m "feat(auth): add app auth bootstrap controller"
```

### Task 4: Add The Supabase Auth Adapter, Sign-In Screen, And Router Redirect Policy

**Files:**
- Create: `apps/lyrica_app/lib/src/infrastructure/auth/supabase_auth_repository.dart`
- Create: `apps/lyrica_app/lib/src/presentation/auth/sign_in_screen.dart`
- Create: `apps/lyrica_app/lib/src/router/auth_router_refresh_notifier.dart`
- Modify: `apps/lyrica_app/lib/src/router/app_routes.dart`
- Modify: `apps/lyrica_app/lib/src/router/app_router.dart`
- Modify: `apps/lyrica_app/lib/src/app/lyrica_app.dart`
- Modify: `apps/lyrica_app/lib/src/shared/app_strings.dart`
- Test: `apps/lyrica_app/test/infrastructure/auth/supabase_auth_repository_test.dart`
- Test: `apps/lyrica_app/test/presentation/auth/sign_in_screen_test.dart`
- Test: `apps/lyrica_app/test/router/app_router_test.dart`
- Test: `apps/lyrica_app/test/app/lyrica_app_test.dart`

- [ ] **Step 1: Write the failing router and sign-in widget tests**

Update the tests to require:

```dart
expect(AppRoutes.signIn.path, '/sign-in');
expect(find.text('Sign in'), findsOneWidget);
expect(find.text('Egy út'), findsNothing);
```

Add a route test that verifies:
- signed-out users land on `/sign-in`
- signed-in users are redirected away from `/sign-in`
- signed-out users cannot open `/songs/:songId`

- [ ] **Step 2: Run the focused routing and sign-in tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/router/app_router_test.dart test/presentation/auth/sign_in_screen_test.dart test/app/lyrica_app_test.dart`

Expected: FAIL because sign-in route and redirect logic do not exist.

- [ ] **Step 3: Implement the Supabase auth adapter**

Create `apps/lyrica_app/lib/src/infrastructure/auth/supabase_auth_repository.dart` to map the Supabase session model into `AppAuthSession`.

Keep the adapter thin:

```dart
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final SupabaseClient _client;
  ...
}
```

- [ ] **Step 4: Add the sign-in screen and centralized router redirect**

Add:
- a `signIn` route constant
- a small sign-in screen with email/password fields and a submit action
- an auth-driven router refresh bridge, such as `auth_router_refresh_notifier.dart`
- a router redirect callback that reads the auth/bootstrap state and decides between `/sign-in`, `/`, and `/songs/:songId`

Pass the router through `LyricaApp` the same way the current tests do.

- [ ] **Step 5: Re-run the focused routing and sign-in tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/router/app_router_test.dart test/presentation/auth/sign_in_screen_test.dart test/app/lyrica_app_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyrica_app/lib/src/infrastructure/auth/supabase_auth_repository.dart apps/lyrica_app/lib/src/presentation/auth/sign_in_screen.dart apps/lyrica_app/lib/src/router/auth_router_refresh_notifier.dart apps/lyrica_app/lib/src/router/app_routes.dart apps/lyrica_app/lib/src/router/app_router.dart apps/lyrica_app/lib/src/app/lyrica_app.dart apps/lyrica_app/lib/src/shared/app_strings.dart apps/lyrica_app/test/infrastructure/auth/supabase_auth_repository_test.dart apps/lyrica_app/test/presentation/auth/sign_in_screen_test.dart apps/lyrica_app/test/router/app_router_test.dart apps/lyrica_app/test/app/lyrica_app_test.dart
git commit -m "feat(auth): add sign-in screen and router redirects"
```

### Task 5: Swap The Song Repository To Supabase While Preserving Local Parsing

**Files:**
- Create: `apps/lyrica_app/lib/src/infrastructure/song_library/supabase_song_repository.dart`
- Modify: `apps/lyrica_app/lib/src/presentation/song_library/song_library_providers.dart`
- Modify: `apps/lyrica_app/lib/src/application/song_library/song_library_service.dart`
- Modify: `apps/lyrica_app/lib/src/domain/song/song_not_found_exception.dart`
- Test: `apps/lyrica_app/test/infrastructure/song_library/supabase_song_repository_test.dart`
- Test: `apps/lyrica_app/test/presentation/song_library/song_library_providers_test.dart`
- Test: `apps/lyrica_app/test/presentation/song_library/song_list_screen_test.dart`

- [ ] **Step 1: Write the failing Supabase repository and provider tests**

Define the repository swap contract:

```dart
expect(await repository.listSongs(), hasLength(3));
expect((await repository.listSongs()).first, isA<SongSummary>());
expect((await repository.getSongSource(songId)).source, contains('{title:'));
```

Also cover:
- mapping a missing row to `SongNotFoundException`
- keeping the provider graph on `SongSummary` + raw `SongSource`
- not invoking the parser inside the repository

- [ ] **Step 2: Run the focused repository and provider tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/infrastructure/song_library/supabase_song_repository_test.dart test/presentation/song_library/song_library_providers_test.dart test/presentation/song_library/song_list_screen_test.dart`

Expected: FAIL because the Supabase repository implementation and auth-aware provider wiring do not exist.

- [ ] **Step 3: Implement the Supabase-backed song repository**

Create `apps/lyrica_app/lib/src/infrastructure/song_library/supabase_song_repository.dart`:

```dart
class SupabaseSongRepository implements SongRepository {
  SupabaseSongRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<SongSummary>> listSongs() { ... }

  @override
  Future<SongSource> getSongSource(String id) { ... }
}
```

Keep the query contract limited to:
- `id`
- `title`
- `chordpro_source`

- [ ] **Step 4: Update the provider graph to select the backend repository**

Modify `song_library_providers.dart` so signed-in app flows resolve the Supabase repository and keep:
- parser ownership in the existing parser provider
- reader result assembly in the current provider layer
- diagnostic logging behavior in the current provider layer

- [ ] **Step 5: Re-run the focused repository and provider tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/infrastructure/song_library/supabase_song_repository_test.dart test/presentation/song_library/song_library_providers_test.dart test/presentation/song_library/song_list_screen_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyrica_app/lib/src/infrastructure/song_library/supabase_song_repository.dart apps/lyrica_app/lib/src/presentation/song_library/song_library_providers.dart apps/lyrica_app/lib/src/application/song_library/song_library_service.dart apps/lyrica_app/lib/src/domain/song/song_not_found_exception.dart apps/lyrica_app/test/infrastructure/song_library/supabase_song_repository_test.dart apps/lyrica_app/test/presentation/song_library/song_library_providers_test.dart apps/lyrica_app/test/presentation/song_library/song_list_screen_test.dart
git commit -m "feat(song-library): add Supabase song repository"
```

### Task 6: Handle Reader Failure States And Session-Expired Recovery

**Files:**
- Modify: `apps/lyrica_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyrica_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyrica_app/lib/src/shared/app_strings.dart`
- Test: `apps/lyrica_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Test: `apps/lyrica_app/test/integration/song_reader_flow_test.dart`

- [ ] **Step 1: Write the failing screen tests for unavailable and expired-session states**

Add tests that require:
- a retryable backend-failure message on list or reader load failure
- a not-found or unavailable state when a song cannot be loaded
- a session-expired message that returns the user to sign-in instead of leaving the reader in a broken state

Example expectation:

```dart
expect(find.text('This song is unavailable.'), findsOneWidget);
expect(find.text('Your session expired. Please sign in again.'), findsOneWidget);
```

- [ ] **Step 2: Run the focused screen and flow tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/presentation/song_reader/song_reader_screen_test.dart test/integration/song_reader_flow_test.dart`

Expected: FAIL because the current UI only covers the asset-backed happy path.

- [ ] **Step 3: Implement the missing load-state surfaces**

Update the list and reader screens so they map provider failures into explicit surfaces for:
- retryable backend failure
- unavailable or not-found song
- session-expired re-authentication

Keep the screens thin; application/auth state should still own the actual state transitions.

- [ ] **Step 4: Re-run the focused screen and flow tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/presentation/song_reader/song_reader_screen_test.dart test/integration/song_reader_flow_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyrica_app/lib/src/presentation/song_reader/song_reader_screen.dart apps/lyrica_app/lib/src/presentation/song_library/song_list_screen.dart apps/lyrica_app/lib/src/shared/app_strings.dart apps/lyrica_app/test/presentation/song_reader/song_reader_screen_test.dart apps/lyrica_app/test/integration/song_reader_flow_test.dart
git commit -m "feat(reader): add backend-aware failure states"
```

### Task 7: Add Real Local Supabase Verification And End-To-End Coverage

**Files:**
- Create: `apps/lyrica_app/test/integration/authenticated_song_reader_flow_test.dart`
- Modify: `scripts/verify.sh`
- Modify: `README.md`
- Modify: `docs/testing/testing-strategy.md`

- [ ] **Step 1: Write the failing real-backend integration test**

Add `apps/lyrica_app/test/integration/authenticated_song_reader_flow_test.dart` to exercise the true local path:

```dart
await tester.enterText(find.byKey(const Key('emailField')), 'demo@lyrica.local');
await tester.enterText(find.byKey(const Key('passwordField')), 'demo-pass-123');
await tester.tap(find.byKey(const Key('signInButton')));
await tester.pumpAndSettle();

expect(find.text('Egy út'), findsOneWidget);
```

Also add an out-of-scope assertion using a hidden seeded song or a second organization fixture.

- [ ] **Step 2: Run the targeted integration test against the local backend to verify it fails**

Run: `./scripts/supabase.sh start`

Then run: `./scripts/db-reset.sh`

Then run: `./scripts/provision-local-demo-user.sh`

Then run: `cd apps/lyrica_app && flutter test test/integration/authenticated_song_reader_flow_test.dart --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<local-anon-key>`

Expected: FAIL because the end-to-end authenticated flow is not wired yet.

- [ ] **Step 3: Extend the verification path to cover the real backend slice**

Modify `scripts/verify.sh` so the non-`--skip-migrations` path also:
- starts or reuses the local Supabase stack
- resets the local database
- provisions the local demo auth user
- runs the real backend authenticated flow test

Document the required local environment values in `README.md`.

- [ ] **Step 4: Re-run the full verification path to verify it passes**

Run: `./scripts/verify.sh`

Expected: PASS with Flutter checks, migration linting, local reset, and authenticated backend flow coverage.

- [ ] **Step 5: Commit**

```bash
git add apps/lyrica_app/test/integration/authenticated_song_reader_flow_test.dart scripts/verify.sh README.md docs/testing/testing-strategy.md
git commit -m "test(app): verify authenticated backend song reading locally"
```

### Task 8: Align Repository Documentation With The New Slice

**Files:**
- Modify: `README.md`
- Modify: `docs/product/vision.md`
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/workflows/development-workflow.md`
- Modify: `apps/lyrica_app/README.md`

- [ ] **Step 1: Update product and architecture wording**

Revise the repository docs so they no longer describe the app as only an asset-backed reader slice.

Add explicit wording that the new slice proves:
- local executable Supabase workflow
- authenticated backend-backed song reads
- continued in-app ChordPro parsing and reader rendering

- [ ] **Step 2: Update domain and testing docs**

Clarify:
- songs are now proven through a backend-backed read path in local development
- auth bootstrap and RLS-backed read behavior are required test subjects for this slice

- [ ] **Step 3: Run the repository verification path one last time**

Run: `./scripts/verify.sh`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/product/vision.md docs/domain/domain-model.md docs/architecture/architecture.md docs/testing/testing-strategy.md docs/workflows/development-workflow.md apps/lyrica_app/README.md
git commit -m "docs(auth-song-reader): align repository docs with backend slice"
```
