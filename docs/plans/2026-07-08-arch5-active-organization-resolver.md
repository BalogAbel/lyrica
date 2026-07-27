# ARCH-5 Active-Organization Resolver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate active-organization resolution into one `ActiveOrganizationResolver` that owns the raw / cached-fallback / organization-id flavors, with the existing provider seams delegating to it and zero behavior change.

**Architecture:** A plain application-layer class composes the existing pure functions (`resolveActiveOrganizationResolution`, `resolveMembershipWithCachedFallback`). The three current providers (`activeOrganizationResolutionProvider`, `membershipResolutionProvider`, `activeOrganizationReaderProvider`) keep their identities and override seams; the latter two become one-line delegations to the resolver. The two pure functions move to `active_organization_resolution.dart` for cohesion.

**Tech Stack:** Dart / Flutter, Riverpod, `flutter_test`.

**Spec:** `docs/specs/2026-07-08-arch5-active-organization-resolver.md`

**Preserve exactly (ADR-016):** cached fallback is gated strictly on `unknownConnectivityFailure`. Do NOT touch controllers' own fallback paths (that is the rejected A2 scope). Do NOT touch RLS/RPC/schema.

---

## File Structure

- Create: `apps/lyron_app/lib/src/application/active_organization_resolver.dart`
- Modify: `apps/lyron_app/lib/src/application/active_organization_resolution.dart` (relocate `resolveMembershipWithCachedFallback` here)
- Modify: `apps/lyron_app/lib/src/application/auth_providers.dart` (remove the moved fn; add resolver provider; delegate two providers)
- Test (create): `apps/lyron_app/test/application/active_organization_resolver_test.dart`
- Test (modify): `apps/lyron_app/test/application/membership_resolution_test.dart` (import cleanup only)
- Docs: ADR-022, `architecture.md`, `repository-review-2026-06-22.md`, deferred reauth doc

---

## Task 1: Characterize `ActiveOrganizationResolver` (failing first)

**Files:**
- Create: `apps/lyron_app/test/application/active_organization_resolver_test.dart`

- [ ] **Step 1: Write the failing resolver test**

