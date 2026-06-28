# Non-Destructive Session Expiry & Offline Relaunch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple local data access from live auth-session validity so a previously signed-in user keeps reading cached songs/plans and keeps editing (writes queue) when the session is not live — both for in-session expiry and offline cold-start relaunch — wiping only on explicit sign-out or authoritative revocation.

**Architecture:** Treat `AppAuthStatus.sessionExpired` as a first-class "offline-authenticated / re-auth-required" state. Persist a durable `LastKnownIdentity` (own Drift record) so cold start knows which user to load. Make planning's `handleSessionExpired` non-destructive (mirroring catalog). Keep the user in the app (router no longer bounces to sign-in) with a re-auth banner; queued mutations flush after same-user re-auth; a different-user sign-in is confirmed before wiping prior data.

**Tech Stack:** Dart, Flutter, Riverpod, go_router, Drift, Supabase auth. Spec: `docs/specs/2026-06-28-non-destructive-session-and-offline-relaunch.md`. Tests via `flutter test` from `apps/lyron_app`.

**Conventions:** All `flutter test` commands run from `apps/lyron_app`. Commit after each task. Findings: `LF-T1`, `LF-T2` (partial), `ARCH-5` (targeted seam).

---

## File Structure

- `apps/lyron_app/lib/src/application/auth/app_auth_state.dart` — add `lastKnownSession`; update `==`/`hashCode`.
- `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart` — cold-start mapping (`null` + identity → `sessionExpired`).
- `apps/lyron_app/lib/src/application/auth/last_known_identity.dart` — **new**: value type + store interface.
- `apps/lyron_app/lib/src/infrastructure/auth/...` or `offline/auth/...` — **new**: Drift-backed `LastKnownIdentityStore` impl.
- `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart:255-284` — `handleSessionExpired` non-destructive.
- `apps/lyron_app/lib/src/application/providers.dart:547-720` — wiring for offline-authenticated; write identity on sign-in.
- `apps/lyron_app/lib/src/router/app_router.dart:34-90` — keep `sessionExpired` in the app.
- `apps/lyron_app/lib/src/presentation/auth/` — re-auth banner; different-user confirmation dialog.

---

