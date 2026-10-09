# Sign-Out Pending-Work Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An explicit sign-out never deletes the signing-out user's unsynced work without a confirmation, whichever control started it and whether or not a read context exists; it never clears another user's identity row; it completes at the local sign-out whatever the network does and never raises an unhandled error. A confirmed sign-out still deletes.

**Architecture:** One application-layer `SignOutCommand` (SO1) decides from the signing-out user's user-wide pending count (SO2, the ADR-029 D4 counter), asks through one presentation dialog with an honest count (SO3), and runs the song list's existing sign-out sequence while it holds the catalog controller alive with an explicit subscription. Every sign-out control calls it. `AppAuthController.signOut()` completes at the local sign-out and handles the backend revocation's result once, never throwing it (SO3, W3). `lastKnownIdentityPersistenceProvider` remembers the current user and clears only that user's identity row on the `signedOut` edge (SO4, closes O1). No new purge, no `PurgeReason`, no new store delete, no ADR-035 change.

**Tech Stack:** Flutter, Dart 3, Riverpod 3.4.3 (legacy `ChangeNotifierProvider`, plain `Provider`), Drift, gotrue 2.27.2, flutter_test. Riverpod APIs used: `ref.read`, and `ref.listen` from a callback outside build with `ProviderSubscription.read()/close()` (allowed while the ref is mounted: `riverpod-3.4.3/lib/src/core/ref.dart`, `_throwIfInvalidUsage`; context7: a listen subscription keeps an `autoDispose` provider alive until closed).

**Spec:** `docs/specs/2026-10-07-sign-out-pending-work-guard.md` (decisions SO1–SO5, findings W1, W2, W3, O1, acceptance AC1–AC11; approved 2026-10-09 with the W3 and catalog-lifetime additions)
**Branch:** `fix/sign-out-pending-work-guard` (from `main` at `c222e44`)
**Discipline:** TDD. Every task starts with a red test that is run and seen failing for the stated reason. Never edit an existing test to make it pass. The only existing tests this plan changes are the two named in the spec's "Intentional behaviour changes" (items 1 and 4), in Tasks 1 and 5. If any other existing test fails: STOP and report, quoting the test.
**Verification after every task:** the FULL suite and the analyzer, never a subset:

```bash
cd apps/lyron_app && flutter test
```

```bash
cd apps/lyron_app && flutter analyze
```

Run `dart format lib test` before each commit. STOP and report if the full suite shows a Riverpod error during a provider build ("Tried to modify a provider while the widget tree was building" or similar), if the plan's code does not match the real file, or if a fix would need a new purge, a new `PurgeReason` or an ADR-035 change.

---

## Facts the implementer needs (verified while planning)

- **The reproduction tests already exist**, committed with the spec:
  - `apps/lyron_app/test/integration/sign_out_pending_work_guard_test.dart` runs the whole app (`LyronApp`, real router, gate, `AppAuthController`, lifecycle, listeners, the real gotrue client, Drift in-memory stores). Only the network is replaced: `_HangingHttpClient` (default, never answers) or `_FailingHttpClient` (every request fails at once; gotrue turns it into `AuthRetryableFetchException` without a status code). `seed(..., persistedSessionForA: true)` stores a still-valid session for A, so the app starts `signedIn(A)` and a sign-out calls the backend; `pendingSongForA: true` adds a pending song create of A's. Tests and their markers:
    - (a) Account sign-out, `// Red until Task 6 (SO1); ...` and `skip: true`;
    - (b) song-list sign-out with no read context, `// Red until Task 5 (SO2); ...` and `skip: true`;
    - the guard (song list with a planning context warns, Cancel deletes nothing), green, not skipped;
    - "offline: a confirmed sign-out on a failing network …" (W3), `// Red until Task 4 (SO3, offline sign-out); ...` and `skip: true`.
  - `apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart`, group "explicit sign-out clears only the signing-out user's identity (O1)": two tests with `skip: 'red until Task 1 (SO4); spec 2026-10-07 sign-out pending-work guard'` and one green guard.
  - Each task removes the skip of its own tests, runs them red, then makes them green. Do not change the fixtures except where a task says so.
