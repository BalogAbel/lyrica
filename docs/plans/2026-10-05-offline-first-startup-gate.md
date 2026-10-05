# Offline-First Startup Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a long idle period the app shows the cached song list immediately offline. The membership gate, the router and the capability-gated affordances decide from the last known local state, never from a network answer.

**Architecture:** A pure decision function (`decideMembershipGate`) maps the last known identity, the live resolution and the pending invite to what the gate shows. `ActiveMembershipController` owns the live resolution (scoped by user) and the 15 s first-run timer, and both the gate and the router redirect read the same decision. PR 2 persists the last known capabilities on the `LastKnownIdentity` row and adds a visible "last synced" indicator.

**Tech Stack:** Flutter, Dart 3, Riverpod 3 (legacy `ChangeNotifierProvider`), Drift + build_runner, supabase_flutter 2.18.0 / supabase 2.16.2 / gotrue 2.27.2, flutter_test, fake_async.

**Spec:** `docs/specs/2026-10-05-offline-first-startup-gate.md` (decisions SG1–SG8, findings G-A–G-H)
**Branch:** `fix/offline-first-startup-gate` (PR 1). PR 2 starts from `main` after PR 1 merges, on `fix/offline-first-affordances`.
**Discipline:** TDD. Every task starts with a red test that is run and seen failing. Never edit a test to make it pass unless the task says the old assertion encoded the behaviour this slice removes.
**Verification after every task:** the FULL suite, never a subdirectory:

```bash
cd apps/lyron_app && flutter test
```

Also run `flutter analyze` (CI fails on info-level lints) and `dart format lib test` before each commit.

---

## Facts the implementer needs (verified while planning)

- **Root cause (G-A).** `SupabaseClient._getAccessToken` (`supabase-2.16.2/lib/src/supabase_client.dart:277-294`) awaits `auth.getSession()` before every PostgREST/RPC call. With an expired session that waits for gotrue's refresh retry loop: measured 10.0–12.4 s offline. The gate showed its failure screen for that whole time.
- **Widget-test fake time and gotrue.** gotrue's retry predicate measures elapsed time with the real `DateTime.now()`, while its back-off delays are fake timers. In a `testWidgets` test a failing HTTP client therefore makes the refresh loop effectively endless, and it keeps scheduling timers. Use an HTTP client whose requests **never complete**: no retry timers, deterministic. Teardown must call `client.auth.stopAutoRefresh()`, unmount the tree, then close databases. **Never** call `client.dispose()` in the test: it completes the hung refresh with an error, and app code resumes after its providers are disposed (`UnmountedRefException`). A planning spike (2026-10-05) proved this harness against the pre-fix code: after 31 s of fake time the gate still showed "Could not verify access. Check your network." and no song.
- **Provider build-time notifications.** `membershipRefreshEffectProvider` listens with `fireImmediately: true`. When the app is already signed in at the moment the effect is first read (common in tests), its callback runs while the provider is still building. Never call a method that notifies a `ChangeNotifier` provider synchronously from there. The plan schedules the refresh on a microtask, which still runs before the next frame. The same hazard exists for the two planning listeners in `planning_providers.dart`: the planning provider's `ref.listen` on the `autoDispose` `activeCatalogContextProvider` was observed firing while the widget tree was building (stack: `songMutationEntriesProvider` watching `activeCatalogContextProvider`, read from `unifiedSyncOverviewProvider`), and its callback notified `ActivePlanningContextController` synchronously ("Tried to modify a provider while the widget tree was building"). Task 6b defers both planning listeners (`syncToCatalogContext`, `handleActiveContextChanged`) to a microtask guarded by `ref.mounted`. The 10-15 s network-first gate wait and test overrides used to hide this; with the local-first gate, home builds while the catalog controller is still transitioning.
- **Backward compatibility.** 13 existing tests construct `ActiveMembershipController()` and call `update(const ActiveOrganizationSelected('org-1'))` with no user id. That must keep opening the gate.
- **`SongCatalogStore`, `PlanningLocalStore` and `LastKnownIdentityStore` have 25 hand-written test fakes** that implement the full interface. Do not add methods to those interfaces. PR 2 adds a separate `CapabilitySnapshotStore` interface and a separate `SyncFreshnessReader` class instead.

## File map

**PR 1**

| File | Change |
|---|---|
| `apps/lyron_app/lib/src/application/auth/app_auth_state.dart` | add `currentUserId` |
| `apps/lyron_app/lib/src/application/auth/membership_gate_decision.dart` | **new**: `MembershipGateView`, `decideMembershipGate` |
| `apps/lyron_app/lib/src/application/auth/active_membership_controller.dart` | rewrite: readers, user-scoped live result, first-run timer |
| `apps/lyron_app/lib/src/application/auth_providers.dart` | controller provider wiring, lifecycle identity notification, refresh effect |
| `apps/lyron_app/lib/src/presentation/auth/membership_gate.dart` | render from `viewFor`, loading view, user-scoped Retry |
| `apps/lyron_app/lib/src/router/app_router.dart` | redirect uses `allowsAuthenticatedRoutes` |
| `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart` | auth-stream `onError` |
| `apps/lyron_app/lib/src/shared/app_strings.dart` | `membershipResolvingMessage` |
| `apps/lyron_app/test/integration/offline_first_startup_gate_test.dart` | **new**: SG8 acceptance |
| `apps/lyron_app/test/integration/membership_gate_purge_test.dart` | **new**: SG2 purge handler |
| `apps/lyron_app/test/application/auth/membership_gate_decision_test.dart` | **new** |
| `apps/lyron_app/test/application/auth/active_membership_controller_test.dart` | **new** |
| `apps/lyron_app/test/application/auth/membership_gate_wiring_test.dart` | **new** |
| `apps/lyron_app/test/presentation/auth/membership_gate_test.dart` | **new** |
| `apps/lyron_app/test/application/auth/app_auth_state_test.dart`, `app_auth_controller_test.dart`, `test/router/app_router_test.dart` | extend |
| docs: ADR-040 (new), ADR-016, ADR-037, `architecture.md`, `testing-strategy.md`, two older specs, the spec, the roadmap | Task 9 |

**PR 2**

| File | Change |
|---|---|
| `apps/lyron_app/lib/src/offline/auth/last_known_identity_tables.dart` | `capabilityCodes` column |
| `apps/lyron_app/lib/src/offline/auth/last_known_identity_database.dart` | schema v3 |
| `apps/lyron_app/lib/src/application/auth/capability_snapshot_store.dart` | **new** interface |
| `apps/lyron_app/lib/src/offline/auth/drift_last_known_identity_store.dart` | implements it; `write()` keeps or clears codes |
| `apps/lyron_app/lib/src/application/auth/capability_resolver.dart` | seed from store, refresh in background, persist |
| `apps/lyron_app/lib/src/application/auth_providers.dart` | `capabilitySnapshotStoreProvider`, resolver wiring |
| `apps/lyron_app/lib/src/application/sync/sync_freshness_reader.dart` | **new** |
| `apps/lyron_app/lib/src/application/core_providers.dart` | `syncFreshnessReaderProvider` |
| `apps/lyron_app/lib/src/presentation/sync/last_synced_format.dart` | **new** |
| `apps/lyron_app/lib/src/presentation/sync/unified_sync_providers.dart` | `syncFreshnessProvider` |
| `apps/lyron_app/lib/src/presentation/sync/unified_sync_status_popup.dart` | last-synced section |
| `apps/lyron_app/lib/src/presentation/sync/unified_sync_header_control.dart` | hollow dot when not fresh |
| tests for each, plus docs | Tasks 10–17 |

---

# Part 1 — PR 1: the gate (SG1–SG5, SG8)

### Task 1: Red acceptance test with the real auth client (SG8)

**Files:**
- Create: `apps/lyron_app/test/integration/offline_first_startup_gate_test.dart`

- [ ] **Step 1: Write the test file**

```dart
// SG8 (docs/specs/2026-10-05-offline-first-startup-gate.md): the startup
// path with the REAL auth client. Every other offline startup test replaces
// the membership and session readers with fakes that answer instantly, which
// is exactly why the 10-15 s gate wait (G-A) was never caught.
//
// The HTTP client never completes a request: a connection that opens and
// never answers, the worst real network shape. It is also the only shape
// that is deterministic under widget-test fake time: gotrue's refresh retry
// loop measures elapsed time with the real DateTime.now() while its back-off
// delays are fake timers, so a failing client makes the loop endless here.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/shared/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/drift_test_setup.dart';

class _HangingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Completer<http.StreamedResponse>().future;
  }
}

String _jwt({required int expiresAtSeconds}) {
  String encode(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode({'sub': 'user-1', 'exp': expiresAtSeconds})}.signature';
}

/// A persisted session whose access token expired five hours ago -- what a
/// device holds after a long idle period (jwt_expiry is 3600 s).
String _expiredSessionJson() {
  final issuedAt = DateTime.now().subtract(const Duration(hours: 5));
  return jsonEncode({
    'access_token': _jwt(
      expiresAtSeconds: issuedAt.millisecondsSinceEpoch ~/ 1000,
    ),
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-1',
    'user': {
      'id': 'user-1',
      'aud': 'authenticated',
      'email': 'demo@lyron.local',
      'app_metadata': <String, Object>{},
      'user_metadata': <String, Object>{},
      'created_at': issuedAt.toIso8601String(),
    },
  });
}

class _Fixture {
  _Fixture()
    : songDatabase = SongCatalogDatabase.inMemory(),
      identityDatabase = LastKnownIdentityDatabase.inMemory(),
      client = SupabaseClient(
        'https://test.supabase.co',
        'anon-key',
        httpClient: _HangingHttpClient(),
      );

  final SongCatalogDatabase songDatabase;
  final LastKnownIdentityDatabase identityDatabase;
  final SupabaseClient client;

  Future<void> seed(
    WidgetTester tester, {
    required bool persistedSession,
  }) async {
    await tester.runAsync(() async {
      await DriftSongCatalogStore(songDatabase).replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [
          SongSummary(id: 'song-1', slug: 'egy-ut', title: 'Egy út'),
        ],
        sources: const [SongSource(id: 'song-1', source: '{title:Egy út}\n')],
        refreshedAt: DateTime.utc(2026, 10, 1),
      );
      await DriftLastKnownIdentityStore(identityDatabase).write(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'demo@lyron.local',
          organizationId: 'org-1',
        ),
      );
      if (persistedSession) {
        await client.auth.setInitialSession(_expiredSessionJson());
      }
    });
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      isolatedSongCatalogProviderScope(
        songCatalogDatabase: songDatabase,
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          lastKnownIdentityDatabaseProvider.overrideWithValue(
            identityDatabase,
          ),
        ],
        child: LyronApp(),
      ),
    );
    // One second of fake time: far below gotrue's 10 s refresh budget, so
    // nothing asserted below may depend on the network.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tearDown(WidgetTester tester) async {
    // Never dispose the client here: dispose completes the hung refresh with
    // an error, and the app code waiting on it would resume after its
    // providers are gone.
    client.auth.stopAutoRefresh();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() async {
      await songDatabase.close();
      await identityDatabase.close();
    });
  }
}

void main() {
  suppressDriftMultipleDatabaseWarnings();

  testWidgets(
    'signed in with an expired token on a hung network: the cached song '
    'list is the first screen (G-A)',
    (tester) async {
      final fixture = _Fixture();
      await fixture.seed(tester, persistedSession: true);
      await fixture.pumpApp(tester);

      expect(
        find.text(AppStrings.membershipConnectivityFailureMessage),
        findsNothing,
      );
      expect(find.text('Egy út'), findsOneWidget);

      await fixture.tearDown(tester);
    },
  );

  testWidgets(
    'cold start straight into sessionExpired: the cached song list and the '
    're-auth banner are the first screen (G-B)',
    (tester) async {
      final fixture = _Fixture();
      await fixture.seed(tester, persistedSession: false);
      await fixture.pumpApp(tester);

      expect(
        find.text(AppStrings.membershipConnectivityFailureMessage),
        findsNothing,
      );
      expect(find.text('Egy út'), findsOneWidget);
      expect(find.byKey(const ValueKey('reauth-banner')), findsOneWidget);

      await fixture.tearDown(tester);
    },
  );
}
```

- [ ] **Step 2: Run it and see both tests fail**

Run: `cd apps/lyron_app && flutter test test/integration/offline_first_startup_gate_test.dart`
Expected: 2 failures. Both report `Expected: no matching candidates` / `Found 1 widget with text "Could not verify access. Check your network."`, or, if that assertion order changes, `Expected: exactly one matching candidate` for `"Egy út"`. Any other failure (compile error, pending timer, `UnmountedRefException`) means the harness is wrong: fix it before going on.

- [ ] **Step 3: Skip both tests until Task 7 makes them pass**

Add `skip: true, // S0 Task 7 removes this` as the last argument of both `testWidgets(...)` calls, so every commit on the branch stays green.

- [ ] **Step 4: Run the full suite**

Run: `cd apps/lyron_app && flutter test`
Expected: PASS (the two new tests are reported as skipped).

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/test/integration/offline_first_startup_gate_test.dart
git commit -m "$(cat <<'EOF'
test(auth): offline startup with the real auth client (S0 red)

Reproduces G-A and G-B with a real SupabaseClient, an expired session and
a network that never answers. Skipped until the gate fix lands.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `AppAuthState.currentUserId`

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth/app_auth_state.dart`
- Test: `apps/lyron_app/test/application/auth/app_auth_state_test.dart`

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `app_auth_state_test.dart`:

```dart
  group('currentUserId', () {
    const session = AppAuthSession(userId: 'live', email: 'live@x');
    const lastKnown = AppAuthSession(userId: 'cached', email: 'cached@x');

    test('is the live session user when signed in', () {
      const state = AppAuthState(
        status: AppAuthStatus.signedIn,
        session: session,
      );
      expect(state.currentUserId, 'live');
    });

    test('is the last known session user when the session expired', () {
      const state = AppAuthState(
        status: AppAuthStatus.sessionExpired,
        lastKnownSession: lastKnown,
      );
      expect(state.currentUserId, 'cached');
    });

    test('is null while initializing or signed out', () {
      expect(
        const AppAuthState(status: AppAuthStatus.initializing).currentUserId,
        isNull,
      );
      expect(
        const AppAuthState(
          status: AppAuthStatus.signedOut,
          lastKnownSession: lastKnown,
        ).currentUserId,
        isNull,
      );
    });
  });
```

- [ ] **Step 2: Run and see it fail**

Run: `cd apps/lyron_app && flutter test test/application/auth/app_auth_state_test.dart`
Expected: compile error, `The getter 'currentUserId' isn't defined for the type 'AppAuthState'`.

- [ ] **Step 3: Implement**

In `app_auth_state.dart`, add after the `lastKnownSession` field:

```dart
  /// The user the app is acting for: the live session's user when signed
  /// in, the last known session's user when offline-authenticated
  /// (ADR-020), otherwise nobody.
  String? get currentUserId => switch (status) {
    AppAuthStatus.signedIn => session?.userId,
    AppAuthStatus.sessionExpired => lastKnownSession?.userId,
    AppAuthStatus.initializing || AppAuthStatus.signedOut => null,
  };
```

- [ ] **Step 4: Run the test file, then the full suite**

Run: `cd apps/lyron_app && flutter test test/application/auth/app_auth_state_test.dart && flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/application/auth/app_auth_state.dart apps/lyron_app/test/application/auth/app_auth_state_test.dart
git commit -m "$(cat <<'EOF'
feat(auth): expose the current user across signedIn and sessionExpired

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: The gate decision table (SG1, SG2, SG4)

**Files:**
- Create: `apps/lyron_app/lib/src/application/auth/membership_gate_decision.dart`
- Test: `apps/lyron_app/test/application/auth/membership_gate_decision_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';

