# S1 — ARCH-1: Split `providers.dart` into domain-scoped provider files

**Date:** 2026-07-08
**Slice:** S1 (Phase 1)
**Finding:** ARCH-1 (`docs/architecture/repository-review-2026-06-22.md`)
**Branch:** `refactor/arch-spine-phase0-1`

## Problem

`apps/lyron_app/lib/src/application/providers.dart` is a 776-line DI god-file
that wires the whole application graph. ARCH-1 (High) calls for two things:

1. Extract a testable `PlanningMutationReconciler`.
2. Split the god-file into domain-scoped `*_providers.dart` files.

**Item 1 is already done.** `PlanningMutationReconciler` was extracted in
`b2d1053` (2026-06-28, after the 2026-06-22 review), lives in
`application/planning/planning_mutation_reconciler.dart` (194 lines), has a test
(`test/application/planning/planning_mutation_reconciler_test.dart`), and carries
an injectable clock seam (`0d20a50`). `providers.dart` now delegates to it in one
line (the former ~110-line inline reconcile switch is gone). The review's §4
ARCH-1 text is stale on this point; §6 already references the extracted
reconciler. This slice reconciles that staleness.

**Item 2 remains.** This slice performs it.

## Goal

Split `providers.dart` into cohesive domain-scoped provider files behind a
barrel, with **zero behavior change** and zero churn at the 46 call sites that
import `application/providers.dart`.

## Constraints

- **No behavior change.** Pure relocation: identical provider instances, types,
  names, and wiring. Proven by characterization tests that pass before and after.
- **Zero call-site churn.** `application/providers.dart` becomes a barrel that
  re-exports the domain files, so every `import '.../application/providers.dart'`
  keeps resolving the same public surface. `closeSharedDatabases` (used by
  `bootstrap.dart` and two tests) stays exported.
- **Follow the existing pattern.** The codebase already ships domain provider
  files re-exported from this barrel (`presentation/song_library/song_library_providers.dart`,
  exported at `providers.dart:54`). This split extends that pattern.
- **Do not touch the reconciler** (already extracted and tested) or the
  org-resolution internals (that is S2 / ARCH-5).

## Design

### File decomposition

`application/providers.dart` → barrel that re-exports four new domain files in
the same directory:

**`core_providers.dart`** — cross-cutting infrastructure and shared DB lifecycle:
- `supabaseClientProvider`, `syncOverviewProvider`
- shared DB statics `_sharedSongCatalogDatabase`, `_sharedPlanningLocalDatabase`
- `songCatalogDatabaseProvider`, `planningLocalDatabaseProvider`,
  `closeSharedDatabases()`
- the shared persistence epoch (see "Shared internal symbol" below)

**`auth_providers.dart`** — identity, membership, invitation, capability:
- `authRepositoryProvider`, `appAuthControllerProvider`,
  `lastKnownIdentityDatabaseProvider`, `lastKnownIdentityStoreProvider`,
  `lastKnownIdentityPersistenceProvider`, `appAuthListenableProvider`
- `invitationRepositoryProvider`, `pendingInviteTokenControllerProvider`,
  `redeemControllerProvider`, `deepLinkListenerProvider`
- `activeMembershipControllerProvider`, `membershipResolutionProvider`,
  `membershipRefreshEffectProvider`
- `activeOrganizationResolutionProvider`, `activeOrganizationReaderProvider`
- `capabilityResolverProvider`

**`song_catalog_providers.dart`** — song catalog runtime (named `song_catalog_`
to avoid confusion with the existing presentation-layer
`song_library_providers.dart`):
- `songCatalogStoreProvider`, `supabaseSongRepositoryProvider`,
  `catalogSessionVerifierProvider`, `appForegroundStateProvider`
- `songCatalogControllerProvider`, `activeCatalogContextProvider`,
  `catalogSnapshotStateProvider`

**`planning_providers.dart`** — planning local-first + sync:
- `VerifiedEmptyMembershipCleanupCoordinator` (class + `VerifiedEmptyMembershipCleanupHandler`
  typedef + `verifiedEmptyMembershipCleanupCoordinatorProvider`)
- `planningLocalStoreProvider`, `planningMutationStoreProvider`,
  `planningLocalReadRepositoryProvider`, `planningWriteServiceProvider`
- `planningRemoteRefreshRepositoryProvider`,
  `planningMutationRemoteRepositoryProvider`,
  `planningMutationSyncControllerProvider` (delegating to the existing
  `PlanningMutationReconciler`), `planningRepositoryProvider`
- `activePlanningContextControllerProvider`, `activePlanningContextProvider`,
  `planningSyncControllerProvider`, `planningSyncStateProvider`

