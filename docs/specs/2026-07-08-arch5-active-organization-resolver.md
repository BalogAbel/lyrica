# S2 — ARCH-5: Consolidate active-organization resolution into one resolver

**Date:** 2026-07-08
**Slice:** S2 (Phase 1)
**Finding:** ARCH-5 (`docs/architecture/repository-review-2026-06-22.md`)
**Branch:** `refactor/arch-spine-phase0-1`
**Builds on:** ADR-016 (resolution semantics), ADR-021 (provider domain split, S1)

## Problem

Active-organization resolution is spread across several provider seams and a
free function, with duplicated cached-fallback handling and no single cohesive
owner (ARCH-5, Medium — "a large implicit state surface"):

- `activeOrganizationResolutionProvider` (`auth_providers.dart`) — raw RPC
  resolution via `resolveActiveOrganizationResolution`.
- `membershipResolutionProvider` — raw resolution **plus** connectivity-gated
  cached fallback (`resolveMembershipWithCachedFallback`).
- `activeOrganizationReaderProvider` — projects raw resolution to a `String?`
  organization id (throws on failure outcomes) via an inline `switch`.
- `resolveMembershipWithCachedFallback` — a top-level pure function living in
  `auth_providers.dart`.

There is no single unit that answers "how is the active organization resolved,
in each of its flavors." The logic is legible only by reading three providers and
a loose function.

## Goal

Introduce one cohesive `ActiveOrganizationResolver` that owns the three
resolution flavors (raw, cached-fallback, and as-organization-id), composed from
the existing pure functions. The existing provider seams delegate to it. Zero
behavior change; all current override points and unit tests preserved.

## Constraints

- **Preserve provider override seams.** Tests override
  `activeOrganizationResolutionProvider` directly
  (`identity_persistence_wiring_test.dart` ×6, `lyron_app_test.dart`) and
  `activeOrganizationReaderProvider`/`membershipResolutionProvider` (many tests,
  `membership_gate.dart`). The three providers must remain override-able with
  identical identities and types.
- **Preserve the pure-function tests.** `resolveMembershipWithCachedFallback` has
  seven direct unit tests (`membership_resolution_test.dart`) and
  `resolveActiveOrganizationResolution` has `active_organization_resolution_test.dart`.
  Keep both pure functions; the resolver composes them.
- **Preserve ADR-016 semantics exactly.** Cached fallback is gated strictly on
  `unknownConnectivityFailure`. The per-outcome controller policies are unchanged.
- **Backend authorization is untouched.** No RLS/RPC/schema change (this is a
  client-side composition refactor). No new ADR-level auth decision beyond
  recording the resolver boundary.

## Scope

**In scope (A1 — auth-side resolver consolidation):**
- A new `ActiveOrganizationResolver` class + `activeOrganizationResolverProvider`.
- Relocate the two pure functions to `active_organization_resolution.dart` for
  cohesion (they already model resolution); update their test imports.
- Delegate `membershipResolutionProvider` and `activeOrganizationReaderProvider`
  to the resolver; keep `activeOrganizationResolutionProvider` as the raw seam the
  resolver is built from.
- Unit test for the resolver.
- ADR-022 + `architecture.md` + ARCH-5 marked fixed.
- Note the reauth-seam intersection and refresh the deferred doc's stale path.

**Out of scope (A2, explicitly rejected):**
- Folding the controllers' own cached-fallback paths into the resolver — namely
  `activePlanningContextController`'s `allowCachedFallback` / `latestOrganizationReader`
  cold-start logic and the song catalog controller's per-outcome handling. These
  encode ADR-016 §"Per-Outcome Behavior" rules that depend on controller-held
  in-memory boundary state; they are legitimately controller concerns. Moving them
  into a stateless resolver is behavior-critical and disproportionate to a Medium
  finding. The resolver owns the resolution + connectivity-fallback *mechanism*;
  controllers keep their per-outcome *policy*.

## Design

### `ActiveOrganizationResolver`

New file `apps/lyron_app/lib/src/application/active_organization_resolver.dart`.
A plain application-layer class, unit-testable without Riverpod:

```dart
final class ActiveOrganizationResolver {
  ActiveOrganizationResolver({
    required ActiveOrganizationResolutionReader resolveRawReader,
    required String? Function() readUserId,
    required Future<String?> Function({required String userId})
        readCachedOrganizationId,
  });

  /// Raw backend resolution, no fallback. Feeds the org-id reader and controllers.
  Future<ActiveOrganizationResolution> resolveRaw();

  /// Raw resolution, then connectivity-gated cached fallback (ADR-016).
  Future<ActiveOrganizationResolution> resolveWithCachedFallback();

  /// Projects the raw resolution to an organization id, throwing on failure
  /// outcomes (SocketException for connectivity, StateError otherwise).
  Future<String?> resolveOrganizationId();
}
```