- **Red output recorded** (skips removed, pre-fix code):
  - (a): `Expected: (pendingSongWorkOfA: 1, pendingWorkOfA: 1, status: AppAuthStatus.sessionExpired, warningShown: true)  Actual: (pendingSongWorkOfA: 0, pendingWorkOfA: 0, status: AppAuthStatus.signedOut, warningShown: false)`.
  - (b): `Expected: (pendingWorkOfA: 1, status: AppAuthStatus.sessionExpired, warningShown: true)  Actual: (pendingWorkOfA: 0, status: AppAuthStatus.signedOut, warningShown: false)`.
  - W3: `The following AuthRetryableFetchException was thrown running a test: AuthRetryableFetchException(message: ClientException: network is unreachable, statusCode: null)`. It is followed by "A Timer is still pending even after the widget tree was disposed": the aborted test never reached `tearDown` (which stops gotrue's auto-refresh ticker). If that timer message remains once the test is green, report it; do not add waits to hide it.
  - Both O1 tests: `Expected: 'user-a'  Actual: <null>`.
- **Line references** are to `main` at `c222e44`. Match the quoted code, not the line number.
- **Sign-out entry points** (graphify, then grep): `SongListScreen._signOut` (`lib/src/presentation/song_library/song_list_screen.dart:312-345`, menu at `:150-151`) and `AccountScreen`'s Sign out tile (`lib/src/presentation/account/account_screen.dart:26-29`). Delete account, `cancelReauthToPriorSession` and ADR-035 D2's no-identity branch are not sign-out controls and are not changed.
- **The `signedOut` edge listeners:** catalog (`lib/src/application/song_catalog_providers.dart:118-142`, `handleExplicitSignOut`), planning (`lib/src/application/planning_providers.dart:366-384`, `handleExplicitSignOut`), identity (`lib/src/application/auth_providers.dart:173-185`, `persistIdentity`). They stay; only the identity case gets a target user (Task 1).
- **gotrue 2.27.2 sign-out** (`~/.pub-cache/hosted/pub.dev/gotrue-2.27.2/lib/src/gotrue_client.dart:1085-1108`): `_removeSession()` (synchronous), `await _asyncStorage?.removeItem(code verifier)`, `notifyAllSubscribers(signedOut)`, then `await admin.signOut(accessToken)` only if a session existed; its failure is rethrown unless 401/403/404. Without a session (for example `sessionExpired` after a cold start) no request is made.
- **`AppAuthController.signOut()` today** (`lib/src/application/auth/app_auth_controller.dart:162-171`) awaits the repository call and then sets `signedOut`; the stream's null event during the call already maps to `signedOut` because `_isSigningOut` is true. No existing test expects `signOut()` to throw: `app_auth_controller_test.dart` uses `signOutError` only with `cancelReauthToPriorSession`.
- **`AppAuthState.currentUserId`** is the live session's user in `signedIn`, the last known session's user in `sessionExpired`, and null in `initializing` and `signedOut`.
- **`LocalDataLifecycle.clearIdentity(userId:)`** already clears only a row that belongs to `userId` (`lib/src/application/storage/local_data_lifecycle.dart:356-389`). Its doc comment says `userId: null` "is the explicit sign-out path"; Task 1 updates that sentence.
- **`song_list_screen_test.dart`'s `buildApp`** creates `AppAuthController(_TestAuthRepository())` and never calls `restoreSession`, so its state is `initializing` (no current user). A test that needs a current user calls `restoreSession()` on the controller from the container (Task 5 shows how). The existing test "sign out clears planning state before auth sign-out" calls `restoreSession()` itself; through the command its count is 0 (empty in-memory databases), so it signs out without a dialog. Its expected events `['planning-sign-out', 'auth-sign-out']` are unchanged: its catalog controller is `_NoopSongCatalogController`, whose `handleExplicitSignOut` records nothing.
- **Riverpod 3 (context7):** a `Ref` used after its provider was disposed throws `UnmountedRefException`. The command provider is therefore app-scoped (not `autoDispose`) and watches nothing.

## File map

| File | Change |
|---|---|
| `apps/lyron_app/lib/src/application/auth_providers.dart` | SO4 in `lastKnownIdentityPersistenceProvider` (Task 1); `signOutCommandProvider` (Task 3) |
| `apps/lyron_app/lib/src/application/storage/local_data_lifecycle.dart` | `clearIdentity` doc comment (Task 1) |
| `apps/lyron_app/lib/src/application/auth/sign_out_command.dart` | **new** (Task 2) |
| `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart` | `signOut()` completes at the local sign-out (Task 4) |
| `apps/lyron_app/lib/src/presentation/auth/sign_out_flow.dart` | **new** (Task 5) |
| `apps/lyron_app/lib/src/shared/app_strings.dart` | sign-out messages (Task 5) |
| `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart` | uses the flow (Task 5) |
| `apps/lyron_app/lib/src/presentation/account/account_screen.dart` | uses the flow (Task 6) |
| `apps/lyron_app/test/application/auth/identity_persistence_wiring_test.dart` | one new test; one named expectation change (Task 1) |
| `apps/lyron_app/test/application/auth/sign_out_command_test.dart` | **new** (Task 2) |
| `apps/lyron_app/test/application/auth/sign_out_command_provider_test.dart` | **new** (Task 3) |
| `apps/lyron_app/test/application/auth/app_auth_controller_sign_out_test.dart` | **new** (Task 4) |
| `apps/lyron_app/test/presentation/auth/sign_out_flow_test.dart` | **new** (Task 5) |
| `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart` | two named tests rewritten (Task 5) |
| `apps/lyron_app/test/presentation/account/account_screen_test.dart` | two new tests (Task 6) |
| `apps/lyron_app/test/integration/*` | remove skips (Tasks 1, 4, 5, 6); two new W3 command tests (Task 4) |
| docs (Task 7) | ADR-020, ADR-037, architecture, testing strategy, deferred entry, ownership spec, spec status |

---

### Task 1: The identity clear targets the user who signed out (SO4, closes O1; AC5)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth_providers.dart`
- Modify: `apps/lyron_app/lib/src/application/storage/local_data_lifecycle.dart` (doc comment only)
- Modify: `apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart` (remove two skips)
- Modify: `apps/lyron_app/test/application/auth/identity_persistence_wiring_test.dart`

- [ ] **Step 1: Remove the two O1 skips and run them red**

In `cross_user_local_first_leak_test.dart`, group "explicit sign-out clears only the signing-out user's identity (O1)", delete the `skip: 'red until Task 1 (SO4); spec 2026-10-07 sign-out pending-work guard',` argument of both tests.

Run: `cd apps/lyron_app && flutter test test/integration/cross_user_local_first_leak_test.dart --plain-name "O1"`
Expected: 2 failures, `Expected: 'user-a'  Actual: <null>`; the guard passes.

- [ ] **Step 2: Add the documenting no-observed-user test and run it red**

Append inside `main()` of `identity_persistence_wiring_test.dart`, next to "signedIn writes the active organization and signedOut clears the identity":

```dart
  test(
    'signedOut with no observed current user clears nothing (SO4)',
    () async {
      // SO4 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): the
      // sign-out clear takes the user who signed out. This controller has no
      // identity store, so the null restored session maps to signedOut
      // without any current user ever being observed; the row on file
      // belongs to nobody this provider acted for, and an unknown
      // signing-out user never authorises a clear.
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-2',
          email: 'other@example.com',
          organizationId: 'org-2',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(authController.state.status, AppAuthStatus.signedOut);
      expect(identityStore.clearCount, 0);
      expect((await identityStore.read())?.userId, 'user-2');
    },
  );
```

`_FakeAuthRepository.currentSession` defaults to null (`identity_persistence_wiring_test.dart:2029-2040`), and `appAuthListenableProvider` watches `lastKnownIdentityPersistenceProvider` (`auth_providers.dart:943-949`).

Run: `cd apps/lyron_app && flutter test test/application/auth/identity_persistence_wiring_test.dart --plain-name "SO4"`
Expected: FAIL, `clearCount` is 1 (today the `signedOut` case clears unconditionally).

- [ ] **Step 3: Implement SO4**

In `auth_providers.dart`, add the import
`import 'package:lyron_app/src/application/auth/current_user_ownership.dart';`.

In `lastKnownIdentityPersistenceProvider`, right after `var resolutionChain = Future<void>.value();`, add:

```dart
  // SO4 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): the user an
  // explicit sign-out clears. Fed on every notification synchronously,
  // before the resolution is queued, because the chain can be blocked
  // behind a pending different-user prompt.
  final ownership = CurrentUserOwnership();
```

Change `persistIdentity`'s signature to take the signing-out user:

```dart
  Future<void> persistIdentity(
    AppAuthState authState,
    int generation,
    AppAuthSession? capturedSession,
    String? signingOutUserId,
  ) async {
```

Replace the `signedOut` case body (keep the existing account-deletion comment above the call):

```dart
      case AppAuthStatus.signedOut:
        if (!isCurrent(generation, AppAuthStatus.signedOut, null)) return;
        // <existing comment on account deletion vs. explicit sign-out, unchanged>
        //
        // SO4 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): only
        // the row of the user who signed out (O1: this used to clear
        // whatever row was on file, including another user's). With no
        // observed user there is nobody to clear for.
        if (signingOutUserId == null) return;
        await lifecycle.clearIdentity(
          reason: PurgeReason.userSignOut,
          userId: signingOutUserId,
        );
        return;
```

In `scheduleIdentityResolution`, capture the user before queueing:

```dart
  void scheduleIdentityResolution(AppAuthState authState) {
    final generation = epoch.invalidate();
    promptController.supersedePending();
    final capturedSession = authState.session;
    final currentUserId = authState.currentUserId;
    if (currentUserId != null) {
      ownership.observe(currentUserId);
    }
    final signingOutUserId = authState.status == AppAuthStatus.signedOut
        ? ownership.userId
        : null;
    final scheduled = resolutionChain.then(
      (_) => persistIdentity(
        authState,
        generation,
        capturedSession,
        signingOutUserId,
      ),
    );
```

(The rest of the method is unchanged.)

In `local_data_lifecycle.dart`, in `clearIdentity`'s doc comment, replace the sentence "`userId: null` is the explicit sign-out path: there is no owner to check against, so it keeps clearing unconditionally, exactly as before." with: "The explicit sign-out passes the user who signed out (SO4, `docs/specs/2026-10-07-sign-out-pending-work-guard.md`); `userId: null` still clears unconditionally for a caller with no owner to check against."

- [ ] **Step 4: Apply the named expectation change (spec, intentional change 4)**

In `identity_persistence_wiring_test.dart`, test "stale signedIn persistence does not rewrite after signedOut clears identity" (`:305-340`), replace `expect(identityStore.clearCount, 1);` with:

```dart
      // SO4 (docs/specs/2026-10-07-sign-out-pending-work-guard.md,
      // intentional change 4): user-1's identity was never written, so the
      // sign-out clear, scoped to user-1, finds no row of user-1 and clears
      // nothing. The subject of this test, no rewrite after the sign-out, is
      // unchanged.
      expect(identityStore.clearCount, 0);
```

Change nothing else in that test. If any other existing test fails: STOP and report.

- [ ] **Step 5: Run the targeted tests green, then the full suite and the analyzer**

- [ ] **Step 6: Commit**

```bash
git add -A apps/lyron_app/lib apps/lyron_app/test
git commit -m "fix(auth): sign-out clears only the signing-out user's identity (SO4, O1)"
```

---

### Task 2: `SignOutCommand` (SO1–SO3; AC6)

**Files:**
- Create: `apps/lyron_app/lib/src/application/auth/sign_out_command.dart`
- Create: `apps/lyron_app/test/application/auth/sign_out_command_test.dart`

- [ ] **Step 1: Write the failing unit tests**

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';

void main() {
  late String? currentUserId;
  late List<String> countedUsers;
  late Future<int> Function() countResult;
  late Future<void> Function() signOutStep;
  late int signOutCalls;
  late List<Object> reported;

  SignOutCommand buildCommand() => SignOutCommand(
    currentUserIdReader: () => currentUserId,
    countPendingWork: ({required userId}) {
      countedUsers.add(userId);
      return countResult();
    },
    signOut: () async {
      signOutCalls += 1;
      await signOutStep();
    },
    reportError: (error, _) => reported.add(error),
  );

  setUp(() {
    currentUserId = 'user-a';
    countedUsers = [];
    countResult = () async => 0;
    signOutStep = () async {};
    signOutCalls = 0;
    reported = [];
  });

  test('zero pending work signs out without asking', () async {
    final asked = <int?>[];
    final outcome = await buildCommand().run(
      confirmDiscard: (count) async {
        asked.add(count);
        return true;
      },
    );
    expect(outcome, SignOutOutcome.signedOut);
    expect(asked, isEmpty);
    expect(countedUsers, ['user-a']);
    expect(signOutCalls, 1);
  });

  test('pending work asks with the count; confirming signs out', () async {
    countResult = () async => 3;
    final asked = <int?>[];
    final outcome = await buildCommand().run(
      confirmDiscard: (count) async {
        asked.add(count);
        return true;
      },
    );
    expect(outcome, SignOutOutcome.signedOut);
    expect(asked, [3]);
    expect(signOutCalls, 1);
  });

  test('cancelling deletes nothing', () async {
    countResult = () async => 1;
    final outcome = await buildCommand().run(
      confirmDiscard: (_) async => false,
    );
    expect(outcome, SignOutOutcome.cancelled);
    expect(signOutCalls, 0);
  });

  test('an unreadable count asks with null, never as zero', () async {
    countResult = () async => throw StateError('storage failure');
    final asked = <int?>[];
    final outcome = await buildCommand().run(
      confirmDiscard: (count) async {
        asked.add(count);
        return false;
      },
    );
    expect(outcome, SignOutOutcome.cancelled);
    expect(asked, [null]);
    expect(signOutCalls, 0);
  });

  test('no current user asks with null and counts nobody', () async {
    currentUserId = null;
    final asked = <int?>[];
    await buildCommand().run(
      confirmDiscard: (count) async {
        asked.add(count);
        return false;
      },
    );
    expect(asked, [null]);
    expect(countedUsers, isEmpty);
    expect(signOutCalls, 0);
  });

  test('a user change during the count supersedes the run', () async {
    final count = Completer<int>();
    countResult = () => count.future;
    final asked = <int?>[];
    final run = buildCommand().run(
      confirmDiscard: (value) async {
        asked.add(value);
        return true;
      },
    );
    currentUserId = 'user-b';
    count.complete(0);
    expect(await run, SignOutOutcome.superseded);
    expect(asked, isEmpty);
    expect(signOutCalls, 0);
  });

  test('a user change while the dialog is open supersedes the run', () async {
    countResult = () async => 2;
    final answer = Completer<bool>();
    final run = buildCommand().run(confirmDiscard: (_) => answer.future);
    await Future<void>.delayed(Duration.zero);
    currentUserId = 'user-b';
    answer.complete(true);
    expect(await run, SignOutOutcome.superseded);
    expect(signOutCalls, 0);
  });

  test('a second run while one is in flight does nothing', () async {
    countResult = () async => 2;
    final answer = Completer<bool>();
    final command = buildCommand();
    final first = command.run(confirmDiscard: (_) => answer.future);
    await Future<void>.delayed(Duration.zero);
    final asked = <int?>[];
    final second = await command.run(
      confirmDiscard: (count) async {
        asked.add(count);
        return true;
      },
    );
    expect(second, SignOutOutcome.alreadyRunning);
    expect(asked, isEmpty);

    answer.complete(false);
    expect(await first, SignOutOutcome.cancelled);
    countResult = () async => 0;
    expect(
      await command.run(confirmDiscard: (_) async => true),
      SignOutOutcome.signedOut,
    );
  });

  test('a failing sign-out sequence is reported once, gives failed and '
      'releases the lock', () async {
    signOutStep = () async => throw StateError('purge failed');
    final command = buildCommand();
    expect(
      await command.run(confirmDiscard: (_) async => true),
      SignOutOutcome.failed,
    );
    expect(reported, hasLength(1));
    expect(reported.single, isA<StateError>());

    signOutStep = () async {};
    expect(
      await command.run(confirmDiscard: (_) async => true),
      SignOutOutcome.signedOut,
    );
  });

  test('a throwing confirmation is reported once and is not a '
      'confirmation', () async {
    countResult = () async => 1;
    final outcome = await buildCommand().run(
      confirmDiscard: (_) async => throw StateError('dialog failed'),
    );
    expect(outcome, SignOutOutcome.cancelled);
    expect(reported, hasLength(1));
    expect(signOutCalls, 0);
  });
}
```

Run: `cd apps/lyron_app && flutter test test/application/auth/sign_out_command_test.dart`
Expected: compile failure (the file does not exist).

- [ ] **Step 2: Implement the command**

```dart
enum SignOutOutcome { signedOut, cancelled, superseded, alreadyRunning, failed }

/// Shows the warning for [pendingCount] (null: unknown) and returns whether
/// the user confirmed the loss. Must answer false when it cannot ask.
typedef SignOutConfirmation = Future<bool> Function(int? pendingCount);

typedef SignOutPendingWorkCounter =
    Future<int> Function({required String userId});

typedef SignOutErrorReporter =
    void Function(Object error, StackTrace stackTrace);

/// SO1–SO3 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): the one
/// explicit sign-out rule every sign-out control runs through.
///
/// The warning is decided from the signing-out user's user-wide pending
/// count, the same count and scope as the different-user wipe (ADR-029 D4),
/// which is also the scope of the sign-out purges. An unreadable count, or
/// no current user, is asked about with `null` and never treated as zero
/// (ADR-029 honest null, ADR-035 D5.4). A confirmed sign-out still deletes
/// (the 2026-08-19 product decision). No error escapes [run]: it is
/// reported once through the injected reporter.
///
/// Holds no `Ref`: the provider in auth_providers.dart injects the reader,
/// the counter, the sign-out sequence and the reporter.
class SignOutCommand {
  SignOutCommand({
    required this._currentUserIdReader,
    required this._countPendingWork,
    required this._signOut,
    required this._reportError,
  });

  final String? Function() _currentUserIdReader;
  final SignOutPendingWorkCounter _countPendingWork;
  final Future<void> Function() _signOut;
  final SignOutErrorReporter _reportError;
  bool _running = false;

  Future<SignOutOutcome> run({
    required SignOutConfirmation confirmDiscard,
  }) async {
    if (_running) {
      return SignOutOutcome.alreadyRunning;
    }
    _running = true;
    try {
      final userId = _currentUserIdReader();
      final pendingCount = userId == null ? null : await _readCount(userId);
      // SO3: the purges target the current user when they run. If that is no
      // longer the user whose work was counted, nothing was confirmed for
      // the new one.
      if (_currentUserIdReader() != userId) {
        return SignOutOutcome.superseded;
      }
      if (pendingCount != 0) {
        if (!await _confirm(confirmDiscard, pendingCount)) {
          return SignOutOutcome.cancelled;
        }
        if (_currentUserIdReader() != userId) {
          return SignOutOutcome.superseded;
        }
      }
      try {
        await _signOut();
      } catch (error, stackTrace) {
        // SO3: no sign-out control may raise an unhandled error. The user
        // can try again: the lock is released below.
        _reportError(error, stackTrace);
        return SignOutOutcome.failed;
      }
      return SignOutOutcome.signedOut;
    } finally {
      _running = false;
    }
  }

  Future<int?> _readCount(String userId) async {
    try {
      return await _countPendingWork(userId: userId);
    } catch (_) {
      return null;
    }
  }

  /// An error while asking is reported and is not a confirmation.
  Future<bool> _confirm(
    SignOutConfirmation confirmDiscard,
    int? pendingCount,
  ) async {
    try {
      return await confirmDiscard(pendingCount);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
      return false;
    }
  }
}
```

- [ ] **Step 3: Run the unit tests green, then the full suite and the analyzer**

- [ ] **Step 4: Commit**

```bash
git add -A apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(auth): sign-out command decides from the user-wide pending count (SO1-SO3)"
```

---

### Task 3: `signOutCommandProvider` with an explicit catalog lifetime (SO1, SO2; AC7)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth_providers.dart`
- Create: `apps/lyron_app/test/application/auth/sign_out_command_provider_test.dart`

- [ ] **Step 1: Write the failing wiring tests**

Two tests in the new file:

1. **User-wide count.** A pending planning row for the current user in an organization with no read context; the command asks with `1`; Cancel leaves the user signed in.
2. **Catalog lifetime (AC7).** Nothing else listens to `songCatalogControllerProvider`. While the catalog's `handleExplicitSignOut` is held on a gate, the controller must not be disposed; after the run it must be.

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  late PlanningLocalDatabase planningDatabase;
  late SongCatalogDatabase songDatabase;
  late List<String> events;
  late AppAuthController authController;

  setUp(() async {
    planningDatabase = PlanningLocalDatabase.inMemory();
    addTearDown(planningDatabase.close);
    songDatabase = SongCatalogDatabase.inMemory();
    addTearDown(songDatabase.close);
    events = [];
    authController = AppAuthController(_SignedInAuthRepository(events));
    await authController.restoreSession();
  });

  test('the command counts the current user\'s pending work in every '
      'organization and cancelling leaves the user signed in', () async {
    await planningDatabase
        .into(planningDatabase.cachedPlanningMutations)
        .insert(
          CachedPlanningMutationsCompanion.insert(
            userId: 'user-1',
            organizationId: 'org-without-context',
            aggregateType: 'plan',
            aggregateId: 'plan-edit',
            mutationKind: PlanningMutationKind.planEdit.value,
            syncStatus: PlanningMutationSyncStatus.pending.value,
            orderKey: 1,
            updatedAt: DateTime.utc(2026, 10, 7),
          ),
        );
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
        songCatalogDatabaseProvider.overrideWithValue(songDatabase),
      ],
    );
    addTearDown(container.dispose);

    final asked = <int?>[];
    final outcome = await container
        .read(signOutCommandProvider)
        .run(
          confirmDiscard: (count) async {
            asked.add(count);
            return false;
          },
        );

    expect(outcome, SignOutOutcome.cancelled);
    expect(asked, [1]);
    expect(authController.state.status, AppAuthStatus.signedIn);
  });

  test('the sign-out sequence holds the catalog controller until it ends '
      '(SO1)', () async {
    final catalogGate = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
        songCatalogDatabaseProvider.overrideWithValue(songDatabase),
        songCatalogControllerProvider.overrideWith((ref) {
          events.add('catalog-created');
          ref.onDispose(() => events.add('catalog-disposed'));
          return _GatedSongCatalogController(songDatabase, events, catalogGate);
        }),
        planningSyncControllerProvider.overrideWith(
          (ref) => _RecordingPlanningSyncController(events),
        ),
      ],
    );
    addTearDown(container.dispose);

    // No pending work: the run signs out without asking.
    final run = container
        .read(signOutCommandProvider)
        .run(confirmDiscard: (_) async => true);
    await pumpEventQueue();
    expect(
      events,
      ['catalog-created', 'catalog-sign-out'],
      reason: 'nothing else listens to the catalog controller; the command '
          'must hold it while its sign-out runs',
    );

    catalogGate.complete();
    expect(await run, SignOutOutcome.signedOut);
    await pumpEventQueue();
    expect(events, [
      'catalog-created',
      'catalog-sign-out',
      'planning-sign-out',
      'auth-sign-out',
      'catalog-disposed',
    ]);
  });
}
```

Test doubles (in the same file):
- `_SignedInAuthRepository(events)`: `restoreSession()` returns `AppAuthSession(userId: 'user-1', email: 'user@example.com')`; `watchSession()` is `const Stream.empty()`; `signOut()` adds `'auth-sign-out'`; the other members are no-ops (copy the shape of `_TestAuthRepository` in `song_list_screen_test.dart:1127-1155`).
- `_GatedSongCatalogController extends SongCatalogController`: copy the super-constructor call of `_NoopSongCatalogController` (`song_list_screen_test.dart:1170-1189`) and the no-op lifecycle and repository doubles it uses; override `handleExplicitSignOut()` to add `'catalog-sign-out'` and then `await gate.future`.
- `_RecordingPlanningSyncController extends PlanningSyncController`: copy `song_list_screen_test.dart`'s `_RecordingPlanningSyncController` and its no-op doubles; `handleExplicitSignOut()` adds `'planning-sign-out'`.

Run: expected compile failure (`signOutCommandProvider` is not defined).

- [ ] **Step 2: Implement the provider**

In `auth_providers.dart`, add the import
`import 'package:lyron_app/src/application/auth/sign_out_command.dart';`
and, below `pendingLocalWorkCounterProvider`:

```dart
/// SO1 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): the one
/// explicit sign-out command every sign-out control runs.
///
/// App-scoped, not autoDispose, and it watches nothing: a run awaits the
/// pending-work count and the confirmation dialog, and in Riverpod 3 a Ref
/// used after its provider was disposed throws.
final signOutCommandProvider = Provider<SignOutCommand>((ref) {
  final authController = ref.read(appAuthControllerProvider);
  return SignOutCommand(
    currentUserIdReader: () => authController.state.currentUserId,
    countPendingWork: ({required userId}) =>
        ref.read(pendingLocalWorkCounterProvider).count(userId: userId),
    // The song list's sequence before SO1, unchanged: both holders reset and
    // purge the signing-out user (XU5) before the auth state leaves them.
    // The catalog controller is autoDispose; the subscription holds it for
    // the whole sequence, including its own signedOut listener, whichever
    // screen started the sign-out, and releases it afterwards.
    signOut: () async {
      final catalog = ref.listen(songCatalogControllerProvider, (_, _) {});
      try {
        await catalog.read().handleExplicitSignOut();
        await ref.read(planningSyncControllerProvider).handleExplicitSignOut();
        await authController.signOut();
      } finally {
        catalog.close();
      }
    },
    reportError: (error, stackTrace) => FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'SignOutCommand',
        context: ErrorDescription('an explicit sign-out failed'),
      ),
    ),
  );
});
```

- [ ] **Step 3: Prove the lifetime test can fail**

Temporarily replace `final catalog = ref.listen(...)` / `catalog.read()` / `catalog.close()` with a plain `ref.read(songCatalogControllerProvider).handleExplicitSignOut()`. Run the lifetime test: it must fail on the first `events` expectation (`'catalog-disposed'` appears while the catalog's sign-out is held). Restore the subscription. If it does not fail, STOP and report: the test then does not pin the lifetime.

- [ ] **Step 4: Run both wiring tests green, then the full suite and the analyzer**

- [ ] **Step 5: Commit**

```bash
git add -A apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(auth): wire the sign-out command; hold the catalog controller for the sequence (SO1, SO2)"
```

---

### Task 4: The sign-out completes at the local sign-out (SO3, closes W3; AC8, AC9, AC10)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart`
- Create: `apps/lyron_app/test/application/auth/app_auth_controller_sign_out_test.dart`
- Modify: `apps/lyron_app/test/integration/sign_out_pending_work_guard_test.dart` (remove the W3 skip; add two command tests)