Create `apps/lyron_app/test/application/active_organization_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/active_organization_resolver.dart';

ActiveOrganizationResolver buildResolver({
  required ActiveOrganizationResolution resolution,
  String? userId = 'user-1',
  String? cachedOrganizationId,
  bool cacheThrows = false,
}) {
  return ActiveOrganizationResolver(
    resolveRawReader: () async => resolution,
    readUserId: () => userId,
    readCachedOrganizationId: ({required userId}) async {
      if (cacheThrows) throw StateError('cache read failed');
      return cachedOrganizationId;
    },
  );
}

void main() {
  group('ActiveOrganizationResolver', () {
    test('resolveRaw passes the reader resolution through unchanged', () async {
      final resolver = buildResolver(
        resolution: const ActiveOrganizationResolution.selected('org-1'),
      );
      expect(
        await resolver.resolveRaw(),
        const ActiveOrganizationResolution.selected('org-1'),
      );
    });

    test('resolveWithCachedFallback uses cache only on connectivity failure',
        () async {
      final resolver = buildResolver(
        resolution:
            const ActiveOrganizationResolution.unknownConnectivityFailure(),
        cachedOrganizationId: 'org-cached',
      );
      expect(
        await resolver.resolveWithCachedFallback(),
        const ActiveOrganizationResolution.selected('org-cached'),
      );
    });

    test('resolveWithCachedFallback does not fall back on verifiedEmpty',
        () async {
      final resolver = buildResolver(
        resolution: const ActiveOrganizationResolution.verifiedEmpty(),
        cachedOrganizationId: 'org-cached',
      );
      expect(
        await resolver.resolveWithCachedFallback(),
        const ActiveOrganizationResolution.verifiedEmpty(),
      );
    });

    test('resolveOrganizationId returns id on selected', () async {
      final resolver = buildResolver(
        resolution: const ActiveOrganizationResolution.selected('org-1'),
      );
      expect(await resolver.resolveOrganizationId(), 'org-1');
    });

    test('resolveOrganizationId returns null on verifiedEmpty', () async {
      final resolver = buildResolver(
        resolution: const ActiveOrganizationResolution.verifiedEmpty(),
      );
      expect(await resolver.resolveOrganizationId(), isNull);
    });

    test('resolveOrganizationId throws SocketException on connectivity failure',
        () async {
      final resolver = buildResolver(
        resolution:
            const ActiveOrganizationResolution.unknownConnectivityFailure(),
      );
      await expectLater(resolver.resolveOrganizationId(), throwsA(isA<Object>()));
    });

    test('resolveOrganizationId throws StateError on non-connectivity failure',
        () async {
      final resolver = buildResolver(
        resolution:
            const ActiveOrganizationResolution.unknownNonConnectivityFailure(),
      );
      await expectLater(
        resolver.resolveOrganizationId(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run it — CONFIRM IT FAILS (resolver does not exist yet)**

Run: `cd apps/lyron_app && flutter test test/application/active_organization_resolver_test.dart`
Expected: FAIL to compile — `active_organization_resolver.dart` / `ActiveOrganizationResolver` not found.

---

## Task 2: Implement the resolver + relocate the pure function + delegate

**Files:**
- Modify: `apps/lyron_app/lib/src/application/active_organization_resolution.dart`
- Create: `apps/lyron_app/lib/src/application/active_organization_resolver.dart`
- Modify: `apps/lyron_app/lib/src/application/auth_providers.dart`
- Modify: `apps/lyron_app/test/application/membership_resolution_test.dart`

- [ ] **Step 1: Relocate `resolveMembershipWithCachedFallback` into the resolution file**

Cut the entire `resolveMembershipWithCachedFallback` function (its doc comment +
body) from `auth_providers.dart` and paste it verbatim at the end of
`apps/lyron_app/lib/src/application/active_organization_resolution.dart`. No
signature or body change. (The file already imports
`shared/connectivity_failure.dart`, which the function does not need, and the
function references only `ActiveOrganizationResolution` types already defined
there — no new imports required.)

- [ ] **Step 2: Create the resolver**

Create `apps/lyron_app/lib/src/application/active_organization_resolver.dart`:

```dart
import 'dart:io';

import 'package:lyron_app/src/application/active_organization_resolution.dart';

/// Single owner of active-organization resolution for the application layer.
///
/// Composes the pure resolution functions into the three flavors the app needs:
/// the raw backend resolution, the connectivity-gated cached-fallback resolution
/// (ADR-016), and the resolution projected to an organization id. Provider seams
/// (`activeOrganizationResolutionProvider`, `membershipResolutionProvider`,
/// `activeOrganizationReaderProvider`) delegate here so resolution lives in one
/// testable place. See ADR-022.
final class ActiveOrganizationResolver {
  ActiveOrganizationResolver({
    required ActiveOrganizationResolutionReader resolveRawReader,
    required String? Function() readUserId,
    required Future<String?> Function({required String userId})
        readCachedOrganizationId,
  }) : _resolveRawReader = resolveRawReader,
       _readUserId = readUserId,
       _readCachedOrganizationId = readCachedOrganizationId;

  final ActiveOrganizationResolutionReader _resolveRawReader;
  final String? Function() _readUserId;
  final Future<String?> Function({required String userId})
      _readCachedOrganizationId;

  /// Raw backend resolution, no fallback.
  Future<ActiveOrganizationResolution> resolveRaw() => _resolveRawReader();

  /// Raw resolution, then connectivity-gated cached fallback (ADR-016): a cached
  /// organization id is only reused on [ActiveOrganizationUnknownConnectivityFailure].
  Future<ActiveOrganizationResolution> resolveWithCachedFallback() async {
    final resolution = await resolveRaw();
    return resolveMembershipWithCachedFallback(
      resolution: resolution,
      userId: _readUserId(),
      readCachedOrganizationId: _readCachedOrganizationId,
    );
  }