- `resolveRaw()` calls the injected `resolveRawReader` (the
  `ActiveOrganizationResolutionReader` currently produced by
  `activeOrganizationResolutionProvider`).
- `resolveWithCachedFallback()` composes `resolveRaw()` with the existing
  `resolveMembershipWithCachedFallback(resolution:, userId:, readCachedOrganizationId:)`
  pure function.
- `resolveOrganizationId()` is the current `activeOrganizationReaderProvider`
  switch, moved verbatim into a method over `resolveRaw()`.

### Pure-function relocation

Move `resolveMembershipWithCachedFallback` from `auth_providers.dart` into
`active_organization_resolution.dart` (next to the sealed type and
`resolveActiveOrganizationResolution`). Update the import in
`membership_resolution_test.dart` accordingly. No signature or body change — the
seven existing test cases stay green.

### Provider delegation

In `auth_providers.dart`:

```dart
final activeOrganizationResolverProvider = Provider<ActiveOrganizationResolver>((ref) {
  return ActiveOrganizationResolver(
    resolveRawReader: ref.watch(activeOrganizationResolutionProvider),
    readUserId: () => ref.read(appAuthControllerProvider).state.session?.userId,
    readCachedOrganizationId:
        ref.read(songCatalogStoreProvider).readLatestCachedOrganizationId,
  );
});

final membershipResolutionProvider =
    Provider<ActiveOrganizationResolutionReader>((ref) {
      return ref.watch(activeOrganizationResolverProvider).resolveWithCachedFallback;
    });

final activeOrganizationReaderProvider = Provider<ActiveOrganizationReader>((ref) {
  return ref.watch(activeOrganizationResolverProvider).resolveOrganizationId;
});
```

`activeOrganizationResolutionProvider` is unchanged. The two delegating providers
keep their exact types (`ActiveOrganizationResolutionReader`,
`ActiveOrganizationReader`), so every existing override and consumer is unaffected.

### Reauth seam (note, do not close)

The resolver is where `signedIn`-time organization resolution is composed, which
is exactly the seam the deferred different-user reauth wiring must hook
(`docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`). That doc still
references `application/providers.dart` as the integration point, which S1's split
made stale. This slice:
- updates the deferred doc's file references to the post-split files
  (`auth_providers.dart` / `planning_providers.dart`) and notes the resolver as
  the natural composition point;
- records the intersection in ADR-022.
It does **not** wire the reauth dialog (still deferred, per the prompt).

## Testing (TDD)

1. **New** `test/application/active_organization_resolver_test.dart` (write first,
   fail first): construct `ActiveOrganizationResolver` with fake readers and
   assert each flavor:
   - `resolveRaw()` returns the reader's resolution unchanged.
   - `resolveWithCachedFallback()` applies the cached org only on
     `unknownConnectivityFailure` with a userId + cache hit; passes through
     otherwise (mirror the ADR-016 gate).
   - `resolveOrganizationId()` returns the id on `selected`, `null` on
     `verifiedEmpty`, throws `SocketException` on connectivity failure and
     `StateError` on non-connectivity failure.
2. Keep `membership_resolution_test.dart` and
   `active_organization_resolution_test.dart` green (import path update only).
3. Keep `identity_persistence_wiring_test.dart`, `providers_test.dart`,
   `lyron_app_test.dart`, and the full suite green — proves the delegation
   preserved behavior and all override seams.

## Documentation duties

- **ADR-022** `docs/architecture/decisions/ADR-022-active-organization-resolver.md`:
  the single-resolver boundary, delegation-preserving-seams decision, the A2
  rejection rationale, and the reauth-seam intersection. References ADR-016.
- **`architecture.md`**: note the resolver as the single owner of active-org
  resolution in the application layer.
- **`repository-review-2026-06-22.md`**: mark ARCH-5 fixed (Fixed digest, §4
  detail, remediation), matching the established convention.
- **Deferred doc**: update
  `docs/deferred/2026-06-28-reauth-different-user-live-wiring.md` file references
  (S1-stale `providers.dart` → split files) in the same commit.

## Commits

1. `test(application): characterize ActiveOrganizationResolver flavors` — failing
   resolver test first.
2. `refactor(application): introduce ActiveOrganizationResolver; delegate providers`
   — resolver + pure-fn relocation + provider delegation; suite green.
3. `docs(adr): record active-organization resolver decision (ADR-022)` — ADR +
   architecture.md + deferred-doc path refresh.
4. `docs(review): mark ARCH-5 fixed (active-organization resolver)`.

## Done when

- `ActiveOrganizationResolver` owns the three resolution flavors; the three
  providers delegate with identical types/seams.
- Pure functions preserved (relocated) with their tests green.
- New resolver unit test green; `flutter analyze` clean; full `flutter test` green.
- ADR-022 added; `architecture.md` updated; deferred reauth doc path refreshed;
  ARCH-5 marked fixed.