- [ ] **Step 1: Remove the W3 skip, add the command tests, run them red**

Delete the `// Red until Task 4 …` comment and `skip: true,` of "offline: a confirmed sign-out on a failing network …". Append to `main()`:

```dart
  // W3, AC9: the outcome is signedOut and the command's lock is released at
  // the local sign-out, while the backend revocation fails or never answers.
  for (final failingNetwork in [true, false]) {
    testWidgets(
      failingNetwork
          ? 'offline (failing network): the command signs out and a second '
                'run is not held (SO3)'
          : 'offline (network that never answers): the command signs out '
                'and a second run is not held (SO3)',
      (tester) async {
        final fixture = _Fixture(
          httpClient: failingNetwork ? _FailingHttpClient() : null,
        );
        await fixture.seed(
          tester,
          cachedSongs: true,
          cachedProjection: true,
          persistedSessionForA: true,
        );
        await fixture.pumpApp(tester);
        expect(fixture.authStatus(tester), AppAuthStatus.signedIn);

        final command = fixture.container(tester).read(signOutCommandProvider);
        final outcomes = <SignOutOutcome>[];
        unawaited(
          command.run(confirmDiscard: (_) async => true).then(outcomes.add),
        );
        await fixture.pumpFrames(tester);
        expect(outcomes, [SignOutOutcome.signedOut]);
        expect(fixture.authStatus(tester), AppAuthStatus.signedOut);
        expect(tester.takeException(), isNull);

        unawaited(
          command.run(confirmDiscard: (_) async => true).then(outcomes.add),
        );
        await fixture.pumpFrames(tester);
        expect(
          outcomes,
          [SignOutOutcome.signedOut, SignOutOutcome.signedOut],
          reason: 'a second run must not wait for the first run\'s backend '
              'request',
        );
        expect(tester.takeException(), isNull);

        await fixture.tearDown(tester);
      },
    );
  }
```