  /// Projects the raw resolution to an organization id, throwing on failure
  /// outcomes so callers surface the correct gate state.
  Future<String?> resolveOrganizationId() async {
    final resolution = await resolveRaw();
    return switch (resolution) {
      ActiveOrganizationSelected(:final organizationId) => organizationId,
      ActiveOrganizationVerifiedEmpty() => null,
      ActiveOrganizationUnknownConnectivityFailure() =>
        throw const SocketException(
          'active organization lookup temporarily unavailable',
        ),
      ActiveOrganizationUnknownNonConnectivityFailure() => throw StateError(
        'active organization lookup failed',
      ),
    };
  }
}
```

- [ ] **Step 3: Delegate the providers in `auth_providers.dart`**

Add the resolver provider and rewrite the two delegating providers. Leave
`activeOrganizationResolutionProvider` unchanged. Replace the body of
`activeOrganizationReaderProvider` (the inline `switch` that was moved into the
resolver) and `membershipResolutionProvider` with delegations:

```dart
final activeOrganizationResolverProvider =
    Provider<ActiveOrganizationResolver>((ref) {
      return ActiveOrganizationResolver(
        resolveRawReader: ref.watch(activeOrganizationResolutionProvider),
        readUserId: () =>
            ref.read(appAuthControllerProvider).state.session?.userId,
        readCachedOrganizationId:
            ref.read(songCatalogStoreProvider).readLatestCachedOrganizationId,
      );
    });

final membershipResolutionProvider =
    Provider<ActiveOrganizationResolutionReader>((ref) {
      return ref
          .watch(activeOrganizationResolverProvider)
          .resolveWithCachedFallback;
    });

final activeOrganizationReaderProvider = Provider<ActiveOrganizationReader>((
  ref,
) {
  return ref.watch(activeOrganizationResolverProvider).resolveOrganizationId;
});
```

Add `import 'package:lyron_app/src/application/active_organization_resolver.dart';`
to `auth_providers.dart`. Then run `cd apps/lyron_app && flutter analyze` and
remove any now-unused imports in `auth_providers.dart` (e.g. `dart:io` if the
`SocketException`/`switch` were the only users there — the analyzer will flag it).
Do not add `// ignore:`.

- [ ] **Step 4: Fix the relocated-function import in its test**

`membership_resolution_test.dart` imports `resolveMembershipWithCachedFallback`
through `package:lyron_app/src/application/providers.dart` (the barrel) and also
directly imports `active_organization_resolution.dart`. After the move the
function lives in `active_organization_resolution.dart` (already imported there),
so the barrel import may become unused. Run
`cd apps/lyron_app && flutter analyze` and remove the now-unused
`providers.dart` import line from that test if flagged. Change nothing else.

- [ ] **Step 5: Run the resolver test — CONFIRM IT PASSES**

Run: `cd apps/lyron_app && flutter test test/application/active_organization_resolver_test.dart`
Expected: PASS (7/7).

- [ ] **Step 6: Run the resolution/membership/wiring tests — CONFIRM GREEN**

Run: `cd apps/lyron_app && flutter test test/application/active_organization_resolution_test.dart test/application/membership_resolution_test.dart test/application/auth/identity_persistence_wiring_test.dart test/application/providers_test.dart`
Expected: all PASS — the delegation preserved behavior and every override seam.

- [ ] **Step 7: analyze + full suite — CONFIRM GREEN**

Run: `cd apps/lyron_app && dart format lib test && flutter analyze && flutter test`
Expected: analyze clean; full suite green. If any test fails, STOP and apply
systematic debugging — this is a behavior-preserving refactor.

- [ ] **Step 8: Commit — two commits, test (red) first, then impl (green)**

