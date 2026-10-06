# Cross-User Local-First Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A local-first read context (song catalog, active planning context, planning sync state) belongs only to the user the app is acting for. It is never established from another user's identity, it is released when the current user changes, and no holder adopts another user's context.

**Architecture:** One source, `AppAuthState.currentUserId`, encoded in two places that compare against it. `AppAuthController.currentUserLastKnownIdentity` is the only identity the local-first readers see (XU1). `CurrentUserOwnership` is the rule each in-memory holder applies on the auth edge through a new `handleCurrentUser` method (XU2). In memory only: no purge, no `PurgeReason`, no store write or delete.

**Tech Stack:** Flutter, Dart 3, Riverpod 3 (legacy `ChangeNotifierProvider`), Drift, flutter_test. No new Riverpod or Supabase API is used: the change adds plain `ChangeNotifier` methods called from the existing auth listeners.

**Spec:** `docs/specs/2026-10-06-cross-user-local-first-ownership.md` (decisions XU1–XU4, findings F6, F7, R-A, R-B, F8, acceptance AC1–AC8)
**Branch:** `fix/cross-user-local-first-leaks` (from `main` at `6e82118`)
**Discipline:** TDD. Every task starts with a red test that is run and seen failing for the stated reason. Never edit an existing test to make it pass. If an existing test fails and the plan does not name it as an intentional behaviour change: STOP and report.
**Verification after every task:** the FULL suite and the analyzer, never a subset:

```bash
cd apps/lyron_app && flutter test
```

```bash
cd apps/lyron_app && flutter analyze
```

Run `dart format lib test` before each commit. STOP and report if the full suite shows a Riverpod error during a provider build ("Tried to modify a provider while the widget tree was building" or similar).

---

## Facts the implementer needs (verified while planning)