(imports: `package:lyron_app/src/application/auth/sign_out_command.dart`.)

Run the file. Expected red, against the code of Tasks 1–3:
- the UI W3 test: the recorded unhandled `AuthRetryableFetchException`;
- failing network: the first outcome is `failed` (the command reports the thrown revocation failure), and `takeException` returns it;
- never answers: `outcomes` is empty after the first pump (the run waits for the backend), and the second run gives `alreadyRunning`.

- [ ] **Step 2: Write the failing controller unit tests**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthRetryableFetchException;

/// Models gotrue's sign-out (gotrue_client.dart:1085-1108): drop the local
/// session and emit signedOut, then call the backend.
class _RevocationRepository implements AuthRepository {
  final _controller = StreamController<AppAuthSession?>.broadcast();
  final revocation = Completer<void>();
  bool emitSignedOutFirst = true;

  void dispose() => _controller.close();

  void emit(AppAuthSession? session) => _controller.add(session);

  @override
  Future<AppAuthSession?> restoreSession() async =>
      const AppAuthSession(userId: 'u1', email: 'u1@example.com');

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {}

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {}

  @override
  Future<void> signOut() async {
    if (emitSignedOutFirst) {
      _controller.add(null);
    }
    await revocation.future;
  }

  @override
  Future<void> deleteAccount() async {}
}