TDD order: the resolver test from Task 1 is committed first as a failing-first
artifact (a transient red commit on the feature branch is fine; CI runs per-PR,
not per-commit), then the implementation makes it green.

```bash
git add apps/lyron_app/test/application/active_organization_resolver_test.dart
git commit -m "test(application): characterize ActiveOrganizationResolver flavors"
git add apps/lyron_app/lib/src/application/active_organization_resolver.dart apps/lyron_app/lib/src/application/active_organization_resolution.dart apps/lyron_app/lib/src/application/auth_providers.dart apps/lyron_app/test/application/membership_resolution_test.dart
git commit -m "refactor(application): introduce ActiveOrganizationResolver; delegate providers"
```

---

## Task 3: ADR-022 + architecture.md + deferred-doc refresh

**Files:**
- Create: `docs/architecture/decisions/ADR-022-active-organization-resolver.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`

- [ ] **Step 1: Write ADR-022**

Create `docs/architecture/decisions/ADR-022-active-organization-resolver.md`,
matching the house header format (see ADR-020):

```markdown
# ADR-022: Active-Organization Resolver

- Status: Accepted
- Date: 2026-07-08
- Extends: [ADR-016-active-organization-resolution-semantics.md](ADR-016-active-organization-resolution-semantics.md)
- Related: [ADR-020-non-destructive-session-and-offline-authenticated-state.md](ADR-020-non-destructive-session-and-offline-authenticated-state.md), [ADR-021-provider-domain-split.md](ADR-021-provider-domain-split.md)
- Spec: `docs/specs/2026-07-08-arch5-active-organization-resolver.md`
- Plan: `docs/plans/2026-07-08-arch5-active-organization-resolver.md`
- Findings: `ARCH-5`

## Context

Active-organization resolution was spread across three provider seams and a
free function, with no single owner (ARCH-5). ADR-020 already touched the
identity-persistence seam of ARCH-5; this decision completes it.

## Decision

Introduce `ActiveOrganizationResolver`, one application-layer class that owns the
three resolution flavors — raw, connectivity-gated cached fallback (per ADR-016),
and organization-id projection — composed from the existing pure functions
(`resolveActiveOrganizationResolution`, `resolveMembershipWithCachedFallback`,
relocated to `active_organization_resolution.dart`). The provider seams
`activeOrganizationResolutionProvider` (raw), `membershipResolutionProvider`, and
`activeOrganizationReaderProvider` are preserved with identical types and override
points; the latter two delegate to the resolver.

Controllers keep their own per-outcome fallback policy (ADR-016 §Per-Outcome
Behavior): the `activePlanningContextController` cold-start `allowCachedFallback`
path and the song catalog controller handling are NOT folded in, because they
depend on controller-held in-memory boundary state. The resolver owns the
resolution + connectivity-fallback *mechanism*; controllers own per-outcome
*policy*.

## Reauth-Seam Intersection (noted, not closed)

The resolver is where `signedIn`-time organization resolution is composed — the
same seam the deferred different-user re-auth wiring must hook
(`docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`). That wiring
remains deferred. Any future PR that wires it should hook the resolver /
`auth_providers.dart` composition point (the deferred doc, previously pointing at
the pre-split `providers.dart`, is updated to reflect this).

## Consequences

- One testable owner of active-organization resolution; providers are thin.
- ADR-016 semantics and all override seams are unchanged; no behavior change.
- Controller per-outcome policies remain where their state lives.
```

- [ ] **Step 2: Update architecture.md**

In `docs/architecture/architecture.md`, in the application-layer / DI section
(near the ADR-021 provider description added in S1), add a sentence that
active-organization resolution is owned by `ActiveOrganizationResolver` in the
application layer, with the resolution providers delegating to it, and reference
ADR-022. Keep the edit scoped.

- [ ] **Step 3: Refresh the deferred reauth doc's stale path references**