- **The reproduction suite already exists:** `apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart`, committed with the spec. It has ten tests. Three are green today and must stay green (with songs and plans cached nothing of A's survives B's sign-in; cancelling B's reauth returns A's data; A re-authenticating keeps A's data). Seven carry `skip: 'red until Task N ...'`. Each task removes the skip of its own tests, runs them red, then makes them green. Do not change the fixture.
- **Red output recorded on 2026-10-06** (skips removed, pre-fix code): the six visibility tests fail with `Expected: not 'user-a'  Actual: 'user-a'`. The F8 test fails with `Expected: <1>  Actual: <0>` (A's pending planning mutation was deleted).
- **Line references** below are to `main` at `6e82118`. Match the quoted code, not the line number.
- **First-observation rule (why `observe` does not report a change the first time).** `planningSyncControllerProvider` (`lib/src/application/planning_providers.dart:391-395`) calls `controller.handleActiveContextChanged(activeContext)` before `handleAuthStateChanged(authController.state)`. If the first `handleCurrentUser` advanced the boundary generation, that in-flight call would go stale and planning would never adopt the active context at provider creation.
- **Not on `signedOut`.** `SongCatalogController.handleExplicitSignOut` takes the purge user from `_state.context?.userId` first (`song_catalog_controller.dart:686-703`), and `PlanningSyncController.handleExplicitSignOut` takes it from `_state.userId` first (`planning_sync_controller.dart:308-343`). The release must not run on the sign-out edge, or those purge targets would change in ordinary cases. `AppAuthState.currentUserId` is null for `signedOut` and `initializing`, so calling `handleCurrentUser` only for a non-null `currentUserId` already excludes them.
- **No build-time notifications.** Each provider also calls `handleAuthStateChanged` while it is being built. At that moment each holder's state is empty (`initial()` or null), so `handleCurrentUser` cannot notify during a build. Keep it that way: never notify from `handleCurrentUser` unless a foreign context is actually held.
- **Subclasses.** `_RecordingController extends AppAuthController` (two presentation tests), `_NoopSongCatalogController extends SongCatalogController`, `_NoopPlanningSyncController` and `_RecordingPlanningSyncController extends PlanningSyncController`. All use `extends`, so new members are inherited. No fake implements these classes' interfaces.
- **Direct `handleActiveContextChanged` callers in tests** (`planning_sync_controller_test.dart`, `providers_test.dart`, the planning integration tests) never call `handleCurrentUser`, so `CurrentUserOwnership.allows` returns true for them (nothing observed). `providers_test.dart` passes only `user-1` contexts under a `user-1` session.

## File map

| File | Change |
|---|---|
| `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart` | add `currentUserLastKnownIdentity` (Task 1) |
| `apps/lyron_app/lib/src/application/auth_providers.dart` | gate `knownOrganizationIdReader` uses the getter (Task 1) |
| `apps/lyron_app/lib/src/application/song_catalog_providers.dart` | identity reader uses the getter (Task 2); `handleCurrentUser` wiring (Task 5) |
| `apps/lyron_app/lib/src/application/planning_providers.dart` | identity reader uses the getter (Task 2); `handleCurrentUser` wiring for planning sync (Task 3) and active planning (Task 4) |
| `apps/lyron_app/lib/src/application/auth/current_user_ownership.dart` | **new** (Task 3) |
| `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart` | `handleCurrentUser`, adoption guard (Task 3) |
| `apps/lyron_app/lib/src/application/planning/active_planning_context_controller.dart` | `handleCurrentUser`, refresh and mirror guards (Task 4) |
| `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart` | `handleCurrentUser` (Task 5) |
| `apps/lyron_app/test/application/auth/app_auth_controller_test.dart` | getter tests (Task 1) |
| `apps/lyron_app/test/application/auth/current_user_ownership_test.dart` | **new** (Task 3) |
| `apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart` | remove skips (Tasks 2–5) |
| docs (Task 6) | ADR-037, ADR-040, ADR-029, architecture, testing strategy, deferred entry, roadmap, spec status |

---

### Task 1: `AppAuthController.currentUserLastKnownIdentity` (XU1)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/auth_providers.dart`
- Test: `apps/lyron_app/test/application/auth/app_auth_controller_test.dart`

- [ ] **Step 1: Write the failing tests.** Append this group at the end of `main()` in `app_auth_controller_test.dart` (before the final closing `}` of `main`):

```dart
  group('currentUserLastKnownIdentity (XU1)', () {
    test('is the identity while its user is current', () async {
      final repo = _FakeAuthRepository();
      final identityStore = _FakeLastKnownIdentityStore()
        ..value = const LastKnownIdentity(
          userId: 'u1',
          email: 'u1@x',
          organizationId: 'org-1',
        );
      final controller = AppAuthController(
        repo,
        lastKnownIdentityStore: identityStore,
      );

      await controller.restoreSession();
      expect(controller.state.status, AppAuthStatus.sessionExpired);
      expect(controller.currentUserLastKnownIdentity?.organizationId, 'org-1');

      repo.emit(const AppAuthSession(userId: 'u1', email: 'u1@x'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, AppAuthStatus.signedIn);
      expect(controller.currentUserLastKnownIdentity?.userId, 'u1');
    });

    test('is null while another user is current, with or without a live '
        'session (F6)', () async {
      final repo = _FakeAuthRepository();
      final identityStore = _FakeLastKnownIdentityStore()
        ..value = const LastKnownIdentity(
          userId: 'u1',
          email: 'u1@x',
          organizationId: 'org-1',
        );
      final controller = AppAuthController(
        repo,
        lastKnownIdentityStore: identityStore,
      );
      await controller.restoreSession();

      repo.emit(const AppAuthSession(userId: 'u2', email: 'u2@x'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.currentUserId, 'u2');
      expect(controller.currentUserLastKnownIdentity, isNull);

      // u2's session is lost while u1's identity is still on file.
      repo.emit(null);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, AppAuthStatus.sessionExpired);
      expect(controller.state.currentUserId, 'u2');
      expect(controller.lastKnownIdentity?.userId, 'u1');
      expect(controller.currentUserLastKnownIdentity, isNull);
    });

    test('is null when nobody is current', () async {
      final repo = _FakeAuthRepository();
      final identityStore = _FakeLastKnownIdentityStore()
        ..value = const LastKnownIdentity(
          userId: 'u1',
          email: 'u1@x',
          organizationId: 'org-1',
        );
      final controller = AppAuthController(
        repo,
        lastKnownIdentityStore: identityStore,
      );
      expect(controller.state.status, AppAuthStatus.initializing);
      expect(controller.currentUserLastKnownIdentity, isNull);

      await controller.restoreSession();
      await controller.signOut();
      expect(controller.state.status, AppAuthStatus.signedOut);
      expect(controller.currentUserLastKnownIdentity, isNull);
    });
  });
```

- [ ] **Step 2: Run, expect a compile failure.**

```bash
cd apps/lyron_app && flutter test test/application/auth/app_auth_controller_test.dart
```

Expected: compilation fails with `The getter 'currentUserLastKnownIdentity' isn't defined for the type 'AppAuthController'`.

- [ ] **Step 3: Add the getter.** In `app_auth_controller.dart`, directly after

```dart
  LastKnownIdentity? get lastKnownIdentity => _identity;
```

insert:

```dart

  /// The last known identity, only when it belongs to the user the app is
  /// acting for ([AppAuthState.currentUserId]): null when nobody is current,
  /// when no identity is on file, or when the identity is another user's.
  ///
  /// The one identity every local-first reader sees (the catalog and
  /// planning local-first contexts and the membership gate's known
  /// organization), so none of them can build a read context from a
  /// different user's identity. Losing user B's session while the device
  /// still holds user A's identity yields `sessionExpired(B)`; reading the
  /// raw identity there established A's context for B (F6,
  /// docs/specs/2026-10-06-cross-user-local-first-ownership.md, XU1).
  LastKnownIdentity? get currentUserLastKnownIdentity {
    final identity = _identity;
    final currentUserId = _state.currentUserId;
    if (identity == null ||
        currentUserId == null ||
        identity.userId != currentUserId) {
      return null;
    }
    return identity;
  }
```

- [ ] **Step 4: The gate reads the same getter (no behaviour change).** In `auth_providers.dart`, inside `activeMembershipControllerProvider`, replace

```dart
        knownOrganizationIdReader: () {
          final userId = authController.state.currentUserId;
          final identity = authController.lastKnownIdentity;
          if (userId == null || identity == null || identity.userId != userId) {
            return null;
          }
          return identity.organizationId;
        },
```

with

```dart
        knownOrganizationIdReader: () =>
            authController.currentUserLastKnownIdentity?.organizationId,
```

- [ ] **Step 5: Run the file, then the full suite and the analyzer.**

```bash
cd apps/lyron_app && flutter test test/application/auth/app_auth_controller_test.dart
```

Expected: all pass. Then run the full `flutter test` and `flutter analyze` (see the header). Expected: green; the seven reproduction tests are still skipped.

- [ ] **Step 6: Commit.**

```bash
git add apps/lyron_app/lib/src/application/auth/app_auth_controller.dart apps/lyron_app/lib/src/application/auth_providers.dart apps/lyron_app/test/application/auth/app_auth_controller_test.dart
git commit -m "feat(auth): current user's last known identity getter (XU1)"
```

---

### Task 2: The local-first identity readers see only the current user's identity (XU1, closes F6)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/song_catalog_providers.dart`
- Modify: `apps/lyron_app/lib/src/application/planning_providers.dart`
- Modify (comment only): `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`
- Test: `apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart`

- [ ] **Step 1: Unskip the two F6 tests.** In the group `establishment from another user's identity (F6)`, delete the `skip: 'red until Task 2 (XU1); spec 2026-10-06 cross-user ownership'` argument from both tests (keep the closing `});`).

- [ ] **Step 2: Run, expect red.**

```bash
cd apps/lyron_app && flutter test test/integration/cross_user_local_first_leak_test.dart
```

Expected: the two F6 tests fail with `Expected: not 'user-a'  Actual: 'user-a'`; three pass; five are skipped.

- [ ] **Step 3: Catalog reader.** In `song_catalog_providers.dart`, replace

```dart
        lastKnownIdentityReader: () {
          final identity = authController.lastKnownIdentity;
          if (identity == null) return null;
```

with

```dart
        // XU1 (docs/specs/2026-10-06-cross-user-local-first-ownership.md):
        // only the current user's identity; another user's is never read.
        lastKnownIdentityReader: () {
          final identity = authController.currentUserLastKnownIdentity;
          if (identity == null) return null;
```

- [ ] **Step 4: Planning reader.** In `planning_providers.dart`, inside `planningSyncControllerProvider`, replace

```dart
        lastKnownIdentityReader: () {
          final identity = authController.lastKnownIdentity;
          if (identity == null) return null;
```

with

```dart
        // XU1 (docs/specs/2026-10-06-cross-user-local-first-ownership.md):
        // only the current user's identity; another user's is never read.
        lastKnownIdentityReader: () {
          final identity = authController.currentUserLastKnownIdentity;
          if (identity == null) return null;
```

- [ ] **Step 5: Correct the R2 comment (comment only).** In `planning_sync_controller.dart`, inside `_tryEstablishLocalFirstContext`, replace

```dart
    // user. Without a live session (sessionExpired) the identity's user is
    // the only one there is. Using identity.userId unconditionally
```

with

```dart
    // user. Without a live session (sessionExpired) the identity's user is
    // used; the provider passes only the current user's identity (XU1,
    // docs/specs/2026-10-06-cross-user-local-first-ownership.md), so that
    // is the last known session's user. Using identity.userId unconditionally
```

- [ ] **Step 6: Run the file, then the full suite and the analyzer.**

```bash
cd apps/lyron_app && flutter test test/integration/cross_user_local_first_leak_test.dart
```

Expected: five pass, five skipped. Then the full `flutter test` and `flutter analyze`: green.

- [ ] **Step 7: Commit.**

```bash
git add apps/lyron_app/lib/src/application/song_catalog_providers.dart apps/lyron_app/lib/src/application/planning_providers.dart apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart
git commit -m "fix(local-first): never establish a context from another user's identity (F6)"
```

---

### Task 3: `CurrentUserOwnership`; planning sync follows the current user (XU2, closes F7, F8, R-B planning)

**Files:**
- Create: `apps/lyron_app/lib/src/application/auth/current_user_ownership.dart`
- Create: `apps/lyron_app/test/application/auth/current_user_ownership_test.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/planning_providers.dart`
- Test: `apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart`

- [ ] **Step 1: Write the unit test for the rule.** Create `test/application/auth/current_user_ownership_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/current_user_ownership.dart';

void main() {
  test('allows everyone before the first observation', () {
    final ownership = CurrentUserOwnership();

    expect(ownership.userId, isNull);
    expect(ownership.allows('user-a'), isTrue);
    expect(ownership.allows('user-b'), isTrue);
  });

  test('the first observation is not a change and allows only that user', () {
    final ownership = CurrentUserOwnership();

    expect(ownership.observe('user-a'), isFalse);
    expect(ownership.userId, 'user-a');
    expect(ownership.allows('user-a'), isTrue);
    expect(ownership.allows('user-b'), isFalse);
  });

  test('observing the same user again is not a change', () {
    final ownership = CurrentUserOwnership()..observe('user-a');

    expect(ownership.observe('user-a'), isFalse);
    expect(ownership.allows('user-a'), isTrue);
  });

  test('observing a different user is a change and moves ownership', () {
    final ownership = CurrentUserOwnership()..observe('user-a');

    expect(ownership.observe('user-b'), isTrue);
    expect(ownership.allows('user-b'), isTrue);
    expect(ownership.allows('user-a'), isFalse);

    // A cancelled reauth returns to the prior user: also a change.
    expect(ownership.observe('user-a'), isTrue);
    expect(ownership.allows('user-a'), isTrue);
    expect(ownership.allows('user-b'), isFalse);
  });
}
```

- [ ] **Step 2: Unskip the three Task 3 integration tests.** In the group `contexts held for the previous user (F7)`, delete `skip: 'red until Task 3 (XU2); spec 2026-10-06 cross-user ownership'` from: "planning established for A from a sessionExpired cold start …", "B's planning organization answering … (F8)", and "a planning establishment started for A does not land after B signs in".

- [ ] **Step 3: Run both, expect red.**

```bash
cd apps/lyron_app && flutter test test/application/auth/current_user_ownership_test.dart test/integration/cross_user_local_first_leak_test.dart
```

Expected: the unit test fails to compile (`current_user_ownership.dart` does not exist). Comment out nothing; run the integration file on its own to see its red:

```bash
cd apps/lyron_app && flutter test test/integration/cross_user_local_first_leak_test.dart
```

Expected: F7 and the planning in-flight test fail with `Expected: not 'user-a'  Actual: 'user-a'`; F8 fails with `Expected: <1>  Actual: <0>`; five pass; two skipped.

- [ ] **Step 4: Create the rule.** Create `lib/src/application/auth/current_user_ownership.dart`:

```dart
/// XU2 (docs/specs/2026-10-06-cross-user-local-first-ownership.md): the one
/// ownership rule every in-memory local-first context holder applies (the
/// song catalog context, the active planning context and the planning sync
/// state). A held or newly adopted context may belong only to the user the
/// app is acting for, `AppAuthState.currentUserId`.
///
/// Holders feed it that user on every signedIn and sessionExpired
/// notification. Explicit sign-out is not fed here: the sign-out handlers
/// reset the holders and choose the purge target themselves (ADR-035,
/// unchanged).
final class CurrentUserOwnership {
  String? _userId;

  /// The most recently observed current user; null until the first
  /// observation.
  String? get userId => _userId;

  /// Records [userId] as the current user. Returns true only when it
  /// replaces a different, previously observed user: work the holder
  /// started for that user must stop, and what it holds for them must go.
  ///
  /// The first observation returns false. The holder is new and has started
  /// nothing for an earlier user; reporting a change there would invalidate
  /// work it started for this same user while its provider was being built.
  bool observe(String userId) {
    final previous = _userId;
    _userId = userId;
    return previous != null && previous != userId;
  }

  /// Whether a context owned by [ownerUserId] may be held or adopted. Before
  /// the first observation nothing is known, and the holder's existing
  /// guards apply.
  bool allows(String ownerUserId) => _userId == null || _userId == ownerUserId;
}
```

- [ ] **Step 5: `PlanningSyncController`.** In `planning_sync_controller.dart`:

(a) Add the import, keeping the import list sorted. Replace

```dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
```

with

```dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/current_user_ownership.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
```

(b) Add the field. Replace

```dart
  bool _refreshQueued = false;
  bool _disposed = false;

  PlanningSyncState get state => _state;
```

with

```dart
  bool _refreshQueued = false;
  bool _disposed = false;
  final _ownership = CurrentUserOwnership();

  PlanningSyncState get state => _state;

  /// XU2 (docs/specs/2026-10-06-cross-user-local-first-ownership.md): called
  /// on every signedIn and sessionExpired notification with
  /// AppAuthState.currentUserId, before the status handlers. When the
  /// current user changes, refresh and local-first work started for the
  /// previous user is invalidated, and planning state held for another user
  /// is reset. This runs on the auth edge itself: the I3 guard in
  /// _refreshPlanning runs only if a refresh runs, and _readPlanningOrThrow
  /// skips the refresh while local data is present (F7). Releasing the
  /// previous boundary here also means handleActiveContextChanged finds no
  /// previous boundary to delete when the new user's arrives (F8). In memory
  /// only: no local data is deleted.
  void handleCurrentUser(String currentUserId) {
    final changed = _ownership.observe(currentUserId);
    final heldUserId = _state.userId;
    final holdsForeign = heldUserId != null && heldUserId != currentUserId;
    if (!changed && !holdsForeign) {
      return;
    }
    _advanceBoundaryGeneration();
    _invalidateRefreshGeneration();
    if (holdsForeign) {
      _setState(
        const PlanningSyncState.initial().copyWith(
          accessStatus: PlanningAccessStatus.signedIn,
        ),
      );
    }
  }
```

(c) Guard adoption. Replace

```dart
    ActivePlanningReadContext? context, {
    bool refresh = true,
  }) async {
    final boundaryGeneration = _advanceBoundaryGeneration();
```

with

```dart
    ActivePlanningReadContext? context, {
    bool refresh = true,
  }) async {
    if (context != null && !_ownership.allows(context.userId)) {
      // XU2: a mirrored boundary owned by a user who is no longer current (a
      // notification queued before the user changed) is never adopted, and
      // must not disturb the current user's work.
      return;
    }
    final boundaryGeneration = _advanceBoundaryGeneration();
```

- [ ] **Step 6: Wire it.** In `planning_providers.dart`, inside `planningSyncControllerProvider`, replace

```dart
      void handleAuthStateChanged(AppAuthState authState) {
        switch (authState.status) {
          case AppAuthStatus.initializing:
            return;
          case AppAuthStatus.signedOut:
            unawaited(controller.handleExplicitSignOut());
            return;
          case AppAuthStatus.sessionExpired:
            unawaited(controller.handleSessionExpired());
```

with

```dart
      void handleAuthStateChanged(AppAuthState authState) {
        // XU2: ownership first, so the status handlers below never act on
        // planning state held for an earlier user. Null for initializing and
        // signedOut; the sign-out handler owns that edge.
        final currentUserId = authState.currentUserId;
        if (currentUserId != null) {
          controller.handleCurrentUser(currentUserId);
        }
        switch (authState.status) {
          case AppAuthStatus.initializing:
            return;
          case AppAuthStatus.signedOut:
            unawaited(controller.handleExplicitSignOut());
            return;
          case AppAuthStatus.sessionExpired:
            unawaited(controller.handleSessionExpired());
```

- [ ] **Step 7: Run both files, then the full suite and the analyzer.**

```bash
cd apps/lyron_app && flutter test test/application/auth/current_user_ownership_test.dart test/integration/cross_user_local_first_leak_test.dart
```

Expected: the unit tests pass; the integration file has eight passing and two skipped. Then the full `flutter test` and `flutter analyze`: green.

- [ ] **Step 8: Commit.**

```bash
git add apps/lyron_app/lib/src/application/auth/current_user_ownership.dart apps/lyron_app/test/application/auth/current_user_ownership_test.dart apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart apps/lyron_app/lib/src/application/planning_providers.dart apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart
git commit -m "fix(planning): planning state follows the current user (F7, F8)"
```

---

### Task 4: The active planning context follows the current user (XU2, closes R-A)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/active_planning_context_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/planning_providers.dart`
- Test: `apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart`

- [ ] **Step 1: Unskip.** Delete `skip: 'red until Task 4 (XU2); spec 2026-10-06 cross-user ownership'` from "the active planning context held for A does not survive B's sign-in".

- [ ] **Step 2: Run, expect red.**

```bash
cd apps/lyron_app && flutter test test/integration/cross_user_local_first_leak_test.dart
```

Expected: that test fails with `Expected: not 'user-a'  Actual: 'user-a'` (on `activePlanningUserId`); eight pass; one skipped.

- [ ] **Step 3: `ActivePlanningContextController`.** In `active_planning_context_controller.dart`:

(a) Import. Replace

```dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
```

with

```dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/current_user_ownership.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
```

(b) Field and method. Replace

```dart
  ActivePlanningReadContext? _state;
  bool _verifiedEmptyMembershipSeen = false;

  ActivePlanningReadContext? get state => _state;
```

with

```dart
  ActivePlanningReadContext? _state;
  bool _verifiedEmptyMembershipSeen = false;
  final _ownership = CurrentUserOwnership();

  ActivePlanningReadContext? get state => _state;

  /// XU2 (docs/specs/2026-10-06-cross-user-local-first-ownership.md): called
  /// on every signedIn and sessionExpired notification with
  /// AppAuthState.currentUserId, before the status handlers. [refresh] keeps
  /// an existing context on a connectivity failure and sessionExpired leaves
  /// the context alone, so a context held for the previous user survived a
  /// different user's offline sign-in (R-A). In memory only.
  void handleCurrentUser(String currentUserId) {
    _ownership.observe(currentUserId);
    final state = _state;
    if (state != null && !_ownership.allows(state.userId)) {
      _verifiedEmptyMembershipSeen = false;
      _setState(null);
    }
  }
```

(c) `refresh()`: no outcome after an await once the user changed. Replace

```dart
    } on Object catch (error) {
      if (isConnectivityFailure(error)) {
        organizationLookupWasConnectivityFailure = true;
```

with

```dart
    } on Object catch (error) {
      // XU2: the lookup awaited. If the current user changed meanwhile, this
      // outcome is not the current user's to apply, not even as a clear().
      if (!_ownership.allows(session.userId)) {
        return;
      }
      if (isConnectivityFailure(error)) {
        organizationLookupWasConnectivityFailure = true;
```

then replace

```dart
    if (reachedVerifiedEmpty) {
      _verifiedEmptyMembershipSeen = true;
```

with

```dart
    // XU2: the same check after the lookup (or the cached fallback read).
    if (!_ownership.allows(session.userId)) {
      return;
    }

    if (reachedVerifiedEmpty) {
      _verifiedEmptyMembershipSeen = true;
```

then replace

```dart
    _setState(
      organizationId == null
          ? null
          : ActivePlanningReadContext(
              userId: session.userId,
              organizationId: organizationId,
            ),
    );
  }
```

with

```dart
    // XU2: the marker clear above awaited; check again before committing.
    if (!_ownership.allows(session.userId)) {
      return;
    }
    _setState(
      organizationId == null
          ? null
          : ActivePlanningReadContext(
              userId: session.userId,
              organizationId: organizationId,
            ),
    );
  }
```

(d) Mirror guard. Replace

```dart
  void syncToCatalogContext(ActiveCatalogContext? context) {
    if (context == null) {
```

with

```dart
  void syncToCatalogContext(ActiveCatalogContext? context) {
    if (context != null && !_ownership.allows(context.userId)) {
      // XU2: a catalog context of a user who is no longer current (a
      // notification queued before the user changed) is never mirrored.
      return;
    }
    if (context == null) {
```

- [ ] **Step 4: Wire it.** In `planning_providers.dart`, inside `activePlanningContextControllerProvider`, replace

```dart
      void handleAuthStateChanged(AppAuthState authState) {
        switch (authState.status) {
          case AppAuthStatus.initializing:
            return;
          case AppAuthStatus.signedOut:
            controller.resetForSessionLifecycle();
            return;
```

with

```dart
      void handleAuthStateChanged(AppAuthState authState) {
        // XU2: ownership first (null for initializing and signedOut).
        final currentUserId = authState.currentUserId;
        if (currentUserId != null) {
          controller.handleCurrentUser(currentUserId);
        }
        switch (authState.status) {
          case AppAuthStatus.initializing:
            return;
          case AppAuthStatus.signedOut:
            controller.resetForSessionLifecycle();
            return;
```

Note: the `signedIn` case right below computes `allowCachedFallback: controller.state == null` after this call, so a released context lets the new user's refresh use the new user's cached fallback. That is intended.

- [ ] **Step 5: Run the file, then the full suite and the analyzer.**

```bash
cd apps/lyron_app && flutter test test/integration/cross_user_local_first_leak_test.dart
```

Expected: nine pass, one skipped. Then the full `flutter test` and `flutter analyze`: green.

- [ ] **Step 6: Commit.**

```bash
git add apps/lyron_app/lib/src/application/planning/active_planning_context_controller.dart apps/lyron_app/lib/src/application/planning_providers.dart apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart
git commit -m "fix(planning): active planning context follows the current user"
```

---

### Task 5: The catalog follows the current user (XU2, closes R-B catalog)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/song_catalog_providers.dart`
- Test: `apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart`

- [ ] **Step 1: Unskip.** Delete `skip: 'red until Task 5 (XU2); spec 2026-10-06 cross-user ownership'` from "a catalog establishment started for A does not land after B signs in".

- [ ] **Step 2: Run, expect red.**

```bash
cd apps/lyron_app && flutter test test/integration/cross_user_local_first_leak_test.dart
```

Expected: that test fails with `Expected: not 'user-a'  Actual: 'user-a'`; nine pass.

- [ ] **Step 3: `SongCatalogController`.** In `song_catalog_controller.dart`:

(a) Import (sorted). Replace

```dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
```

with

```dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/current_user_ownership.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
```

(b) Field. Replace

```dart
  Completer<void>? _pendingFollowUpRefresh;

  CatalogSnapshotState get state => _state;
```

with

```dart
  Completer<void>? _pendingFollowUpRefresh;
  final _ownership = CurrentUserOwnership();

  CatalogSnapshotState get state => _state;
```

(c) Method. Directly after the `handleSessionAvailable()` method:

```dart
  void handleSessionAvailable() {
    final session = _authSessionReader();
    if (session != null) {
      _rememberAuthenticatedUser(session.userId);
    }
    _updateRefreshScheduler();
  }
```

insert:

```dart

  /// XU2 (docs/specs/2026-10-06-cross-user-local-first-ownership.md): called
  /// on every signedIn and sessionExpired notification with
  /// AppAuthState.currentUserId, before the status handlers. A signedIn edge
  /// does not advance the refresh generation on its own, so a refresh or
  /// local-first establishment started for the previous user could still
  /// commit that user's context (R-B). When the current user changes that
  /// work is invalidated, and a context held for another user is dropped on
  /// the edge instead of waiting for the I3 guard in _refreshCatalogBody,
  /// which runs only once the new user's refresh starts (possibly queued
  /// behind the previous user's in-flight one). In memory only: nothing is
  /// deleted.
  void handleCurrentUser(String currentUserId) {
    final changed = _ownership.observe(currentUserId);
    final context = _state.context;
    final holdsForeign = context != null && context.userId != currentUserId;
    if (!changed && !holdsForeign) {
      return;
    }
    _invalidateRefreshWork();
    if (holdsForeign) {
      _setState(const CatalogSnapshotState.initial());
    }
  }
```

- [ ] **Step 4: Wire it.** In `song_catalog_providers.dart`, replace

```dart
      void handleAuthStateChanged(AppAuthState authState) {
        switch (authState.status) {
          case AppAuthStatus.initializing:
            return;
          case AppAuthStatus.signedOut:
            unawaited(controller.handleExplicitSignOut());
            return;
```

with

```dart
      void handleAuthStateChanged(AppAuthState authState) {
        // XU2: ownership first (null for initializing and signedOut; the
        // sign-out handler owns that edge and its purge target).
        final currentUserId = authState.currentUserId;
        if (currentUserId != null) {
          controller.handleCurrentUser(currentUserId);
        }
        switch (authState.status) {
          case AppAuthStatus.initializing:
            return;
          case AppAuthStatus.signedOut:
            unawaited(controller.handleExplicitSignOut());
            return;
```

- [ ] **Step 5: Run the file, then the full suite and the analyzer.**

```bash
cd apps/lyron_app && flutter test test/integration/cross_user_local_first_leak_test.dart
```

Expected: all ten pass, none skipped. Then the full `flutter test` and `flutter analyze`: green. Confirm there is no `skip:` left in the file:

```bash
grep -c "skip:" apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart
```

Expected: `0`.

- [ ] **Step 6: Commit.**

```bash
git add apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart apps/lyron_app/lib/src/application/song_catalog_providers.dart apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart
git commit -m "fix(catalog): catalog context follows the current user"
```

---

### Task 6: Documentation

**Files:** the ones listed below. No code.

- [ ] **Step 1: ADR-037 amendment.** Append to `docs/architecture/decisions/ADR-037-local-first-catalog-visibility.md`:

```markdown

## Amendment: current-user ownership (2026-10-06)

Spec: `docs/specs/2026-10-06-cross-user-local-first-ownership.md`.

The ownership rule above said "`identity.userId` alone when
`sessionExpired` (no live session to compare against)". There is always
something to compare against: `AppAuthState.currentUserId`, the last known
session's user when `sessionExpired`. Losing user B's session while user A's
identity was on file gave `sessionExpired(B)`, and both controllers then
established A's context for B (F6). Separately, a context held for A survived
B's sign-in in planning, in the active planning context, and through
establishments still in flight (F7, R-A, R-B). In planning it also made B's
first boundary delete A's plans and pending work while the different-user
prompt was pending (F8).

Narrowed rule: a local-first read context may belong only to
`AppAuthState.currentUserId`.

- **Establishment (XU1).** `AppAuthController.currentUserLastKnownIdentity`
  (the identity only when it is the current user's) is the only identity the
  catalog and planning local-first readers and the membership gate see.
- **Held contexts (XU2).** Cause 4 of the invariant ("a different-user
  sign-in") now reads "a change of the current user": a sign-in, a direct
  session switch, or a cancelled reauth back to the prior user. On every
  `signedIn` and `sessionExpired` notification each holder (catalog context,
  active planning context, planning sync state) applies
  `CurrentUserOwnership`. It invalidates work started for the previous user,
  drops a context owned by anyone else, and never adopts one. This happens on
  the auth edge, not only inside a refresh that may never run. The I3 guards
  stay as a second line.

In memory only: no purge, no `PurgeReason`, no store write or delete is added
(ADR-035 unchanged). Explicit sign-out is not routed through this rule; its
handlers and purge targets are unchanged. Because no foreign context is ever
held at a sign-out any more, those targets now always fall through to the
signing-out user.
```

- [ ] **Step 2: ADR-040.** In `docs/architecture/decisions/ADR-040-offline-first-startup-gate.md`, replace

```markdown
- Known residual cases are recorded in
  `docs/deferred/2026-10-05-gate-cross-user-leaks.md`. F6 and F7 are
  pre-existing cross-user leaks (not introduced by the gate) that the next
  fix PR closes; C4, F5, N1 and N2 are low-severity gate cases that show
  only the user's own state.
```

with

```markdown
- Known residual cases are recorded in
  `docs/deferred/2026-10-05-gate-cross-user-leaks.md`: C4, F5, N1 and N2 are
  low-severity gate cases that show only the user's own state. The two
  pre-existing cross-user leaks found by the gate review (F6, F7) were closed
  by ADR-037's current-user ownership amendment (2026-10-06), which also
  moved the gate's known-organization reader onto the shared
  `AppAuthController.currentUserLastKnownIdentity` getter.
```

- [ ] **Step 3: ADR-029.** In `docs/architecture/decisions/ADR-029-reauth-prompt-host-and-different-user-resolution.md`, after the second header bullet that starts with `- Amended: 2026-08-06` (the one whose last line ends with "(Finding A)."), add:

```markdown
- Amended: 2026-10-06 — D5's guarantee ("cancel deletes nothing") held for
  the confirmed wipe but not for planning: while the different-user prompt
  was pending, the new user's first planning boundary made
  `PlanningSyncController.handleActiveContextChanged` delete the prior user's
  planning projection and pending mutations (F8). Closed by ADR-037's
  current-user ownership amendment: the prior user's boundary is released in
  memory on the sign-in edge, so the confirmed wipe is again the only path
  that deletes the prior user's data.
```

- [ ] **Step 4: Architecture.** In `docs/architecture/architecture.md`, in the offline-authenticated paragraph, replace

```text
and a context is reset outright if it belongs to a different user than the current session before any of the above runs.
```

with

```text
and a context is reset outright if it belongs to a different user than the current session before any of the above runs. Ownership follows `AppAuthState.currentUserId` (the live session's user, or the last known session's user when offline-authenticated): the local-first readers see the last known identity only when it is the current user's, and every in-memory context holder (catalog context, active planning context, planning sync state) releases a context owned by anyone else on the auth edge that changes the current user, in memory only (ADR-037 amendment, 2026-10-06).
```

- [ ] **Step 5: Testing strategy.** In `docs/testing/testing-strategy.md`, directly before the heading `#### Real auth client rule (offline startup)`, insert:

```markdown
#### Cross-user ownership pattern

`apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart`
(`docs/specs/2026-10-06-cross-user-local-first-ownership.md`) is the
regression gate for "a user never sees or loses another user's songs or
plans through a local-first path". Rules for extending it:

- Drive user changes through the real `AppAuthController` and its session
  stream, with the real different-user reauth providers mounted
  (`appAuthListenableProvider`, `membershipRefreshEffectProvider`). A
  controller-level test with a live session for the new user misses every
  path that goes through `sessionExpired` or through a listener that ignores
  `signedIn`.
- Hold the three context holders alive together (catalog, planning sync,
  active planning). Several leaks only appear when two holders disagree (for
  example the catalog has no songs for the prior user but planning has plans).
- Assert on what the user sees (`songLibraryListProvider`,
  `planningPlanListProvider`, `planningMutationEntriesProvider`), not only on
  controller fields, and assert that the prior user's local rows still exist
  when only a confirmed wipe may delete them.
- To pin an interleaving, pause the real Drift read for one user
  (`_ReadGate`), never replace the store.

```

- [ ] **Step 6: Deferred entry.** Edit `docs/deferred/2026-10-05-gate-cross-user-leaks.md`:

(a) Replace the title line `# Cross-User Local Data Leaks Found in the Gate Review` with `# Startup Gate Review Residuals (C4, F5, N1, N2)`.

(b) Replace the slice line

```markdown
**Slice:** fix/offline-first-startup-gate (found by the adversarial review of
PR 1 on 2026-10-05; both are pre-existing, neither is introduced or worsened
by the gate change)
```

with

```markdown
**Slice:** fix/offline-first-startup-gate (found by the adversarial review of
PR 1 on 2026-10-05). The two cross-user leaks of that review, F6 and F7, were
closed by `docs/specs/2026-10-06-cross-user-local-first-ownership.md`
(ADR-037 amendment, 2026-10-06) and removed from this entry.
```

(c) Replace the `**Status:**` paragraph

```markdown
**Status:** both entries are PLAUSIBLE from a code read. Neither has a
reproducing test yet; the first step of the fix slice is to write that test
and watch it fail.
```

with

```markdown
**Status:** C4, F5, N1 and N2 are low-severity gate cases that show only the
user's own state. None is a cross-user leak.
```

(d) Delete the `**Sequencing:**` paragraph (it is about F6/F7).

(e) In the `**Related:**` list, replace `are the leaks below, C4, F5, N1 and N2` with `were the cross-user leaks (closed 2026-10-06), C4, F5, N1 and N2`.

(f) Delete the whole `## F6 - …` and `## F7 - …` sections, up to (not including) `## C4 - …`.

(g) Replace the `## Why these were deferred` section body with:

```markdown
They show only the current user's own state, Retry or sign-in recovers each
of them, and fixing them means changing the gate's resolution bookkeeping,
which PR 1 had just settled.
```

(h) Replace the `## Trigger` section body with:

```markdown
No fixed slice. Pick these up when a change touches the gate's retry or
resolution bookkeeping (`membershipRetryProvider`,
`ActiveMembershipController`), or when one of them is reported from the
field.
```

(i) Delete the whole `## Requirements for the slice that picks this up` section (its three bullets are the F6/F7 requirements, now in the spec's constraints).

- [ ] **Step 7: Roadmap.** Already updated with the spec at the design gate
  (S0 PR 1 merged as #85; this PR before S0 PR 2). No change here; Task 7
  adds the PR number after the PR is opened.

- [ ] **Step 8: Spec status.** In the spec, replace

```markdown
> Status: spec and plan awaiting approval (design gate); no production code yet
```

with

```markdown
> Status: implemented on `fix/cross-user-local-first-leaks` (Tasks 1–5)
```

- [ ] **Step 9: Verify and commit.** Run the full `flutter test` and `flutter analyze` once more (docs only, but the rule is every task). Then:

```bash
git add docs
git commit -m "docs: current-user ownership for local-first contexts (ADR-037 amendment)"
```

---

### Task 7: Adversarial review and pull request (orchestrator)

- [ ] **Step 1:** One adversarial Opus whole-diff review of `main...HEAD` with exactly this question: "Show an event sequence (sign-in, sign-out, user switch, interrupted reauth, session loss, purge, sessionExpired, cold start) in which one user sees another user's song, plan or context." The reviewer gets the spec, this plan, ADR-020/029/035/037/040 and the reproduction suite. Findings must name a concrete sequence; the orchestrator spot-checks every cited line against the live file.
- [ ] **Step 2:** Exit criterion. Only a cross-user visibility or a view with no way out blocks: fix it with a red test first, the full suite and the analyzer, then re-review the delta. Everything else goes into `docs/deferred/2026-10-05-gate-cross-user-leaks.md` as a new lettered entry, with its sequence, why it does not block, and a fix sketch.
- [ ] **Step 3:** Push and open the PR against `main` (do not merge). Then add the PR number to the roadmap's sequencing line in a follow-up commit on the branch. The body lists F6, F7, R-A, R-B, F8, the red-to-green evidence, the constraints kept (no purge, no `PurgeReason`, ADR-035 unchanged, I3 guards kept), and the ADR amendments.