void main() {
  const selected = ActiveOrganizationResolution.selected('org-1');
  const empty = ActiveOrganizationResolution.verifiedEmpty();
  const offline = ActiveOrganizationResolution.unknownConnectivityFailure();
  const broken = ActiveOrganizationResolution.unknownNonConnectivityFailure();

  MembershipGateView decide({
    String? known,
    ActiveOrganizationResolution? live,
    bool pending = false,
    bool awaiting = false,
  }) {
    return decideMembershipGate(
      knownOrganizationId: known,
      liveResolution: live,
      hasPendingInvite: pending,
      awaitingFirstResolution: awaiting,
    );
  }

  group('with a known organization (SG1, SG2)', () {
    test('opens before any network answer', () {
      expect(decide(known: 'org-1'), MembershipGateView.home);
      expect(decide(known: 'org-1', awaiting: true), MembershipGateView.home);
    });

    test('stays open over every failure', () {
      expect(decide(known: 'org-1', live: offline), MembershipGateView.home);
      expect(decide(known: 'org-1', live: broken), MembershipGateView.home);
    });

    test('stays open after a live verifiedEmpty until the purge runs', () {
      expect(decide(known: 'org-1', live: empty), MembershipGateView.home);
    });

    test('shows the redeem screen for a live verifiedEmpty with a pending '
        'invite', () {
      expect(
        decide(known: 'org-1', live: empty, pending: true),
        MembershipGateView.redeem,
      );
    });

    test('ignores a pending invite while membership is selected', () {
      expect(
        decide(known: 'org-1', live: selected, pending: true),
        MembershipGateView.home,
      );
    });
  });

  group('without a known organization', () {
    test('follows the live resolution', () {
      expect(decide(live: selected), MembershipGateView.home);
      expect(decide(live: empty), MembershipGateView.inviteRequired);
      expect(decide(live: empty, pending: true), MembershipGateView.redeem);
      expect(decide(live: offline), MembershipGateView.connectivityFailure);
      expect(decide(live: broken), MembershipGateView.nonConnectivityFailure);
    });

    test('shows the loading state while the first resolution runs (SG4)', () {
      expect(decide(awaiting: true), MembershipGateView.resolving);
    });

    test('shows the connectivity message when nothing is running or the '
        'first-run timer elapsed', () {
      expect(decide(), MembershipGateView.connectivityFailure);
    });
  });
}
```

- [ ] **Step 2: Run and see it fail**

Run: `cd apps/lyron_app && flutter test test/application/auth/membership_gate_decision_test.dart`
Expected: compile error, `Target of URI doesn't exist: 'package:lyron_app/src/application/auth/membership_gate_decision.dart'`.

- [ ] **Step 3: Implement**

```dart
import 'package:lyron_app/src/application/active_organization_resolution.dart';

/// What the membership gate in front of the authenticated home route shows.
/// See SG1 in docs/specs/2026-10-05-offline-first-startup-gate.md.
enum MembershipGateView {
  home,
  redeem,
  inviteRequired,
  resolving,
  connectivityFailure,
  nonConnectivityFailure,
}

/// The SG1 decision table: a pure function of local state, so no widget ever
/// awaits the network before deciding.
///
/// [knownOrganizationId] is the last known organization of the CURRENT user
/// (null when the stored identity belongs to someone else or has none).
/// [liveResolution] is the latest network resolution for the current user,
/// or null when none has completed. [awaitingFirstResolution] is true while
/// a resolution runs and the SG4 first-run timer has not elapsed.
MembershipGateView decideMembershipGate({
  required String? knownOrganizationId,
  required ActiveOrganizationResolution? liveResolution,
  required bool hasPendingInvite,
  required bool awaitingFirstResolution,
}) {
  if (knownOrganizationId != null) {
    // SG2: a live verifiedEmpty does not hide data that the ADR-035 D5 purge
    // has not removed. The purge clears the identity, which moves the
    // decision to the branch below. A pending invite is the one exception:
    // redemption only starts while its screen is mounted.
    if (liveResolution is ActiveOrganizationVerifiedEmpty &&
        hasPendingInvite) {
      return MembershipGateView.redeem;
    }
    return MembershipGateView.home;
  }
  return switch (liveResolution) {
    ActiveOrganizationSelected() => MembershipGateView.home,
    ActiveOrganizationVerifiedEmpty() =>
      hasPendingInvite
          ? MembershipGateView.redeem
          : MembershipGateView.inviteRequired,
    ActiveOrganizationUnknownConnectivityFailure() =>
      MembershipGateView.connectivityFailure,
    ActiveOrganizationUnknownNonConnectivityFailure() =>
      MembershipGateView.nonConnectivityFailure,
    null =>
      awaitingFirstResolution
          ? MembershipGateView.resolving
          : MembershipGateView.connectivityFailure,
  };
}
```

- [ ] **Step 4: Run the test file, then the full suite**

Run: `cd apps/lyron_app && flutter test test/application/auth/membership_gate_decision_test.dart && flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/application/auth/membership_gate_decision.dart apps/lyron_app/test/application/auth/membership_gate_decision_test.dart
git commit -m "$(cat <<'EOF'
feat(auth): membership gate decision table (SG1)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `ActiveMembershipController` owns the user-scoped live result and the first-run timer (SG3, SG4)

**Files:**
- Modify (full rewrite): `apps/lyron_app/lib/src/application/auth/active_membership_controller.dart`
- Test: `apps/lyron_app/test/application/auth/active_membership_controller_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/active_membership_controller.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';