In `docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`, the S1 split
made two `providers.dart` references stale (lines ~7 and ~45). Update them:
- The "Files / integration point" reference from
  `apps/lyron_app/lib/src/application/providers.dart` to
  `apps/lyron_app/lib/src/application/auth_providers.dart` /
  `planning_providers.dart` (the post-split `signedIn` resolution home), noting
  `ActiveOrganizationResolver` as the resolution composition point.
- The trigger-condition sentence that says "touches the `signedIn` resolution in
  `providers.dart`" → reference `auth_providers.dart` / `planning_providers.dart`.
Keep the doc's meaning intact; only correct the paths.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/decisions/ADR-022-active-organization-resolver.md docs/architecture/architecture.md docs/deferred/2026-06-28-reauth-different-user-live-wiring.md
git commit -m "docs(adr): record active-organization resolver decision (ADR-022)"
```

---

## Task 4: Mark ARCH-5 fixed in the repository review

**Files:**
- Modify: `docs/architecture/repository-review-2026-06-22.md`

- [ ] **Step 1: Update the ARCH-5 references (match the convention)**

Read the surrounding lines first (numbers drift). Three edits:

**a) `**Fixed**` digest** — add after the ARCH-1 bullet:

```markdown
- **ARCH-5** (arch-spine-phase0-1 slice) — active-organization resolution is
  consolidated into a single `ActiveOrganizationResolver` (application layer)
  that owns the raw / cached-fallback / organization-id flavors; the three
  resolution providers delegate to it with identical seams. ADR-022 (extends
  ADR-016; completes the identity seam ADR-020 began). The deferred different-user
  re-auth wiring intersection is noted, not closed.
```

**b) §4 ARCH-5 detail block** (the paragraph `**ARCH-5 — active-organization
resolution**`). Append a status sentence:

```markdown
**Fixed (arch-spine-phase0-1)**: consolidated into `ActiveOrganizationResolver`
with the providers delegating (ADR-022); controller per-outcome fallback policy
retained per ADR-016.
```

**c) Remediation list** — find the `ARCH-5:` remediation line (if present) and
strike it through with `**Done (arch-spine-phase0-1).**`, matching the SEC-3 /
UX-3 / ARCH-1 style. If ARCH-5 has no dedicated remediation-list line, skip this
sub-step (the Fixed digest + §4 status are sufficient) and note that in the
commit body.

Leave the line-86 summary-table row untouched (per the established convention).

- [ ] **Step 2: Commit**

```bash
git add docs/architecture/repository-review-2026-06-22.md
git commit -m "docs(review): mark ARCH-5 fixed (active-organization resolver)"
```

---

## Self-Review

- **Spec coverage:** resolver class (Task 2 Step 2), pure-fn relocation (Task 2
  Step 1), provider delegation preserving seams (Task 2 Step 3), resolver test
  (Task 1), pure-fn/wiring tests kept green (Task 2 Steps 4, 6), ADR-022 +
  architecture.md + deferred-doc refresh (Task 3), ARCH-5 doc status (Task 4).
  All spec sections covered. A2 is explicitly excluded (no controller changes).
- **Placeholders:** none — full resolver, test, delegation, ADR, and doc-edit text
  inline.
- **Consistency:** resolver ctor param names (`resolveRawReader`, `readUserId`,
  `readCachedOrganizationId`) match between the test's `buildResolver`, the class,
  and the provider wiring; method names (`resolveRaw`, `resolveWithCachedFallback`,
  `resolveOrganizationId`) are identical across test, class, and delegations;
  `resolveOrganizationId`'s throw shapes match the original
  `activeOrganizationReaderProvider` switch verbatim.

---

## Done when

- `ActiveOrganizationResolver` owns the three flavors; providers delegate with
  identical types/seams; `activeOrganizationResolutionProvider` unchanged.
- Pure functions relocated, their tests green (import cleanup only).
- New resolver test green; `flutter analyze` clean; full `flutter test` green.
- ADR-022 added; `architecture.md` updated; deferred reauth doc paths refreshed;
  ARCH-5 marked fixed.