## Task 1: `AppAuthState.lastKnownSession` + equality

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth/app_auth_state.dart`
- Test: `apps/lyron_app/test/application/auth/app_auth_state_test.dart`

`AppAuthState` currently holds `status` + `session?` with `==`/`hashCode` over status + session fields (`app_auth_state.dart:5-33`).

- [ ] **Step 1: Failing test — equality and accessor include `lastKnownSession`.**

```dart
test('two states differing only in lastKnownSession are not equal', () {
  const a = AppAuthState(status: AppAuthStatus.sessionExpired);
  final b = AppAuthState(
    status: AppAuthStatus.sessionExpired,
    lastKnownSession: AppAuthSession(userId: 'u1', email: 'e@x', linkedProviders: []),
  );
  expect(a == b, isFalse);
  expect(b.lastKnownSession?.userId, 'u1');
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/auth/app_auth_state_test.dart`. Expected: FAIL (no `lastKnownSession`).

- [ ] **Step 3: Add the field.** Add `final AppAuthSession? lastKnownSession;` to the constructor, include it in `operator ==` via `_sessionEquals(other.lastKnownSession, lastKnownSession)`, and add `lastKnownSession?.userId`, `lastKnownSession?.email` into `Object.hash(...)` (`:19-24`).

- [ ] **Step 4: Run to verify it passes.** Run: `flutter test test/application/auth/app_auth_state_test.dart`. Expected: PASS.

- [ ] **Step 5: Run dependents.** Run: `flutter test test/presentation/sync/unified_sync_status_popup_test.dart` (graphify flagged it depends on `AppAuthState`). Expected: PASS (no behavior change for existing states).

- [ ] **Step 6: Commit.**

```bash
git add apps/lyron_app/lib/src/application/auth/app_auth_state.dart \
        apps/lyron_app/test/application/auth/app_auth_state_test.dart
git commit -m "feat(auth): carry lastKnownSession in AppAuthState (LF-T1)"
```

---

## Task 2: `LastKnownIdentity` value type + store

**Files:**
- Create: `apps/lyron_app/lib/src/application/auth/last_known_identity.dart`
- Create: `apps/lyron_app/lib/src/offline/auth/drift_last_known_identity_store.dart` (+ table) — follow the existing Drift store pattern used by `offline/planning` / `offline/song_catalog`.
- Test: `apps/lyron_app/test/application/auth/last_known_identity_store_test.dart`

- [ ] **Step 1: Failing test — write then read returns the identity; cold read of empty store returns null.**

```dart
test('LastKnownIdentityStore round-trips an identity', () async {
  final store = DriftLastKnownIdentityStore.inMemory();
  expect(await store.read(), isNull);
  await store.write(const LastKnownIdentity(
      userId: 'u1', email: 'e@x', organizationId: 'org1'));
  final got = await store.read();
  expect(got?.userId, 'u1');
  expect(got?.organizationId, 'org1');
});

test('clear removes the identity', () async {
  final store = DriftLastKnownIdentityStore.inMemory();
  await store.write(const LastKnownIdentity(userId: 'u1', email: 'e@x', organizationId: null));
  await store.clear();
  expect(await store.read(), isNull);
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/auth/last_known_identity_store_test.dart`. Expected: FAIL (types missing).

- [ ] **Step 3: Implement the value type + interface.**

```dart
class LastKnownIdentity {
  const LastKnownIdentity({
    required this.userId,
    required this.email,
    required this.organizationId,
    this.updatedAt,
  });
  final String userId;
  final String email;
  final String? organizationId;
  final DateTime? updatedAt;
}

abstract interface class LastKnownIdentityStore {
  Future<LastKnownIdentity?> read();
  Future<void> write(LastKnownIdentity identity);
  Future<void> clear();
}
```

- [ ] **Step 4: Implement the Drift-backed store.** Single-row table `last_known_identity` (userId, email, organizationId nullable, updatedAt). `write` upserts the single row; `read` returns it or null; `clear` deletes it. Mirror connection/factory pattern from `offline/planning/planning_local_database.dart` (`onCreate: m.createAll()`, in-memory factory for tests).

- [ ] **Step 5: Run to verify it passes.** Run: `flutter test test/application/auth/last_known_identity_store_test.dart`. Expected: PASS.

- [ ] **Step 6: Commit.**

```bash
git add apps/lyron_app/lib/src/application/auth/last_known_identity.dart \
        apps/lyron_app/lib/src/offline/auth/ \
        apps/lyron_app/test/application/auth/last_known_identity_store_test.dart
git commit -m "feat(auth): durable LastKnownIdentity store for offline cold-start (ARCH-5 seam)"
```

---

## Task 3: Write identity on successful sign-in; clear on destructive paths

**Files:**
- Modify: `apps/lyron_app/lib/src/application/providers.dart` (auth listener wiring, near `:547-720`)
- Test: `apps/lyron_app/test/application/auth/identity_persistence_wiring_test.dart`

- [ ] **Step 1: Failing test — `signedIn` writes identity; `signedOut`/verified-empty clears it.**

```dart
test('signedIn persists LastKnownIdentity; explicit sign-out clears it', () async {
  // arrange: fake LastKnownIdentityStore + AppAuthController driven through states
  // act: drive signedIn(user u1, org resolved) → then signedOut
  // assert: store.write called with u1 on signedIn; store.clear called on signedOut
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/auth/identity_persistence_wiring_test.dart`. Expected: FAIL.

- [ ] **Step 3: Wire it.** Add a `lastKnownIdentityStoreProvider`. In the auth-state handler(s) in `providers.dart`: on `signedIn`, write `LastKnownIdentity(userId, email, organizationId: resolved-or-cached org)`; on `signedOut` (explicit) and on `verifiedEmptyMembership`, call `store.clear()`. Do **not** clear on `sessionExpired`.

- [ ] **Step 4: Run to verify it passes.** Run: `flutter test test/application/auth/identity_persistence_wiring_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib/src/application/providers.dart \
        apps/lyron_app/test/application/auth/identity_persistence_wiring_test.dart
git commit -m "feat(auth): persist identity on sign-in, clear on destructive paths (LF-T1)"
```

---

## Task 4: Cold-start mapping in `AppAuthController`

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart:22-26,68-81`
- Test: `apps/lyron_app/test/application/auth/app_auth_controller_test.dart`

Today `restoreSession` returns `null` → `_stateForSession(null, fromStream: false)` → `signedOut` (`:80`), which drives the destructive explicit-sign-out path.

- [ ] **Step 1: Failing test — cold start with identity maps to `sessionExpired`, without identity maps to `signedOut`.**

```dart
test('cold start null session + persisted identity → sessionExpired', () async {
  // arrange: repo.restoreSession returns null; identityStore.read returns u1
  await controller.restoreSession();
  expect(controller.state.status, AppAuthStatus.sessionExpired);
  expect(controller.state.lastKnownSession?.userId, 'u1');
});

test('cold start null session + no identity → signedOut', () async {
  // arrange: repo.restoreSession null; identityStore.read null
  await controller.restoreSession();
  expect(controller.state.status, AppAuthStatus.signedOut);
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/auth/app_auth_controller_test.dart -p "cold start"`. Expected: FAIL.

- [ ] **Step 3: Implement.** Inject a `LastKnownIdentityStore` into `AppAuthController`. In `restoreSession`, when the restored session is `null`, read the identity; if present, set `AppAuthState(status: sessionExpired, lastKnownSession: <from identity>)`; else `signedOut`. Keep the existing stream mapping for in-session expiry (`:75-78`) but also populate `lastKnownSession` there from the prior `_state.session`.

- [ ] **Step 4: Run to verify it passes.** Run: `flutter test test/application/auth/app_auth_controller_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib/src/application/auth/app_auth_controller.dart \
        apps/lyron_app/test/application/auth/app_auth_controller_test.dart
git commit -m "feat(auth): map offline cold-start to sessionExpired, not signedOut (LF-T1/LF-T2)"
```

---

## Task 5: Planning `handleSessionExpired` non-destructive

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart:255-284`
- Test: `apps/lyron_app/test/application/planning/planning_sync_controller_test.dart`

Today it calls `deletePlanningDataForUser` (`:270`). Catalog's equivalent (`song_catalog_controller.dart:322-329`) is already non-destructive — mirror it.

- [ ] **Step 1: Failing test — session expiry preserves projection + pending mutations; explicit sign-out still deletes.**

```dart
test('handleSessionExpired keeps planning data', () async {
  // arrange: store seeded with a plan + a pending mutation for user u1
  await controller.handleSessionExpired();
  expect(await store.readPlanSummaries(userId: 'u1', organizationId: 'org1'), isNotEmpty);
});

test('handleExplicitSignOut still deletes planning data', () async {
  await controller.handleExplicitSignOut();
  expect(await store.readPlanSummaries(userId: 'u1', organizationId: 'org1'), isEmpty);
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/planning/planning_sync_controller_test.dart -p "keeps planning data"`. Expected: FAIL (data deleted).

- [ ] **Step 3: Implement.** In `handleSessionExpired` (`:255-284`): keep the generation/boundary advance and state reset, but remove the `deletePlanningDataForUser` call. Set access status to a non-destructive offline-authenticated state (do not reset to `signedOut`). Leave `handleExplicitSignOut` and `handleVerifiedEmptyMembership` unchanged (still delete).

- [ ] **Step 4: Run to verify it passes.** Run: `flutter test test/application/planning/planning_sync_controller_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart \
        apps/lyron_app/test/application/planning/planning_sync_controller_test.dart
git commit -m "fix(planning): non-destructive session expiry, keep local data (LF-T1)"
```

---

## Task 6: Wiring — offline-authenticated reactions in providers

**Files:**
- Modify: `apps/lyron_app/lib/src/application/providers.dart:547-561,607-620,700-715`
- Test: `apps/lyron_app/test/application/planning/...`, `test/application/song_library/...`

The three controllers react to `sessionExpired` in their `handleAuthStateChanged` switches (planning `:614-616`, catalog `:707-709`, active-catalog `:552-554`).

- [ ] **Step 1: Failing test — on `sessionExpired`, controllers enter offline-authenticated (no wipe), not signed-out cleanup.**

```dart
test('sessionExpired leaves catalog cache readable (offline-authenticated)', () async {
  // arrange: catalog controller with cached catalog for u1
  // act: drive auth state to sessionExpired
  // assert: cached catalog still served; status reflects expired-but-readable
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/song_library/song_catalog_controller_test.dart -p "offline-authenticated"`. Expected: FAIL or confirms current behavior bounces.

- [ ] **Step 3: Implement.** Ensure the `sessionExpired` branches call only the non-destructive handlers (planning Task 5; catalog already non-destructive). Confirm no `resetForSessionLifecycle`/cleanup path is taken on `sessionExpired` that clears cached reads. Active-catalog context (`:551-554`) must keep serving the cached org instead of resetting.

- [ ] **Step 4: Run to verify it passes.** Run: `flutter test test/application/`. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib/src/application/providers.dart apps/lyron_app/test/application/
git commit -m "feat(auth): offline-authenticated controller wiring on sessionExpired (LF-T1)"
```

---

## Task 7: Router keeps `sessionExpired` in the app

**Files:**
- Modify: `apps/lyron_app/lib/src/router/app_router.dart:34-90`
- Test: `apps/lyron_app/test/router/app_router_test.dart`

Today any non-`signedIn`, non-`initializing` status falls to `if (!isPublicRoute) return signIn.path` (`:85-86`).

- [ ] **Step 1: Failing test — `sessionExpired` on a protected route is NOT redirected to sign-in.**

```dart
test('sessionExpired stays on the requested protected route', () {
  // arrange: authController.state = sessionExpired with lastKnownSession; membership = cached Selected
  final redirect = router.redirect(context, stateForLocation(AppRoutes.home.path));
  expect(redirect, isNull); // no bounce to sign-in
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/router/app_router_test.dart -p "sessionExpired stays"`. Expected: FAIL (redirects to sign-in).

- [ ] **Step 3: Implement.** In `redirect`, treat `sessionExpired` like `signedIn` for navigation gating: it passes through to protected routes when membership resolves via the cached organization (`membershipResolutionProvider` cached fallback, see `docs/specs/2026-06-03-offline-membership-gate-cached-fallback.md`). Keep `signedOut` → sign-in unchanged.

- [ ] **Step 4: Run to verify it passes.** Run: `flutter test test/router/app_router_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib/src/router/app_router.dart apps/lyron_app/test/router/app_router_test.dart
git commit -m "feat(router): keep offline-authenticated users in the app (LF-T1)"
```

---

## Task 8: Re-auth banner

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/auth/reauth_banner.dart`
- Modify: shared authenticated scaffold/header (where the unified workspace header lives) to show the banner when `status == sessionExpired`.
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart` (banner strings — centralized, AGENTS i18n discipline / UX-10)
- Test: `apps/lyron_app/test/presentation/auth/reauth_banner_test.dart`

- [ ] **Step 1: Failing widget test — banner shows in `sessionExpired`, hidden otherwise; action triggers sign-in.**

```dart
testWidgets('re-auth banner shows when sessionExpired and opens sign-in', (tester) async {
  // pump app shell with auth state sessionExpired
  expect(find.text(AppStrings.reauthRequiredMessage), findsOneWidget);
  await tester.tap(find.byKey(const Key('reauth-banner-action')));
  // assert navigation to sign-in flow
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/presentation/auth/reauth_banner_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement** the banner widget + string + insertion in the authenticated shell; on tap, route to the sign-in flow (same-user re-auth returns to current location via the existing `from` query param pattern, `app_router.dart:46,56`).

- [ ] **Step 4: Run to verify it passes.** Run: `flutter test test/presentation/auth/reauth_banner_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib/src/presentation/auth/reauth_banner.dart \
        apps/lyron_app/lib/src/shared/app_strings.dart \
        apps/lyron_app/test/presentation/auth/reauth_banner_test.dart
git commit -m "feat(auth): re-auth banner for offline-authenticated state (LF-T1)"
```

---

## Task 9: Different-user re-auth confirmation

**Files:**
- Modify: `apps/lyron_app/lib/src/application/providers.dart` (sign-in resolution) and/or a small `ReauthResolution` unit
- Modify: `apps/lyron_app/lib/src/presentation/auth/` (confirmation dialog)
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Test: `apps/lyron_app/test/application/auth/reauth_resolution_test.dart`

- [ ] **Step 1: Failing test — same user flushes; different user requires confirmation before wipe.**

```dart
test('same-user re-auth flushes queue without wiping', () async {
  // arrange: lastKnownSession u1 + pending mutations; sign-in resolves to u1
  // assert: no wipe; syncPendingMutations invoked
});

test('different-user re-auth with pending data requires confirmation before wipe', () async {
  // arrange: lastKnownSession u1 + pending mutations; sign-in resolves to u2
  // assert: prior data NOT wiped until confirm; on confirm, u1 data cleared then proceed as u2
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/auth/reauth_resolution_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement.** On a fresh `signedIn`, compare the new `userId` with `lastKnownSession?.userId`. Same → proceed (existing refresh/sync flushes the queue). Different → if `hasUnsyncedMutations(userId: priorUserId)` (store method, `planning_mutation_sync_types.dart:470`), present a confirmation (`AppStrings.reauthDifferentUserPendingMessage` with email + count); confirm → clear prior user's data + identity, proceed as new user; cancel → sign out the new session, remain offline-authenticated as prior user.

- [ ] **Step 4: Run to verify it passes.** Run: `flutter test test/application/auth/reauth_resolution_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib/src/application/providers.dart \
        apps/lyron_app/lib/src/presentation/auth/ \
        apps/lyron_app/lib/src/shared/app_strings.dart \
        apps/lyron_app/test/application/auth/reauth_resolution_test.dart
git commit -m "feat(auth): confirm before wiping prior user on different-user re-auth (LF-T1)"
```

---

## Task 10: Documentation (ADR + architecture)

**Files:**
- Create: `docs/architecture/decisions/ADR-0XX-non-destructive-session-and-offline-authenticated-state.md`
- Modify: `docs/architecture/architecture.md` (Offline Strategy)
- Modify (if guarantee wording changes): `docs/product/vision.md`

- [ ] **Step 1: Write the ADR** recording: the offline-authenticated state, the destructive ↔ non-destructive matrix (from the spec), identity persistence, and that it extends `ADR-008-local-first.md`'s offline horizon.
- [ ] **Step 2: Update architecture Offline Strategy** with the offline-authenticated state + `LastKnownIdentity`.
- [ ] **Step 3: Commit.**

```bash
git add docs/architecture/decisions/ docs/architecture/architecture.md docs/product/vision.md
git commit -m "docs(auth): ADR + architecture for non-destructive session lifecycle (LF-T1)"
```

---

## Final Verification

- [ ] Full auth + planning + catalog + router suites green: `flutter test test/application/auth/ test/application/planning/ test/application/song_library/ test/router/ test/presentation/auth/`.
- [ ] `flutter analyze` — no new issues.
- [ ] Manual matrix walk-through (or integration test): offline relaunch with dead token → cached songs/plans visible; offline edit → re-auth same user → synced; different-user sign-in → confirmation before wipe.

---

## Self-Review Notes

- Spec coverage: Task 1↔AppAuthState field, Task 2↔identity store, Task 3↔persist/clear, Task 4↔cold-start mapping, Task 5↔planning non-destructive, Task 6↔offline-authenticated wiring, Task 7↔router, Task 8↔banner, Task 9↔different-user confirmation, Task 10↔docs/ADR. Behaviour-matrix rows all covered.
- Type consistency: `LastKnownIdentity` (Task 2) used in Tasks 3/4/9; `lastKnownSession` (Task 1) used in Tasks 4/7/9; `hasUnsyncedMutations` is an existing store method (`planning_mutation_sync_types.dart:470`).
- Dependency order: Tasks 1–2 are foundations; 4 depends on 2; 5 independent; 6 depends on 5; 7 depends on 1; 8–9 depend on 1/2/4. Execute in listed order.