void main() {
  const selected = ActiveOrganizationResolution.selected('org-1');
  const empty = ActiveOrganizationResolution.verifiedEmpty();
  const offline = ActiveOrganizationResolution.unknownConnectivityFailure();
  const broken = ActiveOrganizationResolution.unknownNonConnectivityFailure();

  MembershipGateView viewOf(ActiveMembershipController controller) =>
      controller.viewFor(hasPendingInvite: false);

  test('starts unresolved; with nothing running it shows the connectivity '
      'message', () {
    final controller = ActiveMembershipController();
    addTearDown(controller.dispose);

    expect(controller.last, isNull);
    expect(viewOf(controller), MembershipGateView.connectivityFailure);
    expect(controller.allowsAuthenticatedRoutes, isFalse);
  });

  test('an update without a user id still opens the gate (existing '
      'callers)', () {
    final controller = ActiveMembershipController()..update(selected);
    addTearDown(controller.dispose);

    expect(controller.last, selected);
    expect(viewOf(controller), MembershipGateView.home);
    expect(controller.allowsAuthenticatedRoutes, isTrue);
  });

  test('a known organization opens the gate before any resolution (SG1)', () {
    final controller = ActiveMembershipController(
      currentUserIdReader: () => 'user-1',
      knownOrganizationIdReader: () => 'org-1',
    );
    addTearDown(controller.dispose);

    expect(viewOf(controller), MembershipGateView.home);
    expect(controller.allowsAuthenticatedRoutes, isTrue);
  });

  test('a running resolution shows the loading state until the first-run '
      'timeout, then the connectivity message (SG4)', () {
    fakeAsync((async) {
      final controller = ActiveMembershipController(
        currentUserIdReader: () => 'user-1',
      );

      controller.beginResolution(userId: 'user-1');
      expect(viewOf(controller), MembershipGateView.resolving);

      async.elapse(const Duration(seconds: 14));
      expect(viewOf(controller), MembershipGateView.resolving);

      async.elapse(const Duration(seconds: 1));
      expect(viewOf(controller), MembershipGateView.connectivityFailure);

      controller.update(selected, userId: 'user-1');
      expect(viewOf(controller), MembershipGateView.home);
      controller.dispose();
    });
  });

  test('a live connectivity failure shows the message without waiting for '
      'the timer', () {
    fakeAsync((async) {
      final controller = ActiveMembershipController(
        currentUserIdReader: () => 'user-1',
      );
      controller.beginResolution(userId: 'user-1');
      controller.update(offline, userId: 'user-1');

      expect(viewOf(controller), MembershipGateView.connectivityFailure);
      controller.dispose();
    });
  });

  test('an unknown result never replaces a selected result for the same '
      'user (SG3)', () {
    final controller = ActiveMembershipController(
      currentUserIdReader: () => 'user-1',
    );
    addTearDown(controller.dispose);

    controller.update(selected, userId: 'user-1');
    controller.update(offline, userId: 'user-1');
    expect(controller.last, selected);
    controller.update(broken, userId: 'user-1');
    expect(controller.last, selected);

    controller.update(empty, userId: 'user-1');
    expect(controller.last, empty, reason: 'verifiedEmpty is not a failure');
  });

  test('a result for a user who is no longer current is dropped (SG3)', () {
    final controller = ActiveMembershipController(
      currentUserIdReader: () => 'user-2',
    );
    addTearDown(controller.dispose);

    controller.update(selected, userId: 'user-1');

    expect(controller.last, isNull);
  });

  test('another user never sees the previous user result (SG3)', () {
    var current = 'user-1';
    final controller = ActiveMembershipController(
      currentUserIdReader: () => current,
    );
    addTearDown(controller.dispose);

    controller.update(selected, userId: 'user-1');
    current = 'user-2';
    expect(controller.last, isNull);

    controller.beginResolution(userId: 'user-2');
    expect(viewOf(controller), MembershipGateView.resolving);
  });

  test('reset forgets the live resolution', () {
    final controller = ActiveMembershipController(
      currentUserIdReader: () => 'user-1',
    )..update(selected, userId: 'user-1');
    addTearDown(controller.dispose);

    controller.reset();

    expect(controller.last, isNull);
  });

  test('noteInputsChanged notifies listeners', () {
    final controller = ActiveMembershipController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.noteInputsChanged();

    expect(notifications, 1);
  });

  test('allowsAuthenticatedRoutes follows the pending invite reader', () {
    var pending = true;
    final controller = ActiveMembershipController(
      currentUserIdReader: () => 'user-1',
      knownOrganizationIdReader: () => 'org-1',
      hasPendingInviteReader: () => pending,
    )..update(empty, userId: 'user-1');
    addTearDown(controller.dispose);

    expect(controller.allowsAuthenticatedRoutes, isFalse);
    pending = false;
    expect(controller.allowsAuthenticatedRoutes, isTrue);
  });

  test('the first-run timer does nothing after dispose', () {
    fakeAsync((async) {
      final controller = ActiveMembershipController(
        currentUserIdReader: () => 'user-1',
      )..beginResolution(userId: 'user-1');
      controller.dispose();

      async.elapse(const Duration(seconds: 20));
      expect(async.pendingTimers, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run and see it fail**

Run: `cd apps/lyron_app && flutter test test/application/auth/active_membership_controller_test.dart`
Expected: compile errors, for example `The named parameter 'currentUserIdReader' isn't defined` and `The method 'viewFor' isn't defined`.

- [ ] **Step 3: Implement (replace the whole file)**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';

/// Holds the membership gate's live resolution and decides what the gate
/// shows (SG1-SG4, docs/specs/2026-10-05-offline-first-startup-gate.md).
///
/// The decision itself is [decideMembershipGate]. This class owns the two
/// inputs that are not plain reads: the live resolution, scoped by user
/// (SG3), and the first-run timer (SG4). The plain reads (current user,
/// known organization, pending invite) come in through the readers, so the
/// gate and the router redirect always evaluate the same decision.
class ActiveMembershipController extends ChangeNotifier {
  ActiveMembershipController({
    String? Function()? currentUserIdReader,
    String? Function()? knownOrganizationIdReader,
    bool Function()? hasPendingInviteReader,
    this.firstRunTimeout = const Duration(seconds: 15),
  }) : _currentUserIdReader = currentUserIdReader ?? _nobody,
       _knownOrganizationIdReader = knownOrganizationIdReader ?? _nobody,
       _hasPendingInviteReader = hasPendingInviteReader ?? _noPendingInvite;

  static String? _nobody() => null;
  static bool _noPendingInvite() => false;

  final String? Function() _currentUserIdReader;
  final String? Function() _knownOrganizationIdReader;
  final bool Function() _hasPendingInviteReader;

  /// SG4: how long the gate shows its loading state before the connectivity
  /// message (with Retry) replaces it. Above the 10 s native connect
  /// timeout, so an unroutable network reports its real failure first.
  final Duration firstRunTimeout;

  ActiveOrganizationResolution? _last;
  String? _lastUserId;
  bool _resolving = false;
  bool _firstRunTimedOut = false;
  Timer? _firstRunTimer;
  bool _disposed = false;

  /// The latest live resolution for the current user, or null when none has
  /// completed for them.
  ActiveOrganizationResolution? get last {
    final last = _last;
    if (last == null) {
      return null;
    }
    final current = _currentUserIdReader();
    if (_lastUserId != null && current != null && _lastUserId != current) {
      return null;
    }
    return last;
  }

  String? get currentUserId => _currentUserIdReader();

  MembershipGateView viewFor({required bool hasPendingInvite}) {
    return decideMembershipGate(
      knownOrganizationId: _knownOrganizationIdReader(),
      liveResolution: last,
      hasPendingInvite: hasPendingInvite,
      awaitingFirstResolution: _resolving && !_firstRunTimedOut,
    );
  }

  /// Whether authenticated routes outside the membership flow may open. The
  /// router redirect reads this, so it can never disagree with the gate.
  bool get allowsAuthenticatedRoutes =>
      viewFor(hasPendingInvite: _hasPendingInviteReader()) ==
      MembershipGateView.home;

  /// A resolution for [userId] started. Starts the SG4 first-run timer.
  void beginResolution({required String userId}) {
    if (_lastUserId != null && _lastUserId != userId) {
      _last = null;
    }
    _lastUserId = userId;
    _resolving = true;
    _firstRunTimedOut = false;
    _firstRunTimer?.cancel();
    _firstRunTimer = Timer(firstRunTimeout, () {
      _firstRunTimer = null;
      _firstRunTimedOut = true;
      _notify();
    });
    _notify();
  }

  /// Records a finished resolution (SG3). [userId] is the user the
  /// resolution was started for; omit it only where no user is known.
  void update(ActiveOrganizationResolution next, {String? userId}) {
    final current = _currentUserIdReader();
    if (userId != null && current != null && userId != current) {
      // Resolved for a user who is no longer current: never show it.
      return;
    }
    final sameUser =
        userId == null || _lastUserId == null || userId == _lastUserId;
    final isFailure =
        next is ActiveOrganizationUnknownConnectivityFailure ||
        next is ActiveOrganizationUnknownNonConnectivityFailure;
    final keepSelected =
        sameUser && _last is ActiveOrganizationSelected && isFailure;
    _stopResolving();
    if (!keepSelected) {
      _last = next;
      if (userId != null) {
        _lastUserId = userId;
      }
    }
    _notify();
  }

  /// Explicit sign-out: forget the live resolution entirely.
  void reset() {
    _last = null;
    _lastUserId = null;
    _stopResolving();
    _notify();
  }

  /// An input behind one of the readers changed (auth state, last known
  /// identity, pending invite). Lets the gate and the router re-evaluate.
  void noteInputsChanged() => _notify();

  void _stopResolving() {
    _resolving = false;
    _firstRunTimedOut = false;
    _firstRunTimer?.cancel();
    _firstRunTimer = null;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _firstRunTimer?.cancel();
    _firstRunTimer = null;
    super.dispose();
  }
}
```

- [ ] **Step 4: Fix the two callers that relied on the old non-null `last`**

`last` is now nullable, so the exhaustive `switch (membership)` in `apps/lyron_app/lib/src/presentation/auth/membership_gate.dart` stops compiling. Make the minimal change here; Task 6 rewrites the gate. Add this case after the existing `ActiveOrganizationUnknownNonConnectivityFailure() => ...` case, leaving the other cases unchanged:

```dart
      null => const Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(AppStrings.membershipConnectivityFailureMessage),
          ),
        ),
      ),
```

In `apps/lyron_app/lib/src/router/app_router.dart` nothing changes yet: `membershipController.last is! ActiveOrganizationSelected` already compiles against a nullable value.

- [ ] **Step 5: Run the test file, then the full suite**

Run: `cd apps/lyron_app && flutter test test/application/auth/active_membership_controller_test.dart && flutter test`
Expected: PASS. The 13 existing `ActiveMembershipController()..update(...)` call sites keep working because `update` without a user id behaves as before.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/application/auth/active_membership_controller.dart apps/lyron_app/lib/src/presentation/auth/membership_gate.dart apps/lyron_app/test/application/auth/active_membership_controller_test.dart
git commit -m "$(cat <<'EOF'
feat(auth): user-scoped live membership result and first-run timer

The controller starts unresolved instead of as a connectivity failure
(G-C), never lets a failure replace a selected result for the same user,
and drops results for a user who is no longer current (SG3, SG4).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Provider wiring: readers, identity notifications, refresh effect, purge handler (SG1–SG3)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth_providers.dart` (`localDataLifecycleProvider`, `activeMembershipControllerProvider`, `membershipRefreshEffectProvider`)
- Test (new): `apps/lyron_app/test/application/auth/membership_gate_wiring_test.dart`
- Test (new): `apps/lyron_app/test/integration/membership_gate_purge_test.dart`

- [ ] **Step 1: Write the failing wiring test**

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

import '../../support/drift_test_setup.dart';

const _session = AppAuthSession(userId: 'user-1', email: 'demo@lyron.local');

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._session);

  final AppAuthSession? _session;
  final _sessions = StreamController<AppAuthSession?>.broadcast();

  void dispose() => _sessions.close();

  @override
  Future<AppAuthSession?> restoreSession() async => _session;

  @override
  Stream<AppAuthSession?> watchSession() => _sessions.stream;

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
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

class _Harness {
  _Harness(this.container, this.authController);

  final ProviderContainer container;
  final AppAuthController authController;
}

Future<_Harness> _harness({
  required AppAuthSession? session,
  required ActiveOrganizationResolutionReader resolution,
  LastKnownIdentity? identity,
}) async {
  final identityStore = DriftLastKnownIdentityStore.inMemory();
  if (identity != null) {
    await identityStore.write(identity);
  }
  final repository = _FakeAuthRepository(session);
  addTearDown(repository.dispose);
  final authController = AppAuthController(
    repository,
    lastKnownIdentityStore: identityStore,
  );
  await authController.restoreSession();

  final songDatabase = SongCatalogDatabase.inMemory();
  final planningDatabase = PlanningLocalDatabase.inMemory();
  addTearDown(songDatabase.close);
  addTearDown(planningDatabase.close);

  final container = ProviderContainer(
    overrides: [
      appAuthControllerProvider.overrideWith((_) => authController),
      lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
      songCatalogDatabaseProvider.overrideWithValue(songDatabase),
      planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
      activeOrganizationResolutionProvider.overrideWithValue(resolution),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(container, authController);
}

Future<ActiveOrganizationResolution> _never() =>
    Completer<ActiveOrganizationResolution>().future;

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test('a known organization opens the gate with no network answer (SG1)', () async {
    final harness = await _harness(
      session: _session,
      identity: const LastKnownIdentity(
        userId: 'user-1',
        email: 'demo@lyron.local',
        organizationId: 'org-1',
      ),
      resolution: _never,
    );
    harness.container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();

    final controller = harness.container.read(
      activeMembershipControllerProvider,
    );
    expect(
      controller.viewFor(hasPendingInvite: false),
      MembershipGateView.home,
    );
    expect(controller.allowsAuthenticatedRoutes, isTrue);
  });

  test('another user\'s identity is not a known organization (SG1)', () async {
    final harness = await _harness(
      session: _session,
      identity: const LastKnownIdentity(
        userId: 'user-2',
        email: 'other@lyron.local',
        organizationId: 'org-1',
      ),
      resolution: _never,
    );
    harness.container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();

    expect(
      harness.container
          .read(activeMembershipControllerProvider)
          .viewFor(hasPendingInvite: false),
      MembershipGateView.resolving,
    );
  });

  test('without a known organization the gate loads, then opens on the '
      'answer (SG4, G-C)', () async {
    final answer = Completer<ActiveOrganizationResolution>();
    final harness = await _harness(
      session: _session,
      resolution: () => answer.future,
    );
    harness.container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();

    final controller = harness.container.read(
      activeMembershipControllerProvider,
    );
    expect(
      controller.viewFor(hasPendingInvite: false),
      MembershipGateView.resolving,
    );

    answer.complete(const ActiveOrganizationResolution.selected('org-1'));
    await pumpEventQueue();

    expect(
      controller.viewFor(hasPendingInvite: false),
      MembershipGateView.home,
    );
  });

  test('sessionExpired with a known organization opens the gate (G-B)', () async {
    final harness = await _harness(
      session: null,
      identity: const LastKnownIdentity(
        userId: 'user-1',
        email: 'demo@lyron.local',
        organizationId: 'org-1',
      ),
      resolution: _never,
    );
    expect(
      harness.authController.state.status,
      AppAuthStatus.sessionExpired,
    );

    expect(
      harness.container
          .read(activeMembershipControllerProvider)
          .viewFor(hasPendingInvite: false),
      MembershipGateView.home,
    );
  });

  test('an identity change notifies the gate', () async {
    final harness = await _harness(
      session: _session,
      identity: const LastKnownIdentity(
        userId: 'user-1',
        email: 'demo@lyron.local',
        organizationId: 'org-1',
      ),
      resolution: _never,
    );
    final controller = harness.container.read(
      activeMembershipControllerProvider,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    await harness.container
        .read(localDataLifecycleProvider)
        .clearIdentity(reason: PurgeReason.userSignOut);

    expect(notifications, greaterThan(0));
    expect(
      controller.viewFor(hasPendingInvite: false),
      isNot(MembershipGateView.home),
    );
  });

  test('an explicit sign-out forgets the live resolution (SG3)', () async {
    final harness = await _harness(
      session: _session,
      resolution: () async =>
          const ActiveOrganizationResolution.selected('org-1'),
    );
    harness.container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();
    final controller = harness.container.read(
      activeMembershipControllerProvider,
    );
    expect(controller.last, isA<ActiveOrganizationSelected>());

    await harness.authController.signOut();
    await pumpEventQueue();

    expect(controller.last, isNull);
  });
}
```

- [ ] **Step 2: Run and see it fail**

Run: `cd apps/lyron_app && flutter test test/application/auth/membership_gate_wiring_test.dart`
Expected: failures. "a known organization opens the gate" gets `connectivityFailure` instead of `home` (the provider passes no readers); "an identity change notifies the gate" sees 0 notifications; "without a known organization" sees `connectivityFailure` instead of `resolving`.

- [ ] **Step 3: Wire the controller provider**

In `auth_providers.dart`, replace

```dart
final activeMembershipControllerProvider =
    ChangeNotifierProvider<ActiveMembershipController>(
      (_) => ActiveMembershipController(),
    );
```

with

```dart
/// SG1 (docs/specs/2026-10-05-offline-first-startup-gate.md): the gate
/// decides from the current user's last known organization first. The
/// readers are evaluated on every decision; the listeners below re-run it
/// when an input changes.
final activeMembershipControllerProvider =
    ChangeNotifierProvider<ActiveMembershipController>((ref) {
      final authController = ref.read(appAuthControllerProvider);
      final pendingInvites = ref.read(pendingInviteTokenControllerProvider);
      final controller = ActiveMembershipController(
        currentUserIdReader: () => authController.state.currentUserId,
        knownOrganizationIdReader: () {
          final userId = authController.state.currentUserId;
          final identity = authController.lastKnownIdentity;
          if (userId == null ||
              identity == null ||
              identity.userId != userId) {
            return null;
          }
          return identity.organizationId;
        },
        hasPendingInviteReader: () => pendingInvites.current != null,
      );
      authController.addListener(controller.noteInputsChanged);
      pendingInvites.addListener(controller.noteInputsChanged);
      ref.onDispose(() {
        authController.removeListener(controller.noteInputsChanged);
        pendingInvites.removeListener(controller.noteInputsChanged);
      });
      return controller;
    });
```

- [ ] **Step 4: Notify the gate on every identity write and clear**

In `localDataLifecycleProvider`, replace

```dart
    noteLastKnownIdentity: (identity) {
      ref.read(appAuthControllerProvider).noteLastKnownIdentity(identity);
    },
```

with

```dart
    noteLastKnownIdentity: (identity) {
      ref.read(appAuthControllerProvider).noteLastKnownIdentity(identity);
      // SG1: the gate reads the identity through a reader; a purge or a
      // first write must re-run its decision. Deliberately not through
      // AppAuthController.notifyListeners: capabilityResolverProvider
      // invalidates on every notification from that controller.
      ref.read(activeMembershipControllerProvider).noteInputsChanged();
    },
```

- [ ] **Step 5: Rewrite the refresh effect**

Replace the whole `membershipRefreshEffectProvider` definition with:

```dart
final membershipRefreshEffectProvider = Provider<void>((ref) {
  final membershipController = ref.read(activeMembershipControllerProvider);
  final authController = ref.read(appAuthControllerProvider);

  Future<void> refreshMembership() async {
    final userId = authController.state.session?.userId;
    if (userId == null) {
      return;
    }
    membershipController.beginResolution(userId: userId);
    final reader = ref.read(membershipResolutionProvider);
    final result = await reader();
    membershipController.update(result, userId: userId);
  }

  // Always on a microtask: the status listener below fires immediately
  // while this provider is still building, and beginResolution notifies the
  // membership controller's listeners. A microtask still runs before the
  // next frame, so the gate never renders the pre-resolution state (G-C).
  void scheduleRefresh() {
    scheduleMicrotask(() => unawaited(refreshMembership()));
  }

  ref.listen<AppAuthStatus>(
    appAuthControllerProvider.select((c) => c.state.status),
    (prev, next) {
      if (next == AppAuthStatus.signedIn && prev != AppAuthStatus.signedIn) {
        scheduleRefresh();
      }
      // SG3: an explicit sign-out forgets the live resolution. prev is null
      // only for the immediate first call, where there is nothing to forget.
      if (next == AppAuthStatus.signedOut &&
          prev != null &&
          prev != AppAuthStatus.signedOut) {
        membershipController.reset();
      }
    },
    fireImmediately: true,
  );

  ref.listen<RedeemState>(redeemControllerProvider.select((c) => c.state), (
    prev,
    next,
  ) {
    if (next is RedeemStateSuccess && prev is! RedeemStateSuccess) {
      scheduleRefresh();
    }
  });

  // SG2: a D5 purge clears the identity, but the live resolution held here
  // refreshes only on sign-in edges, so it can still be an older `selected`
  // (the second D5 confirmation usually comes from a catalog or planning
  // refresh). The coordinator calls this only after a purge genuinely ran,
  // which itself took two fresh verified-empty resolutions.
  final coordinator = ref.read(
    verifiedEmptyMembershipCleanupCoordinatorProvider,
  );
  Future<void> recordPurge({required String userId}) async {
    membershipController.update(
      const ActiveOrganizationResolution.verifiedEmpty(),
      userId: userId,
    );
  }

  coordinator.addHandler(recordPurge);
  ref.onDispose(() => coordinator.removeHandler(recordPurge));
});
```

`auth_providers.dart` already imports `dart:async` (for `unawaited`) and `active_organization_resolution.dart`, and already uses `verifiedEmptyMembershipCleanupCoordinatorProvider`; no new imports are needed.

- [ ] **Step 6: Run the wiring test**

Run: `cd apps/lyron_app && flutter test test/application/auth/membership_gate_wiring_test.dart`
Expected: PASS.

- [ ] **Step 7: Write the purge-handler integration test (SG2)**

Create `apps/lyron_app/test/integration/membership_gate_purge_test.dart`:

```dart
// SG2 (docs/specs/2026-10-05-offline-first-startup-gate.md): with a known
// organization, a fresh verifiedEmpty keeps the home route until the ADR-035
// D5 purge has genuinely run; then the gate shows InviteRequiredScreen. The
// second D5 confirmation comes from a catalog refresh here, not from the
// gate's own resolution, which is exactly the case the purge handler covers.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/drift_test_setup.dart';

const _userId = 'user-1';
const _organizationId = 'org-1';
const _email = 'demo@lyron.local';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test('a live verifiedEmpty keeps the home route until the D5 purge runs, '
      'then the gate shows InviteRequired (SG2)', () async {
    final songDatabase = SongCatalogDatabase.inMemory();
    final songStore = DriftSongCatalogStore(songDatabase);
    addTearDown(songDatabase.close);
    await songStore.replaceActiveSnapshot(
      userId: _userId,
      organizationId: _organizationId,
      summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
      sources: const [SongSource(id: 'song-1', source: '{title: Cached Song}')],
      refreshedAt: DateTime.utc(2026, 10, 1, 12),
    );

    final planningDatabase = PlanningLocalDatabase.inMemory();
    final planningStore = DriftPlanningLocalStore(planningDatabase);
    addTearDown(planningDatabase.close);

    final identityStore = DriftLastKnownIdentityStore.inMemory();
    await identityStore.write(
      const LastKnownIdentity(
        userId: _userId,
        email: _email,
        organizationId: _organizationId,
      ),
    );

    final authRepository = _SignedInAuthRepository();
    addTearDown(authRepository.dispose);
    final authController = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
    );
    await authController.restoreSession();

    var monotonicElapsed = Duration.zero;
    final lifecycle = LocalDataLifecycle(
      songCatalogStore: songStore,
      planningLocalStore: planningStore,
      identityStore: identityStore,
      noteLastKnownIdentity: authController.noteLastKnownIdentity,
      eventsRecorder: _NoopLocalDataEventsRecorder(),
      monotonicNow: () => monotonicElapsed,
    );
    final coordinator = VerifiedEmptyMembershipCleanupCoordinator(
      localDataLifecycle: lifecycle,
      countPendingWork: ({required userId}) async => 0,
      requestConfirmation: ({required pendingCount}) async => throw StateError(
        'zero pending work must skip the confirmation dialog',
      ),
      invalidateLastKnownIdentityPersistence: () async {},
    );

    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(
          SupabaseClient('http://127.0.0.1:54321', 'anon-key'),
        ),
        appAuthControllerProvider.overrideWith((_) => authController),
        songCatalogStoreProvider.overrideWithValue(songStore),
        planningLocalStoreProvider.overrideWithValue(planningStore),
        lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        localDataLifecycleProvider.overrideWithValue(lifecycle),
        verifiedEmptyMembershipCleanupCoordinatorProvider.overrideWithValue(
          coordinator,
        ),
        appForegroundStateProvider.overrideWithValue(_ForegroundState()),
        activeOrganizationResolutionProvider.overrideWithValue(
          () async => const ActiveOrganizationResolution.verifiedEmpty(),
        ),
        activeOrganizationReaderProvider.overrideWithValue(() async => null),
        catalogSessionVerifierProvider.overrideWithValue(
          () async => CatalogSessionStatus.verified,
        ),
        supabaseSongRepositoryProvider.overrideWithValue(
          SupabaseSongRepository.testing(
            listSongsRows: () async => throw StateError('not reached'),
            getSongRow: (id) async => throw StateError('not reached'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(
      songCatalogControllerProvider,
      (_, _) {},
    );
    addTearDown(keepAlive.close);

    // The sign-in edge resolution: a fresh verifiedEmpty for a user whose
    // identity still names org-1.
    container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();
    final gate = container.read(activeMembershipControllerProvider);
    expect(gate.last, isA<ActiveOrganizationVerifiedEmpty>());
    expect(gate.viewFor(hasPendingInvite: false), MembershipGateView.home);

    // First counted confirmation (catalog refresh): marker only.
    final catalog = container.read(songCatalogControllerProvider);
    await catalog.refreshCatalog();
    expect(gate.viewFor(hasPendingInvite: false), MembershipGateView.home);

    // Second confirmation after the D5.3 cooldown: the purge runs.
    monotonicElapsed += const Duration(seconds: 61);
    await catalog.refreshCatalog();
    await pumpEventQueue();

    expect(await identityStore.read(), isNull);
    expect(
      gate.viewFor(hasPendingInvite: false),
      MembershipGateView.inviteRequired,
    );
  });

  test('the purge handler records verifiedEmpty even when the gate still '
      'held an older selected result (SG2)', () async {
    // Same as above, but the gate's own resolution answered `selected`
    // before the revocation; only the purge handler can move it.
    final songDatabase = SongCatalogDatabase.inMemory();
    final songStore = DriftSongCatalogStore(songDatabase);
    addTearDown(songDatabase.close);
    await songStore.replaceActiveSnapshot(
      userId: _userId,
      organizationId: _organizationId,
      summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
      sources: const [SongSource(id: 'song-1', source: '{title: Cached Song}')],
      refreshedAt: DateTime.utc(2026, 10, 1, 12),
    );
    final planningDatabase = PlanningLocalDatabase.inMemory();
    final planningStore = DriftPlanningLocalStore(planningDatabase);
    addTearDown(planningDatabase.close);
    final identityStore = DriftLastKnownIdentityStore.inMemory();
    await identityStore.write(
      const LastKnownIdentity(
        userId: _userId,
        email: _email,
        organizationId: _organizationId,
      ),
    );
    final authRepository = _SignedInAuthRepository();
    addTearDown(authRepository.dispose);
    final authController = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
    );
    await authController.restoreSession();
    var monotonicElapsed = Duration.zero;
    final lifecycle = LocalDataLifecycle(
      songCatalogStore: songStore,
      planningLocalStore: planningStore,
      identityStore: identityStore,
      noteLastKnownIdentity: authController.noteLastKnownIdentity,
      eventsRecorder: _NoopLocalDataEventsRecorder(),
      monotonicNow: () => monotonicElapsed,
    );
    final coordinator = VerifiedEmptyMembershipCleanupCoordinator(
      localDataLifecycle: lifecycle,
      countPendingWork: ({required userId}) async => 0,
      requestConfirmation: ({required pendingCount}) async => throw StateError(
        'zero pending work must skip the confirmation dialog',
      ),
      invalidateLastKnownIdentityPersistence: () async {},
    );
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(
          SupabaseClient('http://127.0.0.1:54321', 'anon-key'),
        ),
        appAuthControllerProvider.overrideWith((_) => authController),
        songCatalogStoreProvider.overrideWithValue(songStore),
        planningLocalStoreProvider.overrideWithValue(planningStore),
        lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        localDataLifecycleProvider.overrideWithValue(lifecycle),
        verifiedEmptyMembershipCleanupCoordinatorProvider.overrideWithValue(
          coordinator,
        ),
        appForegroundStateProvider.overrideWithValue(_ForegroundState()),
        activeOrganizationResolutionProvider.overrideWithValue(
          () async => const ActiveOrganizationResolution.selected(
            _organizationId,
          ),
        ),
        activeOrganizationReaderProvider.overrideWithValue(() async => null),
        catalogSessionVerifierProvider.overrideWithValue(
          () async => CatalogSessionStatus.verified,
        ),
        supabaseSongRepositoryProvider.overrideWithValue(
          SupabaseSongRepository.testing(
            listSongsRows: () async => throw StateError('not reached'),
            getSongRow: (id) async => throw StateError('not reached'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(
      songCatalogControllerProvider,
      (_, _) {},
    );
    addTearDown(keepAlive.close);

    container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();
    final gate = container.read(activeMembershipControllerProvider);
    expect(gate.last, isA<ActiveOrganizationSelected>());

    final catalog = container.read(songCatalogControllerProvider);
    await catalog.refreshCatalog();
    monotonicElapsed += const Duration(seconds: 61);
    await catalog.refreshCatalog();
    await pumpEventQueue();

    expect(gate.last, isA<ActiveOrganizationVerifiedEmpty>());
    expect(
      gate.viewFor(hasPendingInvite: false),
      MembershipGateView.inviteRequired,
    );
  });
}

class _SignedInAuthRepository implements AuthRepository {
  final _sessions = StreamController<AppAuthSession?>.broadcast();

  void dispose() => _sessions.close();

  @override
  Future<AppAuthSession?> restoreSession() async =>
      const AppAuthSession(userId: _userId, email: _email);

  @override
  Stream<AppAuthSession?> watchSession() => _sessions.stream;

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
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

class _ForegroundState implements AppForegroundState {
  final _changes = StreamController<bool>.broadcast();

  @override
  bool get isForeground => true;

  @override
  Stream<bool> watchForeground() => _changes.stream;
}

class _NoopLocalDataEventsRecorder implements LocalDataEventsRecorder {
  @override
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordEviction({
    required String target,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordRejectedEmptySnapshot({
    required String userId,
    required String organizationId,
  }) async {}

  @override
  Future<void> recordStorageWriteFailure({String? userId}) async {}

  @override
  Future<void> recordMembershipRevocationMarked({
    required String userId,
  }) async {}

  @override
  Future<void> recordMembershipRevocationCleared({
    required String userId,
  }) async {}

  @override
  Future<void> recordMembershipRevocationPurgeDeclined({
    required String userId,
    required MembershipRevocationPurgeDeclineReason reason,
  }) async {}
}
```

- [ ] **Step 8: Run the purge test**

Run: `cd apps/lyron_app && flutter test test/integration/membership_gate_purge_test.dart`
Expected: PASS. To confirm it tests the handler, temporarily comment out `coordinator.addHandler(recordPurge);`: the second test must then fail with `Expected: <Instance of 'ActiveOrganizationVerifiedEmpty'>`. Restore the line.

- [ ] **Step 9: Run the full suite**

Run: `cd apps/lyron_app && flutter test`
Expected: PASS. If a test that pumps `LyronApp` with the real `membershipRefreshEffectProvider` now fails, read the failure before changing anything: the effect now also builds `verifiedEmptyMembershipCleanupCoordinatorProvider`, whose databases open lazily. A real failure there is a wiring bug to fix, not a test to weaken.

- [ ] **Step 10: Commit**

```bash
git add apps/lyron_app/lib/src/application/auth_providers.dart apps/lyron_app/test/application/auth/membership_gate_wiring_test.dart apps/lyron_app/test/integration/membership_gate_purge_test.dart
git commit -m "$(cat <<'EOF'
feat(auth): gate reads the last known identity and records purges

The membership controller gets the current user, the known organization
and the pending invite through readers, re-evaluates on identity writes,
starts resolutions on a microtask, forgets them on sign-out, and records
verifiedEmpty when a D5 purge genuinely ran (SG1-SG3).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: The gate widget renders the decision (SG1, SG4)

**Files:**
- Modify (full rewrite): `apps/lyron_app/lib/src/presentation/auth/membership_gate.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Test (new): `apps/lyron_app/test/presentation/auth/membership_gate_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/active_membership_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/membership_gate.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Future<void> _pumpGate(
  WidgetTester tester,
  ActiveMembershipController controller, {
  ActiveOrganizationResolutionReader? reader,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeMembershipControllerProvider.overrideWith((_) => controller),
        if (reader != null) membershipResolutionProvider.overrideWithValue(reader),
      ],
      child: const MaterialApp(
        home: MembershipGate(child: Text('home-child')),
      ),
    ),
  );
}

void main() {
  testWidgets('a known organization shows the home route with no '
      'resolution (SG1)', (tester) async {
    await _pumpGate(
      tester,
      ActiveMembershipController(
        currentUserIdReader: () => 'user-1',
        knownOrganizationIdReader: () => 'org-1',
      ),
    );

    expect(find.text('home-child'), findsOneWidget);
  });

  testWidgets('a running first resolution shows the loading copy, never the '
      'failure (G-C)', (tester) async {
    await _pumpGate(
      tester,
      ActiveMembershipController(currentUserIdReader: () => 'user-1')
        ..beginResolution(userId: 'user-1'),
    );

    expect(find.text(AppStrings.membershipResolvingMessage), findsOneWidget);
    expect(
      find.text(AppStrings.membershipConnectivityFailureMessage),
      findsNothing,
    );
  });

  testWidgets('after the first-run timeout the connectivity message and '
      'Retry appear (SG4)', (tester) async {
    await _pumpGate(
      tester,
      ActiveMembershipController(currentUserIdReader: () => 'user-1')
        ..beginResolution(userId: 'user-1'),
    );

    await tester.pump(const Duration(seconds: 15));

    expect(
      find.text(AppStrings.membershipConnectivityFailureMessage),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('membership-gate-retry')), findsOneWidget);
  });

  testWidgets('Retry resolves for the current user and opens the gate', (
    tester,
  ) async {
    final answer = Completer<ActiveOrganizationResolution>();
    final controller = ActiveMembershipController(
      currentUserIdReader: () => 'user-1',
    )..update(
        const ActiveOrganizationResolution.unknownConnectivityFailure(),
        userId: 'user-1',
      );
    await _pumpGate(tester, controller, reader: () => answer.future);

    await tester.tap(find.byKey(const ValueKey('membership-gate-retry')));
    await tester.pump();
    answer.complete(const ActiveOrganizationResolution.selected('org-1'));
    await tester.pump();

    expect(find.text('home-child'), findsOneWidget);
    expect(controller.last, isA<ActiveOrganizationSelected>());
  });

  testWidgets('a non-connectivity failure without a known organization shows '
      'its own message', (tester) async {
    await _pumpGate(
      tester,
      ActiveMembershipController(currentUserIdReader: () => 'user-1')
        ..update(
          const ActiveOrganizationResolution.unknownNonConnectivityFailure(),
          userId: 'user-1',
        ),
    );

    expect(
      find.text(AppStrings.membershipNonConnectivityFailureMessage),
      findsOneWidget,
    );
  });
}
```

Do not add `addTearDown(controller.dispose)`: Riverpod disposes a notifier returned from `overrideWith` when the scope unmounts, and a second dispose throws.

- [ ] **Step 2: Run and see it fail**

Run: `cd apps/lyron_app && flutter test test/presentation/auth/membership_gate_test.dart`
Expected: compile error, `Member not found: 'membershipResolvingMessage'`.

- [ ] **Step 3: Add the string**

In `app_strings.dart`, next to `membershipConnectivityFailureMessage`:

```dart
  static const membershipResolvingMessage = 'Checking access...';
```

- [ ] **Step 4: Rewrite the gate**

Replace the whole of `membership_gate.dart` with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/invite_required_screen.dart';
import 'package:lyron_app/src/presentation/auth/redeem_progress_screen.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Renders the SG1 decision (docs/specs/2026-10-05-offline-first-startup
/// -gate.md). The decision reads local state only, so this widget never
/// waits for the network before showing the home route.
class MembershipGate extends ConsumerWidget {
  const MembershipGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(activeMembershipControllerProvider);
    final pending = ref.watch(pendingInviteTokenControllerProvider).current;

    return switch (membership.viewFor(hasPendingInvite: pending != null)) {
      MembershipGateView.home => child,
      MembershipGateView.redeem => const RedeemProgressScreen(),
      MembershipGateView.inviteRequired => const InviteRequiredScreen(),
      // Text only, like the bootstrap screen: an indeterminate spinner would
      // keep pumpAndSettle from ever settling in widget tests.
      MembershipGateView.resolving => const Scaffold(
        body: SafeArea(
          child: Center(child: Text(AppStrings.membershipResolvingMessage)),
        ),
      ),
      MembershipGateView.connectivityFailure => Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(AppStrings.membershipConnectivityFailureMessage),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('membership-gate-retry'),
                  onPressed: () => unawaited(_retry(ref)),
                  child: const Text(AppStrings.retryAction),
                ),
              ],
            ),
          ),
        ),
      ),
      MembershipGateView.nonConnectivityFailure => const Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(AppStrings.membershipNonConnectivityFailureMessage),
          ),
        ),
      ),
    };
  }

  Future<void> _retry(WidgetRef ref) async {
    final controller = ref.read(activeMembershipControllerProvider);
    final reader = ref.read(membershipResolutionProvider);
    final userId = controller.currentUserId;
    if (userId != null) {
      controller.beginResolution(userId: userId);
    }
    final resolution = await reader();
    controller.update(resolution, userId: userId);
  }
}
```

- [ ] **Step 5: Run the widget test, then the full suite**

Run: `cd apps/lyron_app && flutter test test/presentation/auth/membership_gate_test.dart && flutter test`
Expected: PASS. `test/integration/invite_redeem_flow_test.dart` keeps passing: its controller has no readers, so the decision falls through to the live resolution exactly as before.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/auth/membership_gate.dart apps/lyron_app/lib/src/shared/app_strings.dart apps/lyron_app/test/presentation/auth/membership_gate_test.dart
git commit -m "$(cat <<'EOF'
feat(auth): membership gate renders the local decision

Adds the loading state for a first resolution and scopes Retry to the
current user (SG1, SG4, G-C).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6b: Planning listeners notify on a microtask (build-time notification)

**Problem.** Task 7 opens the gate in the first frames, so home builds while the catalog controller is still transitioning. A widget build reads `activeCatalogContextProvider` (`autoDispose`) through `songMutationEntriesProvider` -> `unifiedSyncOverviewProvider`, and the `ref.listen<ActiveCatalogContext?>(activeCatalogContextProvider, ...)` callback in `activePlanningContextControllerProvider` was observed firing in that build. It calls `controller.syncToCatalogContext(next)`, which notifies a `ChangeNotifier` synchronously: "Tried to modify a provider while the widget tree was building" (`ActivePlanningContextController._setState`). The listener on `activePlanningContextProvider` in `planningSyncControllerProvider` has the same hazard: `handleActiveContextChanged(null)` calls `_setState` before its first await.

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning_providers.dart` (both `ref.listen` callbacks)

- [ ] **Step 1: Red test = the two SG8 acceptance tests**

With Task 7's working-tree changes present (the two `skip` lines removed), run `cd apps/lyron_app && flutter test test/integration/offline_first_startup_gate_test.dart`. Expected before the fix: G-A and G-B fail with "Tried to modify a provider while the widget tree was building" at `ActivePlanningContextController._setState`. SG8 is the only test that keeps the real providers and the real first-frame timing, so it is the regression test; a synthetic build-race unit test was judged not worth the harness cost.

- [ ] **Step 2: Defer both listener callbacks**

Wrap each callback body in `scheduleMicrotask(() { if (!ref.mounted) return; ... })`, passing the captured `next`. `ref.mounted` is part of `Ref` in riverpod 3.4.3 (the locked version). Do **not** subscribe directly to `songCatalogController` instead: the `autoDispose` rebuild would leave a dead instance subscribed.

- [ ] **Step 3: Adjust the one test that encoded synchronous propagation**

`test/application/providers_test.dart`, "propagates active catalog context changes into the planning context controller": its old assertion encoded the synchronous propagation that 6b deliberately removes, so the test was adjusted. After setting the catalog context it now triggers the listener with an explicit `container.read(activeCatalogContextProvider)` and awaits one microtask before the unchanged `expect`.

- [ ] **Step 4: Verify**

Run: `cd apps/lyron_app && dart format lib test && flutter analyze && flutter test`
Expected: no analyzer issues; the full suite passes, SG8 included; the output contains none of "Tried to modify a provider", "markNeedsBuild", "UnmountedRef", "pending timer".

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/application/planning_providers.dart apps/lyron_app/test/application/providers_test.dart docs/plans/2026-10-05-offline-first-startup-gate.md docs/specs/2026-10-05-offline-first-startup-gate.md
git commit -m "fix(planning): notify planning listeners on a microtask (S0 6b)"
```

---

### Task 7: The router uses the same decision; the acceptance test goes green (SG1, SG8)

**Files:**
- Modify: `apps/lyron_app/lib/src/router/app_router.dart` (two redirect branches)
- Modify: `apps/lyron_app/test/router/app_router_test.dart`
- Modify: `apps/lyron_app/test/integration/offline_first_startup_gate_test.dart` (remove `skip`)

- [ ] **Step 1: Write the failing router test**

Add to `app_router_test.dart`, after the test `'session-expired users stay on a protected route (offline-authenticated)'`:

```dart
  testWidgets(
    'a known organization keeps protected routes open while the live '
    'membership resolution fails (SG1)',
    (WidgetTester tester) async {
      final repository = _TestAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
        ),
      );
      final controller = AppAuthController(repository);
      await controller.restoreSession();
      ActiveMembershipController membership() =>
          ActiveMembershipController(
            currentUserIdReader: () => controller.state.currentUserId,
            knownOrganizationIdReader: () => 'org-1',
          )..update(
            const ActiveOrganizationResolution.unknownConnectivityFailure(),
            userId: 'user-1',
          );

      final router = createAppRouter(
        authController: controller,
        membershipController: membership(),
        refreshListenable: controller,
        initialLocation: AppRoutes.planList.path,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        isolatedSongCatalogProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            appAuthControllerProvider.overrideWith((_) => controller),
            appAuthListenableProvider.overrideWithValue(controller),
            activeMembershipControllerProvider.overrideWith(
              (_) => membership(),
            ),
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: ActiveCatalogContext(
                  userId: 'user-1',
                  organizationId: 'org-1',
                ),
                connectionStatus: CatalogConnectionStatus.offlineCached,
                refreshStatus: CatalogRefreshStatus.idle,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: false,
              ),
            ),
            songLibraryListProvider.overrideWith((ref) async => const []),
            planningPlanListProvider.overrideWith(
              (ref) async => [
                PlanSummary(
                  id: 'plan-1',
                  slug: 'sunday-morning',
                  name: 'Sunday Morning',
                  description: 'Single-session Sunday fixture',
                  scheduledFor: DateTime(2026, 4, 5, 8, 30),
                  updatedAt: DateTime(2026, 3, 31, 8),
                ),
              ],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.planListTitle), findsOneWidget);
    },
  );
```

- [ ] **Step 2: Run and see it fail**

Run: `cd apps/lyron_app && flutter test test/router/app_router_test.dart --plain-name "a known organization keeps protected routes open"`
Expected: FAIL, `Expected: exactly one matching candidate` for the plan list title: the redirect still checks `last is! ActiveOrganizationSelected` and sends the user home.

- [ ] **Step 3: Use the decision in both redirect branches**

In `app_router.dart`, both the `signedIn` and the `sessionExpired` branches contain:

```dart
            membershipController.last is! ActiveOrganizationSelected) {
```

Replace each occurrence with:

```dart
            !membershipController.allowsAuthenticatedRoutes) {
```

Then delete `import 'package:lyron_app/src/application/active_organization_resolution.dart';` from `app_router.dart`: those two lines were its only use, and an unused import fails CI.

- [ ] **Step 4: Run the router tests**

Run: `cd apps/lyron_app && flutter test test/router/app_router_test.dart`
Expected: PASS.

- [ ] **Step 5: Turn on the acceptance test**

Remove both `skip: true, // S0 Task 7 removes this` lines from `test/integration/offline_first_startup_gate_test.dart`.

Run: `cd apps/lyron_app && flutter test test/integration/offline_first_startup_gate_test.dart`
Expected: PASS, both tests. If the song is missing but the gate is open, the catalog's local-first path did not run: check that the identity database override reached `lastKnownIdentityStoreProvider`. Do not add network fakes to make it pass; the point of the test is that it has none.

- [ ] **Step 6: Run the full suite**

Run: `cd apps/lyron_app && flutter test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/lyron_app/lib/src/router/app_router.dart apps/lyron_app/test/router/app_router_test.dart apps/lyron_app/test/integration/offline_first_startup_gate_test.dart
git commit -m "$(cat <<'EOF'
fix(auth): offline cold start no longer waits on the network (S0)

The router redirect reads the same gate decision. With an expired token
on a dead network the cached song list is now the first screen, and a
cold start straight into sessionExpired reaches it with the re-auth
banner (G-A, G-B, SG8).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Handle auth-stream errors (SG5, closes G-E)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart`
- Test: `apps/lyron_app/test/application/auth/app_auth_controller_test.dart`

- [ ] **Step 1: Add an error emitter to the test fake**

In `app_auth_controller_test.dart`, inside `_FakeAuthRepository`, after `void emit(AppAuthSession? session) => _controller.add(session);`:

```dart
  void emitError(Object error) => _controller.addError(error);
```

Add `import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;` to the imports.

- [ ] **Step 2: Write the failing tests**

Append inside `main()`:

```dart
  test('a connectivity error on the auth stream changes nothing and is not '
      'reported (SG5)', () async {
    final repo = _FakeAuthRepository()
      ..currentSession = const AppAuthSession(userId: 'u1', email: 'e@x');
    final controller = AppAuthController(repo);
    await controller.restoreSession();
    final reported = <Object>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => reported.add(details.exception);
    addTearDown(() => FlutterError.onError = originalOnError);

    repo.emitError(AuthRetryableFetchException(message: 'offline'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AppAuthStatus.signedIn);
    expect(reported, isEmpty);
  });

  test('any other auth-stream error is reported once and the stream keeps '
      'working (SG5)', () async {
    final repo = _FakeAuthRepository()
      ..currentSession = const AppAuthSession(userId: 'u1', email: 'e@x');
    final controller = AppAuthController(repo);
    await controller.restoreSession();
    final reported = <Object>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => reported.add(details.exception);
    addTearDown(() => FlutterError.onError = originalOnError);

    repo.emitError(StateError('unexpected'));
    await Future<void>.delayed(Duration.zero);
    expect(reported.single, isA<StateError>());
    expect(controller.state.status, AppAuthStatus.signedIn);

    repo.emit(const AppAuthSession(userId: 'u1', email: 'new@x'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.session?.email, 'new@x');
  });
```

- [ ] **Step 3: Run and see them fail**

Run: `cd apps/lyron_app && flutter test test/application/auth/app_auth_controller_test.dart --plain-name "SG5"`
Expected: both FAIL with an uncaught error from the stream (`AuthRetryableFetchException(message: offline, ...)` and `Bad state: unexpected`), because the subscription has no `onError`.

- [ ] **Step 4: Implement**

In `app_auth_controller.dart`, replace

```dart
    _subscription = _repository.watchSession().listen(_handleSessionUpdate);
```

with

```dart
    _subscription = _repository.watchSession().listen(
      _handleSessionUpdate,
      onError: _handleSessionStreamError,
    );
```

and add this method next to `_handleSessionUpdate`:

```dart
  // SG5 (docs/specs/2026-10-05-offline-first-startup-gate.md): gotrue adds
  // every failed token-refresh loop to the auth stream as an error -- every
  // ~20 s while offline in the foreground. Without this handler each one was
  // an uncaught error, which Sentry records as an unhandled fatal event. A
  // connectivity failure is expected offline and changes nothing; anything
  // else is reported once as a handled error. Auth state never changes here.
  void _handleSessionStreamError(Object error, StackTrace stackTrace) {
    if (isConnectivityFailure(error)) {
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'AppAuthController',
        context: ErrorDescription(
          'the auth session stream reported an error; auth state unchanged',
        ),
      ),
    );
  }
```

Add `import 'package:lyron_app/src/shared/connectivity_failure.dart';`.

- [ ] **Step 5: Run the test file, then the full suite**

Run: `cd apps/lyron_app && flutter test test/application/auth/app_auth_controller_test.dart && flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/application/auth/app_auth_controller.dart apps/lyron_app/test/application/auth/app_auth_controller_test.dart
git commit -m "$(cat <<'EOF'
fix(auth): handle auth-stream errors instead of leaking them (SG5)

gotrue reports every failed offline refresh loop on the auth stream; each
one used to reach Sentry as an unhandled fatal event.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: PR 1 documentation, verification, pull request

**Files:**
- Create: `docs/architecture/decisions/ADR-040-offline-first-startup-gate.md`
- Modify: `docs/architecture/decisions/ADR-016-active-organization-resolution-semantics.md`, `docs/architecture/decisions/ADR-037-local-first-catalog-visibility.md`, `docs/architecture/architecture.md`, `docs/testing/testing-strategy.md`, `docs/specs/2026-06-28-non-destructive-session-and-offline-relaunch.md`, `docs/specs/2026-06-03-offline-membership-gate-cached-fallback.md`, `docs/specs/2026-10-05-offline-first-startup-gate.md`, `docs/plans/2026-10-01-delivery-roadmap.md`

- [ ] **Step 1: Write ADR-040**

```markdown
# ADR-040: Offline-First Startup Gate

**Status:** Accepted (2026-10-05). PR 1 implements SG1–SG5 and SG8; PR 2
implements SG6–SG7.
**Supersedes in part:** ADR-016 — its cached fallback is no longer the
membership gate's offline path.
**Amends:** ADR-037 — its invariant now covers everything the startup path
shows, not only the read contexts.
**Context spec:** `docs/specs/2026-10-05-offline-first-startup-gate.md`

## Context

After PR #79 the catalog and planning contexts were local-first, but the
membership gate in front of them was not. It started as a connectivity
failure and opened only after the `current_organization_ids` RPC answered.
With an expired access token every RPC first waits for gotrue's refresh
retry loop, measured at 10.0–12.4 s offline (up to the 120 s token backstop
on a connection that never answers). A cold start straight into
`sessionExpired` never opened the gate at all, and a single fresh
`verifiedEmpty` hid data that ADR-035 D5 deliberately keeps readable.

## Decision

1. **The gate decides from local state.** `decideMembershipGate` is a pure
   function of the current user's last known organization, the live
   resolution, the pending invite and the first-run timer. A known
   organization opens the gate with no network answer. The router redirect
   evaluates the same decision (`allowsAuthenticatedRoutes`).
2. **`verifiedEmpty` waits for the D5 purge.** With a known organization it
   changes nothing; the purge clears the identity, and a purge handler on
   `VerifiedEmptyMembershipCleanupCoordinator` records `verifiedEmpty` for
   the purged user. A pending invite still shows the redeem screen at once.
3. **Live results are scoped by user.** A failure never replaces a
   `selected` result for the same user; a result for a user who is no
   longer current is dropped; an explicit sign-out forgets it.
4. **First run without a known organization** shows a loading state, and
   the connectivity message with Retry after 15 s.
5. **Auth-stream errors are handled.** Connectivity errors are dropped;
   anything else is reported once as a handled error.
6. **(PR 2)** The last known capabilities are stored on the
   `LastKnownIdentity` row, and the sync surface shows when songs and plans
   last synced.

## Consequences

- A genuinely revoked member keeps seeing cached data until the D5 purge
  runs. Their writes are rejected by RLS. This is the cost ADR-035 already
  accepted; the declined-purge notice is deferred
  (`docs/deferred/2026-10-05-membership-revoked-notice.md`).
- Sync and other network calls still wait for gotrue's refresh loop
  offline; only display stopped waiting
  (`docs/deferred/2026-10-05-offline-token-refresh-churn.md`).
- Every offline startup path keeps at least one test with the real auth
  client (`docs/testing/testing-strategy.md`).
```

- [ ] **Step 2: Status notes on ADR-016 and ADR-037**

In ADR-016, directly under the `## Status` heading's existing text, add:

```markdown
> **2026-10-05:** the membership gate no longer uses the cached fallback as
> its offline path. It decides from the last known identity first; see
> ADR-040. The fallback remains for a user with no known organization.
```

In ADR-037, after the `**Context spec:**` line, add:

```markdown
**Extended by:** ADR-040 (2026-10-05) — the same invariant now covers the
membership gate, the router redirect and capability-gated affordances.
```

- [ ] **Step 3: Correct `architecture.md`**

In `docs/architecture/architecture.md`, replace the sentence

```text
The router keeps offline-authenticated users in the app (membership resolves via the cached organization id) and surfaces a persistent re-auth banner.
```

with

```text
The router keeps offline-authenticated users in the app and surfaces a persistent re-auth banner. The membership gate in front of the home route decides from local state, not from a network answer: a known organization for the current user (the live session's user, or the last known session's user when offline-authenticated) opens it immediately, the router redirect evaluates the same decision, and a network result can only refine it. A fresh `verifiedEmpty` closes the gate only after the D5 purge has run (ADR-040).
```

- [ ] **Step 4: Add the real-auth-client rule to `testing-strategy.md`**

Insert directly before the `### Widget Tests` heading:

```markdown
#### Real auth client rule (offline startup)

A fake that answers instantly does not prove an offline path: the 10–15 s
startup wait fixed by ADR-040 hid behind exactly such fakes for months.
Every offline startup path keeps at least one test that uses the real
`SupabaseClient` and `GoTrueClient` with an expired persisted session
(`test/integration/offline_first_startup_gate_test.dart` is the template).

- Use an HTTP client whose requests never complete. Under widget-test fake
  time gotrue's refresh retry loop measures elapsed time with the real
  `DateTime.now()` while its back-off delays are fake timers, so a failing
  client makes the loop endless and leaves timers pending.
- Teardown: `client.auth.stopAutoRefresh()`, unmount the tree, then close
  the databases. Never call `client.dispose()` inside the test: it completes
  the hung refresh with an error and app code resumes after its providers
  are disposed.
```

- [ ] **Step 5: Correction notes on the two older specs**

Directly under the title of `docs/specs/2026-06-28-non-destructive-session-and-offline-relaunch.md`:

```markdown
> **Correction (2026-10-05):** the claim that the `MembershipGate` resolves
> via the cached organization id in `sessionExpired` was not true for a cold
> start straight into `sessionExpired`: the gate never opened. Fixed by
> `docs/specs/2026-10-05-offline-first-startup-gate.md` (G-B), ADR-040.
```

Directly under the title of `docs/specs/2026-06-03-offline-membership-gate-cached-fallback.md`:

```markdown
> **Superseded in part (2026-10-05):** the cached fallback is no longer the
> gate's offline path; the gate decides from the last known identity first
> (ADR-040).
```

- [ ] **Step 6: Update the spec and the roadmap**

In the spec, change `> Status: Draft (2026-10-05), product decisions confirmed, awaiting plan` to `> Status: PR 1 implemented (SG1–SG5, SG8); PR 2 pending`, and change `**Plan:** ... (not yet written)` to `**Plan:** \`docs/plans/2026-10-05-offline-first-startup-gate.md\``.

In the roadmap status note, replace `Next: S0, then S5a.` with `S0 PR 1 implemented on \`fix/offline-first-startup-gate\`, awaiting merge; then S0 PR 2, then S5a.`

- [ ] **Step 7: Full verification**

Run: `./scripts/verify.sh`
Expected: exit 0. Fix anything it reports (including info-level analyzer lints) before going on.

- [ ] **Step 8: Commit the docs**

```bash
git add docs
git commit -m "$(cat <<'EOF'
docs(auth): ADR-040 offline-first startup gate

Records the gate decision, corrects the architecture doc and two older
specs that claimed the gate resolved offline, and adds the real auth
client rule to the testing strategy.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 9: Push and open PR 1**

```bash
git push -u origin fix/offline-first-startup-gate
gh pr create --base main --title "fix(auth): offline-first startup gate (S0, PR 1)" --body "$(cat <<'EOF'
## Summary
- The membership gate decides from the last known identity, so an offline cold start after a long idle period shows the cached song list immediately instead of waiting 10-15 s for gotrue's refresh loop (G-A).
- A cold start straight into `sessionExpired` now reaches the song list and the re-auth banner (G-B).
- A fresh `verifiedEmpty` closes the gate only after the ADR-035 D5 purge ran (SG2).
- Auth-stream errors are handled instead of reaching Sentry as unhandled fatal events (SG5).
- New acceptance test with the real auth client and a network that never answers (SG8).

Spec: `docs/specs/2026-10-05-offline-first-startup-gate.md` · Plan: `docs/plans/2026-10-05-offline-first-startup-gate.md` · ADR-040

## Test plan
- [ ] `flutter test` (full suite)
- [ ] `./scripts/verify.sh`
- [ ] On a device: idle more than 1 h, airplane mode, cold start: song list appears immediately

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

# Part 2 — PR 2: offline affordances and freshness (SG6, SG7)

Start after PR 1 merges:

```bash
git checkout main && git pull && git checkout -b fix/offline-first-affordances
```

### Task 10: `capabilityCodes` column, schema v3

**Files:**
- Modify: `apps/lyron_app/lib/src/offline/auth/last_known_identity_tables.dart`
- Modify: `apps/lyron_app/lib/src/offline/auth/last_known_identity_database.dart`
- Regenerate: `apps/lyron_app/lib/src/offline/auth/last_known_identity_database.g.dart`
- Test: `apps/lyron_app/test/offline/adversarial/last_known_identity_migration_test.dart`

- [ ] **Step 1: Write the failing migration test**

Append inside `main()` of `last_known_identity_migration_test.dart`:

```dart
  test('an existing v2 identity database gains capabilityCodes on upgrade '
      'and keeps its row and marker intact (SG6)', () async {
    final file = await createRelaunchDbFile('identity-migration-v2-v3');
    LastKnownIdentityDatabase? openDb;
    addTearDown(() async {
      await openDb?.close();
      if (await file.parent.exists()) {
        await file.parent.delete(recursive: true);
      }
    });

    // The exact v2 schema: v1 plus membership_revoked_at.
    final rawDb = sqlite3.sqlite3.open(file.path);
    rawDb.execute('''
        CREATE TABLE "last_known_identity_rows" (
          "row_id" INTEGER NOT NULL,
          "user_id" TEXT NOT NULL,
          "email" TEXT NOT NULL,
          "organization_id" TEXT,
          "updated_at" INTEGER,
          "membership_revoked_at" INTEGER,
          PRIMARY KEY ("row_id")
        );
      ''');
    rawDb.execute('''
        INSERT INTO last_known_identity_rows
          (row_id, user_id, email, organization_id, updated_at,
           membership_revoked_at)
        VALUES (1, 'user-1', 'user-1@example.com', 'org-1', 1700000000,
                1700000500);
      ''');
    rawDb.execute('PRAGMA user_version = 2;');
    rawDb.close();

    final db = LastKnownIdentityDatabase.connect(openRelaunchExecutor(file));
    openDb = db;

    final row = await (db.select(
      db.lastKnownIdentityRows,
    )..where((t) => t.rowId.equals(1))).getSingle();
    expect(row.userId, 'user-1');
    expect(row.organizationId, 'org-1');
    expect(row.membershipRevokedAt, isNotNull);
    expect(row.capabilityCodes, isNull);

    await (db.update(db.lastKnownIdentityRows)
          ..where((t) => t.rowId.equals(1)))
        .write(
          const LastKnownIdentityRowsCompanion(
            capabilityCodes: Value('["canEditSongs"]'),
          ),
        );
    final updated = await (db.select(
      db.lastKnownIdentityRows,
    )..where((t) => t.rowId.equals(1))).getSingle();
    expect(updated.capabilityCodes, '["canEditSongs"]');

    await db.close();
    openDb = null;
  });
```

- [ ] **Step 2: Run and see it fail**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/last_known_identity_migration_test.dart`
Expected: compile error, `The getter 'capabilityCodes' isn't defined for the type 'LastKnownIdentityRow'`.

- [ ] **Step 3: Add the column**

In `last_known_identity_tables.dart`, after `membershipRevokedAt`:

```dart
  // SG6 (docs/specs/2026-10-05-offline-first-startup-gate.md): the last
  // successfully resolved capability codes for exactly this row's
  // (userId, organizationId), as a JSON array of strings. Null means none
  // stored. Living on the identity row means every identity clear
  // (sign-out, D5 purge, different-user wipe) removes it, with no new
  // PurgeTarget.
  TextColumn get capabilityCodes => text().nullable()();
```

- [ ] **Step 4: Bump the schema**

In `last_known_identity_database.dart`, inside `onUpgrade` after the `if (from < 2) { ... }` block:

```dart
      if (from < 3) {
        // SG6: pre-migration rows have no stored capabilities; null is the
        // correct starting state, the same as a freshly written row.
        await m.addColumn(
          lastKnownIdentityRows,
          lastKnownIdentityRows.capabilityCodes,
        );
      }
```

and change `int get schemaVersion => 2;` to `int get schemaVersion => 3;`.

- [ ] **Step 5: Regenerate**

Run: `cd apps/lyron_app && dart run build_runner build --delete-conflicting-outputs`
Expected: `last_known_identity_database.g.dart` changes; no other generated file changes.

- [ ] **Step 6: Run the migration tests, then the full suite**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/last_known_identity_migration_test.dart && flutter test`
Expected: PASS (the existing v1 test runs both upgrade steps).

- [ ] **Step 7: Commit**

```bash
git add apps/lyron_app/lib/src/offline/auth apps/lyron_app/test/offline/adversarial/last_known_identity_migration_test.dart
git commit -m "$(cat <<'EOF'
feat(storage): capabilityCodes column on the identity row (schema v3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: `CapabilitySnapshotStore` on the identity store (SG6)

**Files:**
- Create: `apps/lyron_app/lib/src/application/auth/capability_snapshot_store.dart`
- Modify: `apps/lyron_app/lib/src/offline/auth/drift_last_known_identity_store.dart`
- Test: `apps/lyron_app/test/application/auth/last_known_identity_store_test.dart`

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `last_known_identity_store_test.dart`:

```dart
  group('capability codes (SG6)', () {
    const identity = LastKnownIdentity(
      userId: 'user-1',
      email: 'user-1@example.com',
      organizationId: 'org-1',
    );

    test('are stored and read for the identity row\'s exact user and '
        'organization', () async {
      await store.write(identity);

      final written = await store.writeCapabilityCodes(
        userId: 'user-1',
        organizationId: 'org-1',
        codes: {'canEditSongs', 'canViewSongs'},
      );

      expect(written, isTrue);
      expect(
        await store.readCapabilityCodes(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        {'canEditSongs', 'canViewSongs'},
      );
    });

    test('are never written or read for another user or organization',
        () async {
      await store.write(identity);

      expect(
        await store.writeCapabilityCodes(
          userId: 'user-1',
          organizationId: 'org-2',
          codes: {'canEditSongs'},
        ),
        isFalse,
      );
      expect(
        await store.writeCapabilityCodes(
          userId: 'user-2',
          organizationId: 'org-1',
          codes: {'canEditSongs'},
        ),
        isFalse,
      );
      expect(
        await store.readCapabilityCodes(
          userId: 'user-2',
          organizationId: 'org-1',
        ),
        isNull,
      );
    });

    test('a write after the identity was cleared does not resurrect them',
        () async {
      await store.write(identity);
      await store.writeCapabilityCodes(
        userId: 'user-1',
        organizationId: 'org-1',
        codes: {'canEditSongs'},
      );
      await store.clear();

      expect(
        await store.writeCapabilityCodes(
          userId: 'user-1',
          organizationId: 'org-1',
          codes: {'canEditSongs'},
        ),
        isFalse,
      );
      expect(await store.read(), isNull);
    });

    test('an identity write keeps them only for the same user and '
        'organization', () async {
      await store.write(identity);
      await store.writeCapabilityCodes(
        userId: 'user-1',
        organizationId: 'org-1',
        codes: {'canEditSongs'},
      );

      await store.write(identity);
      expect(
        await store.readCapabilityCodes(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        {'canEditSongs'},
      );

      await store.write(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user-1@example.com',
          organizationId: 'org-2',
        ),
      );
      await store.write(identity);
      expect(
        await store.readCapabilityCodes(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isNull,
      );
    });
  });
```

- [ ] **Step 2: Run and see them fail**

Run: `cd apps/lyron_app && flutter test test/application/auth/last_known_identity_store_test.dart`
Expected: compile error, `The method 'writeCapabilityCodes' isn't defined for the type 'DriftLastKnownIdentityStore'`.

- [ ] **Step 3: Create the interface**

`apps/lyron_app/lib/src/application/auth/capability_snapshot_store.dart`:

```dart
/// SG6 (docs/specs/2026-10-05-offline-first-startup-gate.md): the last known
/// capability codes per (userId, organizationId). UX only -- the backend
/// stays the authority (AGENTS.md rule 5).
///
/// A separate interface from LastKnownIdentityStore on purpose: that one has
/// many hand-written test fakes, and capabilities are an optional concern of
/// the same row.
abstract interface class CapabilitySnapshotStore {
  /// The stored codes, or null when nothing is stored for exactly this pair.
  Future<Set<String>?> readCapabilityCodes({
    required String userId,
    required String organizationId,
  });

  /// Stores [codes] only if the stored identity row still belongs to exactly
  /// ([userId], [organizationId]), in one statement. Returns false and writes
  /// nothing otherwise, so a resolve that finishes after a purge cannot
  /// write the set back.
  Future<bool> writeCapabilityCodes({
    required String userId,
    required String organizationId,
    required Set<String> codes,
  });
}
```

- [ ] **Step 4: Implement it on the Drift store**

In `drift_last_known_identity_store.dart`:

1. Add imports `import 'dart:convert';` and `import 'package:lyron_app/src/application/auth/capability_snapshot_store.dart';`.
2. Change the class header to `class DriftLastKnownIdentityStore implements LastKnownIdentityStore, CapabilitySnapshotStore {`.
3. In `write()`, replace

```dart
      final sameUser = existing != null && existing.userId == identity.userId;
```

with

```dart
      final sameUser = existing != null && existing.userId == identity.userId;
      // SG6: stored capabilities belong to exactly one (userId,
      // organizationId); any other identity starts without them.
      final sameContext =
          sameUser && existing.organizationId == identity.organizationId;
```

and add this argument to the `LastKnownIdentityRowsCompanion.insert(...)` call, after `membershipRevokedAt: ...`:

```dart
              capabilityCodes: sameContext
                  ? const Value.absent()
                  : const Value(null),
```

4. Add the two methods before `_readRow()`:

```dart
  @override
  Future<Set<String>?> readCapabilityCodes({
    required String userId,
    required String organizationId,
  }) async {
    final row = await _readRow();
    if (row == null ||
        row.userId != userId ||
        row.organizationId != organizationId) {
      return null;
    }
    final encoded = row.capabilityCodes;
    if (encoded == null) {
      return null;
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      return null;
    }
    return decoded.whereType<String>().toSet();
  }

  @override
  Future<bool> writeCapabilityCodes({
    required String userId,
    required String organizationId,
    required Set<String> codes,
  }) async {
    final sorted = codes.toList()..sort();
    // One conditional UPDATE: if the row was cleared or now belongs to
    // another user or organization, nothing matches and nothing is written.
    final updated =
        await (_database.update(_database.lastKnownIdentityRows)..where(
              (table) =>
                  table.rowId.equals(1) &
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .write(
              LastKnownIdentityRowsCompanion(
                capabilityCodes: Value(jsonEncode(sorted)),
              ),
            );
    return updated > 0;
  }
```

- [ ] **Step 5: Run the store tests, then the full suite**

Run: `cd apps/lyron_app && flutter test test/application/auth/last_known_identity_store_test.dart && flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/application/auth/capability_snapshot_store.dart apps/lyron_app/lib/src/offline/auth/drift_last_known_identity_store.dart apps/lyron_app/test/application/auth/last_known_identity_store_test.dart
git commit -m "$(cat <<'EOF'
feat(auth): store last known capabilities on the identity row (SG6)

Writes are conditional on the row still naming the same user and
organization, so a resolve after a purge cannot resurrect them.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: `CapabilityResolver` answers from the store first (SG6)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth/capability_resolver.dart`
- Test: `apps/lyron_app/test/application/auth/capability_resolver_test.dart`

- [ ] **Step 1: Write the failing tests**

Add these fakes above `void main()` in `capability_resolver_test.dart` (plus `import 'dart:async';` and `import 'package:lyron_app/src/application/auth/capability_snapshot_store.dart';`):

```dart
class _FakeSnapshotStore implements CapabilitySnapshotStore {
  final Map<String, Set<String>> rows = {};
  int writes = 0;

  static String _key(String userId, String organizationId) =>
      '$userId|$organizationId';

  @override
  Future<Set<String>?> readCapabilityCodes({
    required String userId,
    required String organizationId,
  }) async => rows[_key(userId, organizationId)];

  @override
  Future<bool> writeCapabilityCodes({
    required String userId,
    required String organizationId,
    required Set<String> codes,
  }) async {
    writes += 1;
    rows[_key(userId, organizationId)] = codes;
    return true;
  }
}

class _ScriptedGateway implements CapabilityGateway {
  _ScriptedGateway(this.answer);

  Future<Set<Capability>> Function() answer;
  int calls = 0;

  @override
  Future<Set<Capability>> resolve(String organizationId) {
    calls += 1;
    return answer();
  }
}
```

Append inside `main()`:

```dart
  group('stored capabilities (SG6)', () {
    test('answer before the network does', () async {
      final store = _FakeSnapshotStore()
        ..rows['user-1|org-1'] = {'canEditSongs'};
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(
          () => Completer<Set<Capability>>().future,
        ),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );

      final capabilities = await resolver.capabilitiesFor('org-1');

      expect(capabilities, {Capability.editSongs});
      expect(
        resolver.hasCapabilitySync('org-1', Capability.editSongs),
        isTrue,
      );
    });

    test('a failed refresh keeps the stored set', () async {
      final store = _FakeSnapshotStore()
        ..rows['user-1|org-1'] = {'canEditSongs'};
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(() async => throw StateError('offline')),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );

      await resolver.capabilitiesFor('org-1');
      await pumpEventQueue();

      expect(store.rows['user-1|org-1'], {'canEditSongs'});
      expect(
        resolver.hasCapabilitySync('org-1', Capability.editSongs),
        isTrue,
      );
    });

    test('a successful refresh replaces, persists and notifies', () async {
      final store = _FakeSnapshotStore()
        ..rows['user-1|org-1'] = {'canEditSongs'};
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(() async => {Capability.viewSongs}),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );
      var notifications = 0;
      resolver.addListener(() => notifications++);

      await resolver.capabilitiesFor('org-1');
      await pumpEventQueue();

      expect(
        resolver.hasCapabilitySync('org-1', Capability.editSongs),
        isFalse,
      );
      expect(
        resolver.hasCapabilitySync('org-1', Capability.viewSongs),
        isTrue,
      );
      expect(store.rows['user-1|org-1'], {'canViewSongs'});
      expect(notifications, 1);
    });

    test('with nothing stored the network answer is persisted', () async {
      final store = _FakeSnapshotStore();
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(() async => {Capability.viewSongs}),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );

      expect(await resolver.capabilitiesFor('org-1'), {Capability.viewSongs});
      expect(store.rows['user-1|org-1'], {'canViewSongs'});
    });

    test('another user\'s stored set is never applied', () async {
      final store = _FakeSnapshotStore()
        ..rows['user-1|org-1'] = {'canEditSongs'};
      final gateway = _ScriptedGateway(() async => {Capability.viewSongs});
      final resolver = CapabilityResolver(
        gateway: gateway,
        snapshotStore: store,
        readUserId: () => 'user-2',
      );

      expect(await resolver.capabilitiesFor('org-1'), {Capability.viewSongs});
      expect(gateway.calls, 1);
    });

    test('invalidate re-reads the store instead of deleting it', () async {
      final store = _FakeSnapshotStore()
        ..rows['user-1|org-1'] = {'canEditSongs'};
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(
          () => Completer<Set<Capability>>().future,
        ),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );
      await resolver.capabilitiesFor('org-1');

      resolver.invalidate();

      expect(await resolver.capabilitiesFor('org-1'), {Capability.editSongs});
      expect(store.rows['user-1|org-1'], {'canEditSongs'});
    });
  });
```

- [ ] **Step 2: Run and see them fail**

Run: `cd apps/lyron_app && flutter test test/application/auth/capability_resolver_test.dart`
Expected: compile error, `The named parameter 'snapshotStore' isn't defined`.

- [ ] **Step 3: Implement (replace the `CapabilityResolver` class; keep `CapabilityGateway` and `SupabaseCapabilityGateway` unchanged)**

Add imports `import 'dart:async';` and `import 'capability_snapshot_store.dart';` at the top of `capability_resolver.dart`, then:

```dart
class CapabilityResolver extends ChangeNotifier {
  CapabilityResolver({
    required this._gateway,
    CapabilitySnapshotStore? snapshotStore,
    String? Function()? readUserId,
  }) : _snapshotStore = snapshotStore,
       _readUserId = readUserId ?? _nobody;

  static String? _nobody() => null;

  final CapabilityGateway _gateway;
  // SG6 (docs/specs/2026-10-05-offline-first-startup-gate.md): the last
  // known capabilities, so gated affordances answer offline from the local
  // store instead of after the network fails.
  final CapabilitySnapshotStore? _snapshotStore;
  final String? Function() _readUserId;

  final Map<String, Future<Set<Capability>>> _cache = {};

  final Map<String, Set<Capability>> _resolved = {};

  int _version = 0;
  int get version => _version;

  bool _disposed = false;

  Future<Set<Capability>> capabilitiesFor(String organizationId) {
    final capturedVersion = _version;
    return _cache.putIfAbsent(
      organizationId,
      () => _load(organizationId, capturedVersion),
    );
  }

  Future<Set<Capability>> _load(
    String organizationId,
    int capturedVersion,
  ) async {
    final userId = _readUserId();
    final stored = await _readStored(userId, organizationId);
    if (stored != null) {
      if (_version == capturedVersion) {
        _resolved[organizationId] = stored;
      }
      unawaited(
        _refreshInBackground(organizationId, userId, capturedVersion, stored),
      );
      return stored;
    }
    try {
      final resolved = await _gateway.resolve(organizationId);
      if (_version == capturedVersion) {
        _resolved[organizationId] = resolved;
      }
      await _persist(userId, organizationId, resolved);
      return resolved;
    } catch (error, stackTrace) {
      if (_version == capturedVersion) {
        _cache.remove(organizationId);
      }
      debugPrint(
        'CapabilityResolver: failed to resolve capabilities '
        'for $organizationId: $error\n$stackTrace',
      );
      rethrow;
    }
  }

  Future<void> _refreshInBackground(
    String organizationId,
    String? userId,
    int capturedVersion,
    Set<Capability> stored,
  ) async {
    try {
      final resolved = await _gateway.resolve(organizationId);
      if (_version != capturedVersion) {
        return;
      }
      _resolved[organizationId] = resolved;
      _cache[organizationId] = Future.value(resolved);
      await _persist(userId, organizationId, resolved);
      if (!setEquals(resolved, stored) && !_disposed) {
        notifyListeners();
      }
    } catch (error) {
      // SG6: a failed resolve keeps the stored set.
      debugPrint(
        'CapabilityResolver: background refresh failed for '
        '$organizationId; keeping the stored capabilities: $error',
      );
    }
  }

  Future<Set<Capability>?> _readStored(
    String? userId,
    String organizationId,
  ) async {
    final store = _snapshotStore;
    if (store == null || userId == null) {
      return null;
    }
    try {
      final codes = await store.readCapabilityCodes(
        userId: userId,
        organizationId: organizationId,
      );
      if (codes == null) {
        return null;
      }
      return Capability.values.where((c) => codes.contains(c.code)).toSet();
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(
    String? userId,
    String organizationId,
    Set<Capability> capabilities,
  ) async {
    final store = _snapshotStore;
    if (store == null || userId == null) {
      return;
    }
    try {
      await store.writeCapabilityCodes(
        userId: userId,
        organizationId: organizationId,
        codes: {for (final capability in capabilities) capability.code},
      );
    } catch (error) {
      debugPrint('CapabilityResolver: could not store capabilities: $error');
    }
  }

  bool? hasCapabilitySync(String organizationId, Capability capability) =>
      _resolved[organizationId]?.contains(capability);

  Future<bool> hasCapability(
    String organizationId,
    Capability capability,
  ) async {
    final set = await capabilitiesFor(organizationId);
    return set.contains(capability);
  }

  void invalidate() {
    _cache.clear();
    _resolved.clear();
    _version++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
```

- [ ] **Step 4: Run the resolver tests, then the full suite**

Run: `cd apps/lyron_app && flutter test test/application/auth/capability_resolver_test.dart && flutter test`
Expected: PASS, including the three existing resolver tests.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/application/auth/capability_resolver.dart apps/lyron_app/test/application/auth/capability_resolver_test.dart
git commit -m "$(cat <<'EOF'
feat(auth): capabilities answer from the last known set first (SG6)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Wire the capability store; gated affordances offline (SG6)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth_providers.dart`
- Test (new): `apps/lyron_app/test/presentation/shared/if_capability_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/capability_resolver.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';
import 'package:lyron_app/src/presentation/shared/if_capability.dart';

class _HangingGateway implements CapabilityGateway {
  @override
  Future<Set<Capability>> resolve(String organizationId) =>
      Completer<Set<Capability>>().future;
}

void main() {
  testWidgets('a stored capability shows the affordance with no network '
      'answer (SG6)', (tester) async {
    final database = LastKnownIdentityDatabase.inMemory();
    final store = DriftLastKnownIdentityStore(database);
    await tester.runAsync(() async {
      await store.write(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user-1@example.com',
          organizationId: 'org-1',
        ),
      );
      await store.writeCapabilityCodes(
        userId: 'user-1',
        organizationId: 'org-1',
        codes: {Capability.editSongs.code},
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          capabilityResolverProvider.overrideWith(
            (_) => CapabilityResolver(
              gateway: _HangingGateway(),
              snapshotStore: store,
              readUserId: () => 'user-1',
            ),
          ),
        ],
        child: const MaterialApp(
          home: IfCapability(
            capability: Capability.editSongs,
            organizationId: 'org-1',
            child: Text('edit'),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.text('edit'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
  });
}
```

- [ ] **Step 2: Run it**

Run: `cd apps/lyron_app && flutter test test/presentation/shared/if_capability_test.dart`
Expected: PASS already (Task 12 implemented the resolver). This test pins the widget-level behaviour; the red step for this task is Step 3.

- [ ] **Step 3: Write the failing provider test**

Append to `apps/lyron_app/test/application/auth/membership_gate_wiring_test.dart` (it already has the harness):

```dart
  test('the capability resolver reads and writes the identity database '
      '(SG6)', () async {
    final harness = await _harness(
      session: _session,
      identity: const LastKnownIdentity(
        userId: 'user-1',
        email: 'demo@lyron.local',
        organizationId: 'org-1',
      ),
      resolution: _never,
    );

    final store = harness.container.read(capabilitySnapshotStoreProvider);

    expect(store, isA<DriftLastKnownIdentityStore>());
  });
```

Run: `cd apps/lyron_app && flutter test test/application/auth/membership_gate_wiring_test.dart`
Expected: compile error, `Undefined name 'capabilitySnapshotStoreProvider'`.

- [ ] **Step 4: Implement the providers**

In `auth_providers.dart`, add `import 'package:lyron_app/src/application/auth/capability_snapshot_store.dart';` and, after `lastKnownIdentityStoreProvider`:

```dart
/// SG6: the last known capabilities live on the identity row, so every
/// identity clear removes them with no new purge target.
final capabilitySnapshotStoreProvider = Provider<CapabilitySnapshotStore>((
  ref,
) {
  return DriftLastKnownIdentityStore(
    ref.watch(lastKnownIdentityDatabaseProvider),
  );
});
```

In `capabilityResolverProvider`, replace

```dart
  final resolver = CapabilityResolver(
    gateway: SupabaseCapabilityGateway(client),
  );
```

with

```dart
  final resolver = CapabilityResolver(
    gateway: SupabaseCapabilityGateway(client),
    snapshotStore: ref.watch(capabilitySnapshotStoreProvider),
    readUserId: () => ref.read(appAuthControllerProvider).state.currentUserId,
  );
```

- [ ] **Step 5: Run the wiring test, then the full suite**

Run: `cd apps/lyron_app && flutter test test/application/auth/membership_gate_wiring_test.dart && flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/application/auth_providers.dart apps/lyron_app/test/presentation/shared/if_capability_test.dart apps/lyron_app/test/application/auth/membership_gate_wiring_test.dart
git commit -m "$(cat <<'EOF'
feat(auth): gated affordances work offline from the last known role

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Last-synced reader and formatter (SG7)

**Files:**
- Create: `apps/lyron_app/lib/src/application/sync/sync_freshness_reader.dart`
- Create: `apps/lyron_app/lib/src/presentation/sync/last_synced_format.dart`
- Modify: `apps/lyron_app/lib/src/application/core_providers.dart`, `apps/lyron_app/lib/src/shared/app_strings.dart`
- Test (new): `apps/lyron_app/test/application/sync/sync_freshness_reader_test.dart`, `apps/lyron_app/test/presentation/sync/last_synced_format_test.dart`

- [ ] **Step 1: Write the failing tests**

`test/application/sync/sync_freshness_reader_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/sync/sync_freshness_reader.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test('reads the persisted refresh times for one user and organization '
      '(SG7)', () async {
    final songs = SongCatalogDatabase.inMemory();
    final plans = PlanningLocalDatabase.inMemory();
    addTearDown(songs.close);
    addTearDown(plans.close);
    await DriftSongCatalogStore(songs).replaceActiveSnapshot(
      userId: 'user-1',
      organizationId: 'org-1',
      summaries: const [SongSummary(id: 'song-1', title: 'Song')],
      sources: const [SongSource(id: 'song-1', source: '{title: Song}')],
      refreshedAt: DateTime.utc(2026, 10, 1, 8),
    );
    await plans
        .into(plans.planningProjectionOwners)
        .insert(
          PlanningProjectionOwnersCompanion.insert(
            userId: 'user-1',
            organizationId: 'org-1',
            snapshotVersion: 1,
            refreshedAt: DateTime.utc(2026, 10, 2, 9),
          ),
        );
    final reader = SyncFreshnessReader(
      songCatalogDatabase: songs,
      planningLocalDatabase: plans,
    );

    final freshness = await reader.read(
      userId: 'user-1',
      organizationId: 'org-1',
    );
    final other = await reader.read(userId: 'user-2', organizationId: 'org-1');

    expect(freshness.songsRefreshedAt?.toUtc(), DateTime.utc(2026, 10, 1, 8));
    expect(freshness.plansRefreshedAt?.toUtc(), DateTime.utc(2026, 10, 2, 9));
    expect(other, const SyncFreshness.unknown());
  });
}
```

`test/presentation/sync/last_synced_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/sync/last_synced_format.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  final now = DateTime(2026, 10, 5, 12);

  test('formats a last-synced time relative to now (SG7)', () {
    expect(
      formatLastSynced(null, now: now),
      AppStrings.unifiedSyncLastSyncedNever,
    );
    expect(
      formatLastSynced(now.subtract(const Duration(seconds: 30)), now: now),
      AppStrings.unifiedSyncLastSyncedJustNow,
    );
    expect(
      formatLastSynced(now.subtract(const Duration(minutes: 5)), now: now),
      AppStrings.unifiedSyncLastSyncedMinutesAgo(5),
    );
    expect(
      formatLastSynced(now.subtract(const Duration(hours: 3)), now: now),
      AppStrings.unifiedSyncLastSyncedHoursAgo(3),
    );
    expect(
      formatLastSynced(now.subtract(const Duration(days: 2)), now: now),
      AppStrings.unifiedSyncLastSyncedDaysAgo(2),
    );
  });

  test('a time in the future (clock moved back) reads as just now', () {
    expect(
      formatLastSynced(now.add(const Duration(hours: 1)), now: now),
      AppStrings.unifiedSyncLastSyncedJustNow,
    );
  });

  test('one day reads in the singular', () {
    expect(AppStrings.unifiedSyncLastSyncedDaysAgo(1), '1 day ago');
  });
}
```

- [ ] **Step 2: Run and see them fail**

Run: `cd apps/lyron_app && flutter test test/application/sync/sync_freshness_reader_test.dart test/presentation/sync/last_synced_format_test.dart`
Expected: compile errors, missing `sync_freshness_reader.dart` and `last_synced_format.dart`.

- [ ] **Step 3: Add the strings**

In `app_strings.dart`, after the `unifiedSyncFreshness*` constants:

```dart
  static const unifiedSyncLastSyncedSongsLabel = 'Songs last synced';
  static const unifiedSyncLastSyncedPlansLabel = 'Plans last synced';
  static const unifiedSyncLastSyncedNever = 'never';
  static const unifiedSyncLastSyncedJustNow = 'just now';
  static String unifiedSyncLastSyncedMinutesAgo(int minutes) =>
      '$minutes min ago';
  static String unifiedSyncLastSyncedHoursAgo(int hours) => '$hours h ago';
  static String unifiedSyncLastSyncedDaysAgo(int days) =>
      days == 1 ? '1 day ago' : '$days days ago';
```

- [ ] **Step 4: Create the reader**

`apps/lyron_app/lib/src/application/sync/sync_freshness_reader.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

/// When songs and plans last refreshed successfully for one
/// (userId, organizationId). SG7 (docs/specs/2026-10-05-offline-first
/// -startup-gate.md). Device wall-clock values: for display only, never
/// compared or ordered (ADR-030).
class SyncFreshness {
  const SyncFreshness({
    required this.songsRefreshedAt,
    required this.plansRefreshedAt,
  });

  const SyncFreshness.unknown()
    : songsRefreshedAt = null,
      plansRefreshedAt = null;

  final DateTime? songsRefreshedAt;
  final DateTime? plansRefreshedAt;

  @override
  bool operator ==(Object other) =>
      other is SyncFreshness &&
      other.songsRefreshedAt == songsRefreshedAt &&
      other.plansRefreshedAt == plansRefreshedAt;

  @override
  int get hashCode => Object.hash(songsRefreshedAt, plansRefreshedAt);
}

/// Reads the persisted refresh times straight from the two databases, like
/// the storage accountants do. A separate class rather than new store
/// methods: SongCatalogStore and PlanningLocalStore have many hand-written
/// test fakes.
class SyncFreshnessReader {
  const SyncFreshnessReader({
    required this._songCatalogDatabase,
    required this._planningLocalDatabase,
  });

  final SongCatalogDatabase _songCatalogDatabase;
  final PlanningLocalDatabase _planningLocalDatabase;

  Future<SyncFreshness> read({
    required String userId,
    required String organizationId,
  }) async {
    final snapshot =
        await (_songCatalogDatabase.select(
                _songCatalogDatabase.cachedCatalogSnapshots,
              )
              ..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
            .getSingleOrNull();
    final owner =
        await (_planningLocalDatabase.select(
                _planningLocalDatabase.planningProjectionOwners,
              )
              ..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
            .getSingleOrNull();
    return SyncFreshness(
      songsRefreshedAt: snapshot?.refreshedAt,
      plansRefreshedAt: owner?.refreshedAt,
    );
  }
}
```

- [ ] **Step 5: Create the formatter**

`apps/lyron_app/lib/src/presentation/sync/last_synced_format.dart`:

```dart
import 'package:lyron_app/src/shared/app_strings.dart';

/// SG7: relative "last synced" copy. [at] is a device wall-clock value used
/// for display only (ADR-030); a time after [now] reads as "just now".
String formatLastSynced(DateTime? at, {required DateTime now}) {
  if (at == null) {
    return AppStrings.unifiedSyncLastSyncedNever;
  }
  final elapsed = now.difference(at);
  if (elapsed.inMinutes < 1) {
    return AppStrings.unifiedSyncLastSyncedJustNow;
  }
  if (elapsed.inHours < 1) {
    return AppStrings.unifiedSyncLastSyncedMinutesAgo(elapsed.inMinutes);
  }
  if (elapsed.inDays < 1) {
    return AppStrings.unifiedSyncLastSyncedHoursAgo(elapsed.inHours);
  }
  return AppStrings.unifiedSyncLastSyncedDaysAgo(elapsed.inDays);
}
```

- [ ] **Step 6: Add the reader provider**

In `core_providers.dart`, add `import 'package:lyron_app/src/application/sync/sync_freshness_reader.dart';` and, after `localStorageMonitorProvider`:

```dart
final syncFreshnessReaderProvider = Provider<SyncFreshnessReader>((ref) {
  return SyncFreshnessReader(
    songCatalogDatabase: ref.watch(songCatalogDatabaseProvider),
    planningLocalDatabase: ref.watch(planningLocalDatabaseProvider),
  );
});
```

- [ ] **Step 7: Run the two test files, then the full suite**

Run: `cd apps/lyron_app && flutter test test/application/sync/sync_freshness_reader_test.dart test/presentation/sync/last_synced_format_test.dart && flutter test`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add apps/lyron_app/lib/src/application/sync/sync_freshness_reader.dart apps/lyron_app/lib/src/presentation/sync/last_synced_format.dart apps/lyron_app/lib/src/application/core_providers.dart apps/lyron_app/lib/src/shared/app_strings.dart apps/lyron_app/test/application/sync/sync_freshness_reader_test.dart apps/lyron_app/test/presentation/sync/last_synced_format_test.dart
git commit -m "$(cat <<'EOF'
feat(sync): read and format last successful refresh times (SG7)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: The sync popup shows when songs and plans last synced (SG7)

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/sync/unified_sync_providers.dart`
- Modify: `apps/lyron_app/lib/src/presentation/sync/unified_sync_status_popup.dart`
- Test: `apps/lyron_app/test/presentation/sync/unified_sync_status_popup_test.dart`

- [ ] **Step 1: Override the new provider in every existing popup test scope**

In `unified_sync_status_popup_test.dart`, add `import 'package:lyron_app/src/application/sync/sync_freshness_reader.dart';`. Then add this entry to the `overrides:` list of **every** `ProviderScope(` in the file (search for `ProviderScope(`; `_pumpPopup` included):

```dart
        syncFreshnessProvider.overrideWith(
          (ref) async => const SyncFreshness.unknown(),
        ),
```

The popup tests otherwise build no real providers, and this keeps them that way.

- [ ] **Step 2: Write the failing test**

Append inside `main()`:

```dart
  testWidgets('shows when songs and plans last synced (SG7)', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(_overview()),
          syncFreshnessProvider.overrideWith(
            (ref) async => SyncFreshness(
              songsRefreshedAt: now.subtract(const Duration(minutes: 5)),
              plansRefreshedAt: null,
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: UnifiedSyncStatusPopup())),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        '${AppStrings.unifiedSyncLastSyncedSongsLabel}: '
        '${AppStrings.unifiedSyncLastSyncedMinutesAgo(5)}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '${AppStrings.unifiedSyncLastSyncedPlansLabel}: '
        '${AppStrings.unifiedSyncLastSyncedNever}',
      ),
      findsOneWidget,
    );
  });
```

- [ ] **Step 3: Run and see it fail**

Run: `cd apps/lyron_app && flutter test test/presentation/sync/unified_sync_status_popup_test.dart`
Expected: compile error, `Undefined name 'syncFreshnessProvider'`.

- [ ] **Step 4: Add the provider**

In `unified_sync_providers.dart`, add `import 'package:lyron_app/src/application/sync/sync_freshness_reader.dart';` and, after `localStorageFootprintProvider`:

```dart
/// SG7: last successful refresh times for the active context, re-read
/// whenever catalog or planning state changes. Any failure, including a
/// provider graph that cannot be built in a narrow widget test, degrades to
/// unknown instead of an error.
final syncFreshnessProvider = FutureProvider.autoDispose<SyncFreshness>((
  ref,
) async {
  try {
    ref.watch(catalogSnapshotStateProvider);
    ref.watch(planningSyncStateProvider);
    final context = ref.watch(activeCatalogContextProvider);
    if (context == null) {
      return const SyncFreshness.unknown();
    }
    return await ref
        .watch(syncFreshnessReaderProvider)
        .read(userId: context.userId, organizationId: context.organizationId);
  } catch (_) {
    return const SyncFreshness.unknown();
  }
}, retry: noAutomaticProviderRetry);
```

- [ ] **Step 5: Render it in the popup**

In `unified_sync_status_popup.dart`, add imports `import 'package:lyron_app/src/application/sync/sync_freshness_reader.dart';` and `import 'package:lyron_app/src/presentation/sync/last_synced_format.dart';`. In `UnifiedSyncStatusPopup.build`, replace

```dart
              const SizedBox(height: 12),
              Expanded(child: _PopupBody(overview: overview)),
```

with

```dart
              const SizedBox(height: 8),
              const _LastSyncedSummary(),
              const SizedBox(height: 12),
              Expanded(child: _PopupBody(overview: overview)),
```

and add this widget at the end of the file:

```dart
/// SG7: when songs and plans last synced, so offline data is never shown as
/// if it were current.
class _LastSyncedSummary extends ConsumerWidget {
  const _LastSyncedSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final freshness =
        ref.watch(syncFreshnessProvider).value ??
        const SyncFreshness.unknown();
    final now = DateTime.now();
    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${AppStrings.unifiedSyncLastSyncedSongsLabel}: '
          '${formatLastSynced(freshness.songsRefreshedAt, now: now)}',
          key: const ValueKey('unified-sync-last-synced-songs'),
          style: style,
        ),
        Text(
          '${AppStrings.unifiedSyncLastSyncedPlansLabel}: '
          '${formatLastSynced(freshness.plansRefreshedAt, now: now)}',
          key: const ValueKey('unified-sync-last-synced-plans'),
          style: style,
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Run the popup tests, then the full suite**

Run: `cd apps/lyron_app && flutter test test/presentation/sync/unified_sync_status_popup_test.dart && flutter test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/sync apps/lyron_app/test/presentation/sync/unified_sync_status_popup_test.dart
git commit -m "$(cat <<'EOF'
feat(sync): show when songs and plans last synced (SG7)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: The header shows non-fresh data without opening the popup (SG7)

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/sync/unified_sync_header_control.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Test: `apps/lyron_app/test/presentation/sync/unified_sync_header_control_test.dart`

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `unified_sync_header_control_test.dart`:

```dart
  testWidgets('offline-cached or stale data draws a hollow dot (SG7)', (
    tester,
  ) async {
    await _pump(
      tester,
      _overview(
        UnifiedSyncHeaderStatus.synced,
        freshness: UnifiedSyncFreshness.offlineCached,
      ),
    );
    expect(
      find.byKey(const ValueKey('unified-sync-header-dot-hollow')),
      findsOneWidget,
    );

    await _pump(
      tester,
      _overview(
        UnifiedSyncHeaderStatus.synced,
        freshness: UnifiedSyncFreshness.stale,
      ),
    );
    expect(
      find.byKey(const ValueKey('unified-sync-header-dot-hollow')),
      findsOneWidget,
    );
  });

  testWidgets('fresh data draws a filled dot', (tester) async {
    await _pump(tester, _overview(UnifiedSyncHeaderStatus.synced));
    expect(
      find.byKey(const ValueKey('unified-sync-header-dot-filled')),
      findsOneWidget,
    );
  });

  test('freshness copy is human-readable, not an identifier (SG7)', () {
    for (final copy in [
      AppStrings.unifiedSyncFreshnessStale,
      AppStrings.unifiedSyncFreshnessOfflineCached,
    ]) {
      expect(copy, isNot(contains('_')));
      expect(copy, contains(' '));
    }
  });
```

- [ ] **Step 2: Run and see them fail**

Run: `cd apps/lyron_app && flutter test test/presentation/sync/unified_sync_header_control_test.dart`
Expected: the two widget tests fail (`Expected: exactly one matching candidate` for the dot keys) and the copy test fails (`'stale'` contains no space; `'offline_cached'` contains `_`).

- [ ] **Step 3: Human-readable freshness copy**

In `app_strings.dart`, change

```dart
  static const unifiedSyncFreshnessStale = 'stale';
  static const unifiedSyncFreshnessOfflineCached = 'offline_cached';
```

to

```dart
  static const unifiedSyncFreshnessStale = 'Not up to date';
  static const unifiedSyncFreshnessOfflineCached =
      'Offline, showing saved data';
```

Run `grep -rn "unifiedSyncFreshnessStale\|unifiedSyncFreshnessOfflineCached" apps/lyron_app/lib apps/lyron_app/test` and confirm every use reads the constant (none compares against the old literal).

- [ ] **Step 4: Hollow dot when not fresh**

In `unified_sync_header_control.dart`, inside `_UnifiedSyncHeaderControlBody.build`, after `final tooltip = ...;` add:

```dart
    // SG7: offline-cached or stale data must be visible without opening the
    // popup. The pending-work colour keeps its meaning; the dot turns hollow.
    final notFresh =
        overview.freshness == UnifiedSyncFreshness.stale ||
        overview.freshness == UnifiedSyncFreshness.offlineCached;
```

and replace

```dart
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
```

with

```dart
          child: Container(
            key: ValueKey(
              notFresh
                  ? 'unified-sync-header-dot-hollow'
                  : 'unified-sync-header-dot-filled',
            ),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: notFresh ? Colors.transparent : color,
              shape: BoxShape.circle,
              border: notFresh ? Border.all(color: color, width: 2) : null,
            ),
          ),
```

The tooltip (already carrying the freshness copy) remains the accessible label.

- [ ] **Step 5: Run the header tests, then the full suite**

Run: `cd apps/lyron_app && flutter test test/presentation/sync/unified_sync_header_control_test.dart && flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/sync/unified_sync_header_control.dart apps/lyron_app/lib/src/shared/app_strings.dart apps/lyron_app/test/presentation/sync/unified_sync_header_control_test.dart
git commit -m "$(cat <<'EOF'
feat(sync): header marks offline or stale data (SG7)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: PR 2 documentation, verification, pull request

**Files:**
- Modify: `docs/architecture/architecture.md`, `docs/architecture/decisions/ADR-040-offline-first-startup-gate.md`, `docs/deferred/2026-09-30-capability-gating-offline-cold-start.md`, `docs/specs/2026-10-05-offline-first-startup-gate.md`, `docs/plans/2026-10-01-delivery-roadmap.md`

- [ ] **Step 1: Architecture authorization section**

In `docs/architecture/architecture.md`, after the line `Authorization is backend-enforced. The Flutter client consumes capability results only for UX affordances.`, add:

```markdown
The client keeps the last successfully resolved capability set for the current `(userId, organizationId)` on the `LastKnownIdentity` row and answers gated affordances from it first, refreshing from the backend in the background. A failed refresh keeps the stored set; any identity clear (sign-out, D5 purge, different-user wipe) removes it; a resolve that finishes after a purge cannot write it back. A stale set can be wrong in either direction, which is acceptable only because the backend stays the authority (ADR-040).
```

- [ ] **Step 2: ADR-040 status**

Change the ADR-040 status line to `**Status:** Accepted (2026-10-05). Implemented: PR 1 (SG1–SG5, SG8) and PR 2 (SG6–SG7).`

- [ ] **Step 3: Narrow the capability deferred entry to option (b)**

In `docs/deferred/2026-09-30-capability-gating-offline-cold-start.md`:

- under `## Options`, replace the body of `### (a) Persist resolved capabilities per user and organization` with `Implemented by S0 PR 2 (ADR-040, spec SG6). Kept here only as history.`;
- in `## Requirements for the slice that picks this up`, remove the four red-test bullets that belong to option (a) and the "Choose (a), (b), or both" bullet;
- replace the `**Update (2026-10-05):**` paragraph with `**Update (2026-10-05):** option (a) shipped in S0 PR 2. S6 picks up option (b) only.`

- [ ] **Step 4: Spec and roadmap status**

In the spec, set `> Status: Implemented (PR 1 and PR 2)`. In the roadmap status note, replace the S0 sentence with `S0 implemented (PR 1 and PR 2). Next: S5a.`, and change the S0 row's scope cell to start with `**Implemented.**`.

- [ ] **Step 5: Full verification**

Run: `./scripts/verify.sh`
Expected: exit 0.

- [ ] **Step 6: Commit, push, open PR 2**

```bash
git add docs
git commit -m "$(cat <<'EOF'
docs(auth): capabilities and freshness for ADR-040 (S0 PR 2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git push -u origin fix/offline-first-affordances
gh pr create --base main --title "feat(auth): offline affordances and last-synced indicator (S0, PR 2)" --body "$(cat <<'EOF'
## Summary
- Capability-gated affordances answer from the last known capabilities, stored on the identity row (schema v3), so offline editors keep their buttons after a cold start (SG6, S6 option (a) pulled forward).
- The sync popup shows when songs and plans last synced; the header marks offline or stale data with a hollow dot and readable copy (SG7).

Spec: `docs/specs/2026-10-05-offline-first-startup-gate.md` · Plan: `docs/plans/2026-10-05-offline-first-startup-gate.md` · ADR-040

## Test plan
- [ ] `flutter test` (full suite)
- [ ] `./scripts/verify.sh`
- [ ] On a device: sign in online, go offline, cold start: "Add song" appears without waiting; the header dot is hollow; the popup shows both last-synced times

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Spec coverage check

| Spec item | Task |
|---|---|
| SG1 decision from last known identity; router uses it | 3, 4, 5, 6, 7 |
| SG2 verifiedEmpty waits for the purge; purge handler; invite exception | 3, 5 (purge test) |
| SG3 user-scoped live result, failures keep selected, sign-out reset | 4, 5 |
| SG4 loading state, 15 s timer | 3, 4, 6 |
| SG5 auth-stream onError | 8 |
| SG6 persisted capabilities | 10, 11, 12, 13 |
| SG7 last-synced indicator, hollow dot, readable copy | 14, 15, 16 |
| SG8 real auth client test + testing-strategy rule | 1, 7, 9 |
| G-B sessionExpired cold start | 1, 5, 7 |
| G-C no failure flash online | 4, 5, 6 |
| Docs (ADR-040, ADR-016/037, architecture, testing strategy, older specs, deferred, roadmap) | 9, 17 |