### Barrel

`application/providers.dart` keeps only:
- its existing `export '...presentation/song_library/song_library_providers.dart';`
- `export 'core_providers.dart' hide lastKnownIdentityPersistenceEpochProvider, LastKnownIdentityPersistenceEpoch;`
- `export 'auth_providers.dart';`
- `export 'song_catalog_providers.dart';`
- `export 'planning_providers.dart';`

No declarations of its own. Every current call site is unaffected.

### Shared internal symbol

`_LastKnownIdentityPersistenceEpoch` and `_lastKnownIdentityPersistenceEpochProvider`
are read by **two domains**: auth (`lastKnownIdentityPersistenceProvider`) and
planning (`verifiedEmptyMembershipCleanupCoordinatorProvider`, which calls
`.invalidate()`). A file-private symbol cannot cross the split.

Resolution (approved): relocate both into `core_providers.dart`, rename to public
(`LastKnownIdentityPersistenceEpoch`, `lastKnownIdentityPersistenceEpochProvider`),
annotate with `@internal` (`package:meta`), and **`hide`** both from the barrel so
they never reach the public surface that the 46 call sites see. `auth_providers.dart`
and `planning_providers.dart` import `core_providers.dart` directly to reach them.
`package:meta` is added to `apps/lyron_app/pubspec.yaml` dependencies; the `hide`
is the enforcing mechanism, `@internal` documents intent.

### Import cycles are expected

The DI wiring is genuinely interconnected: `planning_providers` references
`song_catalog_providers` (e.g. `PlanningWriteService` wraps a
`LocalFirstSongRepository` over `songCatalogStoreProvider`), and
`song_catalog_providers` references `planning_providers` (the
`songCatalogControllerProvider` calls the cleanup coordinator). Dart supports
cyclic library imports, and Riverpod providers initialize lazily, so these
file-level cycles compile and run correctly. Domain placement stays cohesive; the
ADR records that import cycles are an accepted property of this DI layer rather
than a defect to design around.

## Testing (TDD, characterization-first)

The existing `test/application/providers_test.dart` already reads a broad slice of
the graph (`supabaseClientProvider`, `planningRepositoryProvider`, the planning
local-first seams, `songCatalogControllerProvider`, `activeCatalogContextProvider`,
`catalogSnapshotStateProvider`, `planningSyncStateProvider`, `songLibraryListProvider`)
through the barrel. It is the characterization net.

1. **Add a surface-completeness characterization test** to `providers_test.dart`
   first: a `ProviderContainer` (with the same overrides the file already uses)
   that reads **every** public top-level provider exported by the barrel and
   asserts each resolves non-null (or to its expected type), plus asserts
   `closeSharedDatabases` is callable. Run the full suite green **before** the
   split — this pins the exact public surface.
2. Perform the split (create the four files, convert the barrel).
3. Run `test/application/providers_test.dart` and the full app suite: identical
   green result. No test file imports change (all go through the barrel).
4. Confirm the hidden epoch symbols are NOT reachable through the barrel: a
   negative check is implicit (any test importing only the barrel cannot name
   them); document this rather than adding a compile-failure test.

## Documentation duties

- **ADR** `docs/architecture/decisions/ADR-021-provider-domain-split.md`: records
  the domain decomposition, the barrel + `hide` strategy for the shared epoch, and
  the accepted-import-cycle decision. (ADR-021 is the next free number; 020 is the
  current highest.)
- **`docs/architecture/architecture.md`**: update the DI/application-layer
  description to reflect domain-scoped provider files behind the barrel.
- **`docs/architecture/repository-review-2026-06-22.md`**: mark ARCH-1 fixed —
  both halves (reconciler already extracted in `b2d1053`; god-file split in this
  slice) — in the `**Fixed**` digest, the §4 ARCH-1 detail (correct the stale
  "extract PlanningMutationReconciler" wording), and the remediation list.

## Commits

1. `test(application): characterize full provider surface before split` — the
   surface-completeness test; green before any move.
2. `refactor(application): split providers.dart into domain-scoped files` — create
   the four domain files + barrel + `meta` dep; suite stays green.
3. `docs(adr): record provider domain-split decision` — ADR + architecture.md.
4. `docs(review): mark ARCH-1 fixed (provider split + reconciler)` — review-doc
   status.

## Done when

- Four domain files + barrel; `providers.dart` declares nothing itself.
- All 46 call sites unchanged; `flutter analyze` clean; full `flutter test` green.
- Characterization test covers the full exported provider surface, green before
  and after.
- Epoch symbols hidden from the barrel; `@internal` + `meta` in place.
- ADR added; `architecture.md` updated; ARCH-1 marked fixed (both halves).