void main() {
  late _RevocationRepository repo;
  late AppAuthController controller;
  late List<Object> reported;

  setUp(() async {
    repo = _RevocationRepository();
    addTearDown(repo.dispose);
    controller = AppAuthController(repo);
    await controller.restoreSession();
    expect(controller.state.status, AppAuthStatus.signedIn);
    reported = [];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => reported.add(details.exception);
    addTearDown(() => FlutterError.onError = originalOnError);
  });

  test('completes at the local sign-out while the revocation never '
      'answers', () async {
    await controller.signOut().timeout(const Duration(seconds: 2));
    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test('a connectivity failure of the revocation is not reported', () async {
    await controller.signOut();
    repo.revocation.completeError(
      AuthRetryableFetchException(message: 'ClientException: offline'),
    );
    await pumpEventQueue();
    expect(reported, isEmpty);
    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test('any other revocation failure is reported once and never '
      'thrown', () async {
    await controller.signOut();
    repo.revocation.completeError(StateError('server error'));
    await pumpEventQueue();
    expect(reported, hasLength(1));
    expect(reported.single, isA<StateError>());
    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test('a failure before the signedOut event still ends signed out and is '
      'reported once', () async {
    repo.emitSignedOutFirst = false;
    final done = controller.signOut();
    repo.revocation.completeError(StateError('local storage failure'));
    await done;
    await pumpEventQueue();
    expect(controller.state.status, AppAuthStatus.signedOut);
    expect(reported, hasLength(1));
  });

  test('a revocation result after a new sign-in does not touch the new '
      'user\'s state', () async {
    await controller.signOut();
    repo.emit(const AppAuthSession(userId: 'u2', email: 'u2@example.com'));
    await pumpEventQueue();
    expect(controller.state.status, AppAuthStatus.signedIn);

    repo.revocation.completeError(
      AuthRetryableFetchException(message: 'ClientException: offline'),
    );
    await pumpEventQueue();
    expect(controller.state.status, AppAuthStatus.signedIn);
    expect(controller.state.currentUserId, 'u2');
    expect(reported, isEmpty);
  });
}
```

Check the `AuthRetryableFetchException` import against `test/shared/connectivity_failure_test.dart` and use the same one. Run: the first test times out; the failure tests see an unhandled error thrown by `signOut()`.

- [ ] **Step 3: Implement**

In `app_auth_controller.dart`, add a field next to `_isSigningOut`:

```dart
  // SO3 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): completed
  // at the local sign-out of the [signOut] call in flight.
  Completer<void>? _pendingLocalSignOut;
```

Replace `signOut()`:

```dart
  /// Explicit sign-out. Completes at the local sign-out, not at the backend
  /// revocation (SO3, W3, docs/specs/2026-10-07-sign-out-pending-work-guard.md):
  /// gotrue drops the local session and emits signedOut before it calls the
  /// backend, so this completes on that event or when the repository call
  /// settles, whichever is first. The revocation keeps running; its result
  /// is handled once by [_handleRevocationResult] and never thrown.
  Future<void> signOut() async {
    _authGeneration += 1;
    _isSigningOut = true;
    final localSignOut = Completer<void>();
    _pendingLocalSignOut = localSignOut;
    final revocation = _repository.signOut().then<(Object, StackTrace)?>(
      (_) => null,
      onError: (Object error, StackTrace stackTrace) => (error, stackTrace),
    );
    unawaited(revocation.then((_) => _completeLocalSignOut(localSignOut)));
    try {
      await localSignOut.future;
      _setState(const AppAuthState(status: AppAuthStatus.signedOut));
    } finally {
      _isSigningOut = false;
      if (identical(_pendingLocalSignOut, localSignOut)) {
        _pendingLocalSignOut = null;
      }
    }
    unawaited(revocation.then(_handleRevocationResult));
  }

  void _completeLocalSignOut(Completer<void> localSignOut) {
    if (!localSignOut.isCompleted) {
      localSignOut.complete();
    }
  }

  // Runs after the local sign-out was applied, so the app is signedOut by
  // construction: offline, the revocation's failure changes nothing (the
  // server-side session stays unrevoked, as it did before SO3).
  void _handleRevocationResult((Object, StackTrace)? failure) {
    if (failure == null) {
      return;
    }
    final (error, stackTrace) = failure;
    if (isConnectivityFailure(error)) {
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'AppAuthController',
        context: ErrorDescription(
          'signOut: the backend session revocation failed; the app is '
          'signed out locally',
        ),
      ),
    );
  }
```

At the end of `_processSessionUpdate`, after the final `_setState(_stateForSession(session));`, add:

```dart
    // SO3: the null session of a sign-out in flight is its local sign-out.
    final pendingLocalSignOut = _pendingLocalSignOut;
    if (session == null && pendingLocalSignOut != null) {
      _completeLocalSignOut(pendingLocalSignOut);
    }
```

`deleteAccount()` and `cancelReauthToPriorSession()` are not changed.

- [ ] **Step 4: Run the unit tests and the whole-app tests green, then the full suite and the analyzer**

If the W3 widget tests show "A Timer is still pending" once green: STOP and report.

- [ ] **Step 5: Commit**

```bash
git add -A apps/lyron_app/lib apps/lyron_app/test
git commit -m "fix(auth): sign-out completes at the local sign-out; offline revocation failure is not an error (SO3, W3)"
```

**Executed 2026-10-09 (`34c0996`, review follow-up `6350cbe`):**
- Harness: `_FailingHttpClient` fails at once every `/auth/v1/` request and every request that is not GET or HEAD, and leaves GET and HEAD open. A client that failed everything left PostgREST's GET retry back-off timers pending (postgrest 2.9.1 `_executeWithRetry`), the cause of the "Timer is still pending" message (not gotrue's ticker, as assumed above); and an open membership RPC (a POST, not retried) kept the sign-out's identity clear queued behind the signedIn resolution. Both fakes count `/auth/v1/logout` requests and the W3 tests assert exactly one.
- Review fixes in `signOut()`: `signedOut` is applied only if the auth generation is unchanged since the call started; a call while another is in flight joins it; the repository call starts with `Future<void>.sync`. Three more unit tests (overlapping calls, a sign-in before the revocation settles, a synchronous throw).

---

### Task 5: The warning dialog and the song list (SO1–SO3, closes W2; AC2, AC3, AC4)

**Files:**
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Create: `apps/lyron_app/lib/src/presentation/auth/sign_out_flow.dart`
- Create: `apps/lyron_app/test/presentation/auth/sign_out_flow_test.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart` (two named tests, spec intentional change 1)
- Modify: `apps/lyron_app/test/integration/sign_out_pending_work_guard_test.dart` (remove the (b) skip)

- [ ] **Step 1: Remove the (b) skip and run it red**

Delete the `// Red until Task 5 (SO2); ...` comment and `skip: true,` of test (b). Run the file: (b) fails with the recorded output; (a) is still skipped; the rest pass.

- [ ] **Step 2: Write the failing dialog tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/auth/sign_out_flow.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  Future<Future<bool>> open(WidgetTester tester, int? pendingCount) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showUnsyncedSignOutDialog(
                context,
                pendingCount: pendingCount,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('names a known count', (tester) async {
    await open(tester, 3);
    expect(find.text(AppStrings.unsyncedSignOutTitle), findsOneWidget);
    expect(
      find.text(AppStrings.unsyncedSignOutPendingMessage(count: 3)),
      findsOneWidget,
    );
  });

  testWidgets('says an unknown count is unknown', (tester) async {
    await open(tester, null);
    expect(
      find.text(AppStrings.unsyncedSignOutUnknownPendingMessage),
      findsOneWidget,
    );
  });

  testWidgets('confirm answers true', (tester) async {
    final result = await open(tester, 1);
    await tester.tap(find.text(AppStrings.unsyncedSignOutConfirmAction));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('cancel and a barrier dismiss answer false', (tester) async {
    final cancelled = await open(tester, 1);
    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();
    expect(await cancelled, isFalse);

    final dismissed = await open(tester, 1);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await dismissed, isFalse);
  });

  test('the count message is singular for one change', () {
    expect(
      AppStrings.unsyncedSignOutPendingMessage(count: 1),
      'You have 1 unsynced change. Signing out will permanently discard it.',
    );
    expect(
      AppStrings.unsyncedSignOutPendingMessage(count: 2),
      'You have 2 unsynced changes. Signing out will permanently discard '
      'them.',
    );
  });
}
```

Run: expected compile failure.

- [ ] **Step 3: Strings and the flow**

In `app_strings.dart`, replace

```dart
  static const unsyncedSignOutMessage =
      'You have unsynced modifications. Signing out will permanently discard these changes.';
```

with

```dart
  static String unsyncedSignOutPendingMessage({required int count}) =>
      count == 1
      ? 'You have 1 unsynced change. Signing out will permanently discard it.'
      : 'You have $count unsynced changes. Signing out will permanently discard them.';
  static const unsyncedSignOutUnknownPendingMessage =
      'Unsynced changes could not be counted. Signing out will permanently discard any changes that have not synced.';
```

Create `presentation/auth/sign_out_flow.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// SO3 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): the sign-out
/// warning. Shaped like `showMembershipRevocationPurgeDialog`: a known count
/// is named, `null` says the count is unknown (never a fabricated number),
/// and a barrier dismiss is Cancel.
Future<bool> showUnsyncedSignOutDialog(
  BuildContext context, {
  required int? pendingCount,
}) async {
  final count = pendingCount;
  final message = count == null
      ? AppStrings.unsyncedSignOutUnknownPendingMessage
      : AppStrings.unsyncedSignOutPendingMessage(count: count);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(AppStrings.unsyncedSignOutTitle),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.songCancelAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(AppStrings.unsyncedSignOutConfirmAction),
            ),
          ],
        ),
      ) ??
      false; // barrier dismiss: delete nothing
}

/// SO1: what every sign-out control calls. Reads the command before any
/// await; the command outlives this widget (the router may replace the
/// screen while the dialog is open), and an unmounted context answers
/// "not confirmed". The command reports its own errors, so the returned
/// future never fails.
Future<SignOutOutcome> signOutWithPendingWorkGuard(
  BuildContext context,
  WidgetRef ref,
) {
  final command = ref.read(signOutCommandProvider);
  return command.run(
    confirmDiscard: (pendingCount) async {
      if (!context.mounted) {
        return false;
      }
      return showUnsyncedSignOutDialog(context, pendingCount: pendingCount);
    },
  );
}
```

- [ ] **Step 4: The song list uses the flow**

In `song_list_screen.dart`:
- menu: `case _SongListMenuAction.signOut: unawaited(signOutWithPendingWorkGuard(context, ref));`
- delete `_signOut` (`:312-345`) entirely;
- add `import 'package:lyron_app/src/presentation/auth/sign_out_flow.dart';`;
- remove `import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';` if the analyzer reports it unused (its only use was `unifiedSyncOverviewProvider` in `_signOut`).

- [ ] **Step 5: Rewrite the two named song-list tests (spec, intentional change 1)**

In `song_list_screen_test.dart`:

1. `buildApp` gets two optional parameters, `int? songPendingWorkCount` and `int? planningPendingWorkCount`. When either is non-null, add to the overrides:

```dart
        if (songPendingWorkCount != null || planningPendingWorkCount != null)
          pendingLocalWorkCounterProvider.overrideWithValue(
            PendingLocalWorkCounter(
              readPlanningPendingWorkCount: ({required userId}) async =>
                  planningPendingWorkCount ?? 0,
              readSongPendingWorkCount: ({required userId}) async =>
                  songPendingWorkCount ?? 0,
            ),
          ),
```

(import `package:lyron_app/src/application/auth/pending_local_work_counter.dart`).

2. "shows a warning before sign out when unsynced changes exist" (`:739-759`): replace `hasUnsyncedChanges: true` with `songPendingWorkCount: 1`; after the first `pumpAndSettle()` add

```dart
    // SO2: the warning counts the current user's work, so a user is needed.
    await ProviderScope.containerOf(
      tester.element(find.byType(SongListScreen)),
    ).read(appAuthControllerProvider).restoreSession();
    await tester.pumpAndSettle();
```

and replace the message expectation with
`expect(find.text(AppStrings.unsyncedSignOutPendingMessage(count: 1)), findsOneWidget);`.

3. "shows a warning before sign out when planning mutations are unsynced" (`:761-783`): replace `hasUnsyncedChanges: false, hasUnsyncedPlanningMutations: true` with `planningPendingWorkCount: 1`, add the same `restoreSession` block, and the same message expectation.

Change nothing else in either test. If any other song-list test fails: STOP and report.

- [ ] **Step 6: Run the dialog tests, the song-list tests and (b) green, then the full suite and the analyzer**

- [ ] **Step 7: Commit**

```bash
git add -A apps/lyron_app/lib apps/lyron_app/test
git commit -m "fix(sign-out): song list warns from the user-wide pending count (SO2, SO3, W2)"
```

**Executed 2026-10-09 (`6fe62f9`):** the full suite also failed two tests in `test/app/lyron_app_test.dart` that leave `planningLocalDatabaseProvider` at its file-backed default, which never opens under fake time; the command's count waited on it. With the user's approval both override it with an in-memory database (spec, intentional change 7); no assertion changed.

---

### Task 6: The Account sign-out uses the command (SO1, closes W1; AC1, AC3)

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/account/account_screen.dart`
- Modify: `apps/lyron_app/test/presentation/account/account_screen_test.dart`
- Modify: `apps/lyron_app/test/integration/sign_out_pending_work_guard_test.dart` (remove the (a) skip)

- [ ] **Step 1: Remove the (a) skip and run it red**

Expected: the recorded output (no dialog, `signedOut`, pending planning and song work 0).

- [ ] **Step 2: Write the failing Account tests**

Add to `account_screen_test.dart` (keep the existing test):

```dart
  SignOutCommand commandWith({
    required int pendingCount,
    required void Function() onSignOut,
  }) => SignOutCommand(
    currentUserIdReader: () => 'user-1',
    countPendingWork: ({required userId}) async => pendingCount,
    signOut: () async => onSignOut(),
    reportError: (_, _) {},
  );

  testWidgets('Sign out asks with the pending count before signing out', (
    tester,
  ) async {
    var signedOut = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAuthControllerProvider.overrideWith(
            (_) => _RecordingController(),
          ),
          signOutCommandProvider.overrideWithValue(
            commandWith(pendingCount: 2, onSignOut: () => signedOut = true),
          ),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );

    await tester.tap(find.text(AppStrings.signOutAction));
    await tester.pumpAndSettle();
    expect(
      find.text(AppStrings.unsyncedSignOutPendingMessage(count: 2)),
      findsOneWidget,
    );
    expect(signedOut, isFalse);

    await tester.tap(find.text(AppStrings.unsyncedSignOutConfirmAction));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
  });

  testWidgets('Cancel in the sign-out warning does not sign out', (
    tester,
  ) async {
    var signedOut = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAuthControllerProvider.overrideWith(
            (_) => _RecordingController(),
          ),
          signOutCommandProvider.overrideWithValue(
            commandWith(pendingCount: 1, onSignOut: () => signedOut = true),
          ),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );

    await tester.tap(find.text(AppStrings.signOutAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();
    expect(signedOut, isFalse);
  });
```

(imports: `sign_out_command.dart`, `app_strings.dart`.) Run: the first test fails (no dialog; today the tile calls `controller.signOut()`).

- [ ] **Step 3: Implement**

In `account_screen.dart`:

```dart
          ListTile(
            title: const Text(AppStrings.signOutAction),
            onTap: () => unawaited(signOutWithPendingWorkGuard(context, ref)),
          ),
```

Add `import 'dart:async';` and `import 'package:lyron_app/src/presentation/auth/sign_out_flow.dart';`. The Delete account tile is unchanged (`controller` is still used by it).

- [ ] **Step 4: Run the Account tests and (a) green, then the full suite and the analyzer**

- [ ] **Step 5: Commit**

```bash
git add -A apps/lyron_app/lib apps/lyron_app/test
git commit -m "fix(sign-out): Account sign-out warns about unsynced work (SO1, W1)"
```

---

### Task 7: Documentation

**Files:** see the spec's "Documentation updates".

- [ ] ADR-020: add an "Amended: 2026-10-09" header line and a short "Amendment: the explicit sign-out warning (2026-10-09)" section: every explicit sign-out control runs `SignOutCommand`; it warns whenever the signing-out user's user-wide pending count (ADR-029 D4 counter) is nonzero or unknown, with the count or an explicit unknown message; a confirmed sign-out still deletes; the sign-out completes at the local sign-out and an offline backend revocation failure is not an error (W3); the identity clear targets the signing-out user (SO4). In the policy matrix, the explicit sign-out row reads "**Destructive** after a warning when the signing-out user has nonzero or unknown pending work (2026-10-09)".
- [ ] ADR-037: in "Amendment: current-user ownership (2026-10-06)", extend the "Explicit sign-out (XU5)" bullet: the identity row cleared on sign-out is also the signing-out user's only (SO4, 2026-10-09; O1 before).
- [ ] `docs/architecture/architecture.md`, offline-authenticated paragraph (`:220`): after "an explicit sign-out purges the user who signed out, never another user (ADR-037 amendment, 2026-10-06)", add: "Every sign-out control runs one `SignOutCommand`, which warns whenever that user's user-wide pending count is nonzero or unknown before anything is deleted; the sign-out completes at the local sign-out whatever the network does, and the identity row it clears is that user's only (`docs/specs/2026-10-07-sign-out-pending-work-guard.md`)."
- [ ] `docs/testing/testing-strategy.md`: replace "Sign-out warning routing through `unifiedSyncOverviewProvider.hasUnsyncedWork` instead of the legacy per-domain providers." with "Sign-out warning decided by `SignOutCommand` from the signing-out user's user-wide pending count (unit tests for zero, nonzero, unknown, cancel, superseded, a second run, a failing sequence and a throwing confirmation), not from the active context." Add under "Cross-user ownership pattern" (or a sibling heading) a short note: `sign_out_pending_work_guard_test.dart` runs the whole app (`LyronApp`) with the real gotrue client and a hanging or failing HTTP client, and a persisted valid session when the backend sign-out must be exercised; extend it when a sign-out control is added.
- [ ] `docs/deferred/2026-10-05-gate-cross-user-leaks.md`: remove O1 (title becomes "(C4, F5, N1, N2, O2, O3)", the status paragraph says O2–O3, the O1 section goes, the trigger paragraph drops "O1 with the next change to `persistIdentity`'s sign-out path"); add one line under the header: "O1 was closed by `docs/specs/2026-10-07-sign-out-pending-work-guard.md` (SO4)." The file name stays.
- [ ] `docs/specs/2026-10-06-cross-user-local-first-ownership.md`, "Out of scope": append to the first bullet "(closed by SO4 of `docs/specs/2026-10-07-sign-out-pending-work-guard.md`)".
- [ ] The spec's status line: "approved 2026-10-09; implemented on `fix/sign-out-pending-work-guard` (Tasks 1–6)".
- [ ] Commit: `docs: sign-out pending-work guard (ADR-020, ADR-037 amendments)`.

---

### Task 8: Adversarial review and pull request (orchestrator)

- [ ] One adversarial Opus 5.5 whole-diff review (`git diff main...HEAD`), with exactly this question: "Show an event sequence (any sign-out entry point, sessionExpired, user switch, interrupted reauth, offline state, purge) in which unsynced work is deleted without confirmation, or in which one user's sign-out affects another user's data or identity." Give the reviewer the spec, this plan and the ownership spec. Tell it not to review commit trailers.
- [ ] Exit criterion (spec): only unconfirmed data loss, a cross-user effect, or a view with no way out blocks. Fix blockers TDD-first (full suite each time); record everything else in `docs/deferred/2026-10-05-gate-cross-user-leaks.md` or a new deferred entry.
- [ ] If the CI dependency audit fails on an upstream version, fix it in a separate `chore(deps)` commit with a targeted `flutter pub upgrade <package>`.
- [ ] Push and open the PR to `main`; do not merge.
