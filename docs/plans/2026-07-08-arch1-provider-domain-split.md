# ARCH-1 Provider Domain-Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the 776-line `application/providers.dart` god-file into four domain-scoped provider files behind a re-export barrel, with zero behavior change and zero call-site churn.

**Architecture:** Move each top-level declaration **verbatim** from `providers.dart` into one of four new files in the same directory (`core_providers.dart`, `auth_providers.dart`, `song_catalog_providers.dart`, `planning_providers.dart`). `providers.dart` becomes a barrel that `export`s them, so all 46 existing `import '.../application/providers.dart'` call sites are untouched. The only code edit to moved declarations is renaming the shared persistence-epoch symbol to public + `@internal`, which the barrel `hide`s.

**Tech Stack:** Dart / Flutter, Riverpod, `flutter analyze`, `flutter test`, `package:meta`.

**Spec:** `docs/specs/2026-07-08-arch1-provider-domain-split.md`

**Key preconditions (already true, do not redo):** `PlanningMutationReconciler` is already extracted (`application/planning/planning_mutation_reconciler.dart`, tested, injectable clock). This slice does NOT touch it. Do NOT refactor org-resolution internals — that is a later slice (ARCH-5).

---

## File Structure

- Create: `apps/lyron_app/lib/src/application/core_providers.dart`
- Create: `apps/lyron_app/lib/src/application/auth_providers.dart`
- Create: `apps/lyron_app/lib/src/application/song_catalog_providers.dart`
- Create: `apps/lyron_app/lib/src/application/planning_providers.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart` → barrel only
- Modify: `apps/lyron_app/pubspec.yaml` → add `meta` dependency
- Test: `apps/lyron_app/test/application/providers_test.dart` → add surface guard
- Docs: ADR-021, `architecture.md`, `repository-review-2026-06-22.md`

### Declaration → file map (exact inventory of the 40 public providers + helpers)

**`core_providers.dart`** (infra + shared DB lifecycle + shared epoch):
`syncOverviewProvider`, `supabaseClientProvider`, the `_sharedSongCatalogDatabase`
and `_sharedPlanningLocalDatabase` statics, `songCatalogDatabaseProvider`,
`planningLocalDatabaseProvider`, `closeSharedDatabases()`, and the relocated epoch
(`LastKnownIdentityPersistenceEpoch` class + `lastKnownIdentityPersistenceEpochProvider`).

**`auth_providers.dart`:** `authRepositoryProvider`,
`activeOrganizationResolutionProvider`, `appAuthControllerProvider`,
`lastKnownIdentityDatabaseProvider`, `lastKnownIdentityStoreProvider`,
`lastKnownIdentityPersistenceProvider`, `invitationRepositoryProvider`,
`pendingInviteTokenControllerProvider`, `redeemControllerProvider`,
`deepLinkListenerProvider`, `activeMembershipControllerProvider`,
`membershipResolutionProvider`, `membershipRefreshEffectProvider`,
`appAuthListenableProvider`, `activeOrganizationReaderProvider`,
`capabilityResolverProvider`.

**`song_catalog_providers.dart`:** `songCatalogStoreProvider`,
`supabaseSongRepositoryProvider`, `catalogSessionVerifierProvider`,
`appForegroundStateProvider`, `songCatalogControllerProvider`,
`activeCatalogContextProvider`, `catalogSnapshotStateProvider`.

**`planning_providers.dart`:** `VerifiedEmptyMembershipCleanupHandler` typedef,
`VerifiedEmptyMembershipCleanupCoordinator` class,
`verifiedEmptyMembershipCleanupCoordinatorProvider`, `planningLocalStoreProvider`,
`planningMutationStoreProvider`, `planningLocalReadRepositoryProvider`,
`planningWriteServiceProvider`, `planningRemoteRefreshRepositoryProvider`,
`planningMutationRemoteRepositoryProvider`,
`planningMutationSyncControllerProvider`, `planningRepositoryProvider`,
`activePlanningContextControllerProvider`, `activePlanningContextProvider`,
`planningSyncControllerProvider`, `planningSyncStateProvider`.

---

## Task 1: Characterization surface guard (before any move)

**Files:**
- Test: `apps/lyron_app/test/application/providers_test.dart`

This is a compile-time guard: it references every public provider the split
relocates, by name, through the barrel. If the split drops or renames any
provider, this test stops compiling. It does NOT read providers (reading
autoDispose controllers triggers async catalog refreshes and platform calls —
flaky), so it is deterministic. Runtime wiring is already characterized by the
other tests in this file plus the full app suite, all of which resolve providers
through the barrel.

- [ ] **Step 1: Add the surface guard test**

Append this test inside `main()` in `providers_test.dart` (the file already
imports `package:lyron_app/src/application/providers.dart` and `flutter_test`):

```dart
  test('barrel exports the full application provider surface', () {
    // Compile-time guard: naming each provider proves the barrel still exports
    // it after the domain split. Deliberately does NOT read them (reading
    // autoDispose catalog/planning controllers triggers async refreshes and
    // platform calls). Runtime wiring is covered by the other tests here and
    // the full app suite, which resolve these through the same barrel.
    final surface = <Object>[
      // core
      syncOverviewProvider,
      supabaseClientProvider,
      songCatalogDatabaseProvider,
      planningLocalDatabaseProvider,
      // auth
      authRepositoryProvider,
      activeOrganizationResolutionProvider,
      appAuthControllerProvider,
      lastKnownIdentityDatabaseProvider,
      lastKnownIdentityStoreProvider,
      lastKnownIdentityPersistenceProvider,
      invitationRepositoryProvider,
      pendingInviteTokenControllerProvider,
      redeemControllerProvider,
      deepLinkListenerProvider,
      activeMembershipControllerProvider,
      membershipResolutionProvider,
      membershipRefreshEffectProvider,
      appAuthListenableProvider,
      activeOrganizationReaderProvider,
      capabilityResolverProvider,
      // song catalog
      songCatalogStoreProvider,
      supabaseSongRepositoryProvider,
      catalogSessionVerifierProvider,
      appForegroundStateProvider,
      songCatalogControllerProvider,
      activeCatalogContextProvider,
      catalogSnapshotStateProvider,
      // planning
      verifiedEmptyMembershipCleanupCoordinatorProvider,
      planningLocalStoreProvider,
      planningMutationStoreProvider,
      planningLocalReadRepositoryProvider,
      planningWriteServiceProvider,
      planningRemoteRefreshRepositoryProvider,
      planningMutationRemoteRepositoryProvider,
      planningMutationSyncControllerProvider,
      planningRepositoryProvider,
      activePlanningContextControllerProvider,
      activePlanningContextProvider,
      planningSyncControllerProvider,
      planningSyncStateProvider,
    ];

    expect(surface, hasLength(40));
    expect(surface.toSet(), hasLength(40)); // all distinct symbols
    expect(closeSharedDatabases, isA<Function>());
  });
```

- [ ] **Step 2: Run it — CONFIRM IT PASSES (against the un-split file)**

Run: `cd apps/lyron_app && flutter test test/application/providers_test.dart`
Expected: PASS, including the new test. This pins the current surface before any
move. (If `hasLength(40)` mismatches, the list above is the source of truth —
count the actual list entries and set the two length expectations to that count;
do not silently drop a provider.)

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/application/providers_test.dart
git commit -m "test(application): characterize full provider surface before split"
```

---

## Task 2: Split `providers.dart` into domain files

**Files:**
- Create the four domain files (see map above)
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Modify: `apps/lyron_app/pubspec.yaml`

**Method:** move declarations **verbatim** (no logic edits) except the epoch
rename. Partition imports per file by starting from the current import block and
letting `flutter analyze` drive add/remove of imports until clean. Dart tolerates
cyclic library imports, so cross-file references between `planning_providers.dart`
and `song_catalog_providers.dart` are fine.

- [ ] **Step 1: Add the `meta` dependency**

In `apps/lyron_app/pubspec.yaml`, under `dependencies:`, add (alphabetically
among existing deps):

```yaml
  meta: ^1.15.0
```

Then run `cd apps/lyron_app && flutter pub get`. (If the analyzer later reports a
version-solve issue, use the version `flutter pub get` resolves; `meta` ships with
the Dart SDK constraint, so any `^1.x` that solves is acceptable.)

- [ ] **Step 2: Create `core_providers.dart`**

Create `apps/lyron_app/lib/src/application/core_providers.dart`. Move the
following declarations from `providers.dart` verbatim: `syncOverviewProvider`,
`supabaseClientProvider`, the `_sharedSongCatalogDatabase` /
`_sharedPlanningLocalDatabase` statics, `songCatalogDatabaseProvider`,
`planningLocalDatabaseProvider`, `closeSharedDatabases()`. Then move the epoch and
**rename it public with `@internal`**:

```dart
import 'package:meta/meta.dart';

/// Monotonic epoch used to invalidate stale last-known-identity persistence
/// writes when membership is verified empty. Internal to the application
/// provider library: read by [lastKnownIdentityPersistenceProvider] (auth) and
/// the verified-empty cleanup coordinator (planning). Not exported from the
/// `providers.dart` barrel.
@internal
final class LastKnownIdentityPersistenceEpoch {
  var _value = 0;

  int invalidate() {
    _value += 1;
    return _value;
  }

  bool isCurrent(int value) => _value == value;
}

@internal
final lastKnownIdentityPersistenceEpochProvider =
    Provider<LastKnownIdentityPersistenceEpoch>(
      (_) => LastKnownIdentityPersistenceEpoch(),
    );
```

Add the imports this file needs (at minimum: `dart:async`,
`package:flutter_riverpod/flutter_riverpod.dart`,
`package:supabase_flutter/supabase_flutter.dart`, `package:meta/meta.dart`, and
the offline database/store imports for the two DB providers and
`closeSharedDatabases`). Let `flutter analyze` confirm.

- [ ] **Step 3: Create `auth_providers.dart`**

Create `apps/lyron_app/lib/src/application/auth_providers.dart`. Move the auth
inventory (see map) verbatim. Update the two references to the epoch:
`lastKnownIdentityPersistenceProvider` reads
`ref.watch(_lastKnownIdentityPersistenceEpochProvider)` → change to
`ref.watch(lastKnownIdentityPersistenceEpochProvider)`. Add
`import 'package:lyron_app/src/application/core_providers.dart';` so it can see
`supabaseClientProvider`, `lastKnownIdentityDatabaseProvider`'s siblings, and the
epoch. Let `flutter analyze` prune/add imports.

- [ ] **Step 4: Create `song_catalog_providers.dart`**

Create `apps/lyron_app/lib/src/application/song_catalog_providers.dart`. Move the
song-catalog inventory verbatim. It references `core_providers.dart`
(`songCatalogDatabaseProvider`, `supabaseClientProvider`), `auth_providers.dart`
(`appAuthControllerProvider`, `activeOrganizationReaderProvider`), and
`planning_providers.dart` (`verifiedEmptyMembershipCleanupCoordinatorProvider`,
read by `songCatalogControllerProvider`). Add those imports; let `flutter analyze`
confirm the exact set.

- [ ] **Step 5: Create `planning_providers.dart`**

Create `apps/lyron_app/lib/src/application/planning_providers.dart`. Move the
planning inventory verbatim, including the `VerifiedEmptyMembershipCleanupHandler`
typedef and `VerifiedEmptyMembershipCleanupCoordinator` class. Update the epoch
reference inside `verifiedEmptyMembershipCleanupCoordinatorProvider`:
`ref.read(_lastKnownIdentityPersistenceEpochProvider).invalidate()` →
`ref.read(lastKnownIdentityPersistenceEpochProvider).invalidate()`. Add imports
for `core_providers.dart`, `auth_providers.dart`, and `song_catalog_providers.dart`
(the coordinator reads `songCatalogStoreProvider`; `planningWriteServiceProvider`
wraps a `LocalFirstSongRepository` over it).

- [ ] **Step 6: Convert `providers.dart` to a barrel**

Replace the entire contents of
`apps/lyron_app/lib/src/application/providers.dart` with:

```dart
export 'package:lyron_app/src/presentation/song_library/song_library_providers.dart';

export 'core_providers.dart'
    hide LastKnownIdentityPersistenceEpoch, lastKnownIdentityPersistenceEpochProvider;
export 'auth_providers.dart';
export 'song_catalog_providers.dart';
export 'planning_providers.dart';
```

(The first line preserves the existing re-export at the old `providers.dart:54`.)

- [ ] **Step 7: Analyze and fix imports until clean**

Run: `cd apps/lyron_app && dart format lib && flutter analyze`
Expected: no errors, no warnings. Resolve any unused-import or missing-import
findings per file. Do NOT suppress with ignores; fix the imports.

- [ ] **Step 8: Run the provider tests, then the full suite — CONFIRM GREEN**

Run: `cd apps/lyron_app && flutter test test/application/providers_test.dart`
Expected: PASS (surface guard still green — the barrel exports the same 40).

Run: `cd apps/lyron_app && flutter test`
Expected: full suite PASS with no regressions. If anything fails, STOP and use
systematic debugging — the split must be behavior-preserving; a failure means a
declaration or import was moved incorrectly.

- [ ] **Step 9: Commit**

```bash
git add apps/lyron_app/lib/src/application/ apps/lyron_app/pubspec.yaml apps/lyron_app/pubspec.lock
git commit -m "refactor(application): split providers.dart into domain-scoped files"
```

---

## Task 3: ADR + architecture.md

**Files:**
- Create: `docs/architecture/decisions/ADR-021-provider-domain-split.md`
- Modify: `docs/architecture/architecture.md`

- [ ] **Step 1: Write ADR-021**

Create `docs/architecture/decisions/ADR-021-provider-domain-split.md`, matching
the format of a recent ADR (read `ADR-020-non-destructive-session-and-offline-authenticated-state.md`
for the house structure: Status / Context / Decision / Consequences). Content to
capture:

- **Status:** Accepted.
- **Context:** `providers.dart` was a 776-line DI god-file (ARCH-1, High). The
  `PlanningMutationReconciler` half of ARCH-1 was already extracted (`b2d1053`);
  the remaining god-file split is this decision.
- **Decision:** Split into four domain-scoped files
  (`core_providers`, `auth_providers`, `song_catalog_providers`,
  `planning_providers`) behind a re-export barrel (`providers.dart`), extending
  the existing `song_library_providers.dart` barrel-export pattern. The shared
  persistence epoch is relocated to `core_providers`, made public + `@internal`,
  and `hide`-n from the barrel so it stays off the public surface. File-level
  import cycles between `planning_providers` and `song_catalog_providers` are
  accepted: Dart supports cyclic imports and Riverpod providers initialize
  lazily, so the DI wiring's inherent interconnection is expressed directly
  rather than contorted to force a DAG.
- **Consequences:** Zero call-site churn (46 importers unchanged); smaller,
  domain-cohesive files; the barrel remains the single application-provider entry
  point. Import cycles mean the four files are not independently importable as a
  strict layering — acceptable for a DI composition layer.

- [ ] **Step 2: Update architecture.md**

In `docs/architecture/architecture.md`, find the section describing the
application/DI layer (search for `providers.dart`). Update it to state that the
application providers are organized into domain-scoped files
(`core_providers.dart`, `auth_providers.dart`, `song_catalog_providers.dart`,
`planning_providers.dart`) re-exported through the `providers.dart` barrel, and
reference ADR-021. Keep the edit scoped to the DI description; do not rewrite
unrelated sections.

- [ ] **Step 3: Commit**

```bash
git add docs/architecture/decisions/ADR-021-provider-domain-split.md docs/architecture/architecture.md
git commit -m "docs(adr): record provider domain-split decision (ADR-021)"
```

---

## Task 4: Mark ARCH-1 fixed in the repository review

**Files:**
- Modify: `docs/architecture/repository-review-2026-06-22.md`

- [ ] **Step 1: Update the ARCH-1 references (match the SEC-3/UX-3 convention)**

Three edits; read the surrounding lines first (line numbers drift):

**a) `**Fixed**` digest** — add after the existing SEC-3 bullet:

```markdown
- **ARCH-1** (arch-spine-phase0-1 slice) — the `PlanningMutationReconciler` was
  already extracted (`b2d1053`, tested, injectable clock); the remaining
  `providers.dart` god-file (776 lines) is now split into four domain-scoped
  files (`core_providers`, `auth_providers`, `song_catalog_providers`,
  `planning_providers`) behind a re-export barrel. ADR-021. Zero call-site churn;
  the full provider surface is pinned by a characterization test.
```

**b) §4 ARCH-1 detail block** (the paragraph beginning `**ARCH-1 — central DI
monolith.**`). It currently recommends extracting `PlanningMutationReconciler` and
splitting the file — now both are done. Append a status sentence at the end of
that paragraph:

```markdown
**Fixed (arch-spine-phase0-1)**: `PlanningMutationReconciler` extracted earlier
in `b2d1053`; the file split into domain-scoped `*_providers.dart` behind a
barrel landed in this slice (ADR-021).
```

**c) Remediation list** — the current line reads exactly:

```markdown
- ARCH-1: split `providers.dart`; extract `PlanningMutationReconciler`.
```

Replace it with:

```markdown
- ~~ARCH-1: split `providers.dart`; extract `PlanningMutationReconciler`.~~ **Done (arch-spine-phase0-1).**
```

Also update the summary table row severity note only if the doc's convention has
been to leave summary-table rows untouched (it has, per SEC-5/SEC-3/UX-3) — so
leave the line-66 table row as-is.

- [ ] **Step 2: Commit**

```bash
git add docs/architecture/repository-review-2026-06-22.md
git commit -m "docs(review): mark ARCH-1 fixed (provider split + reconciler)"
```

---

## Self-Review

- **Spec coverage:** four domain files + barrel (Task 2), meta+`@internal`+`hide`
  for the epoch (Task 2 Steps 1-2, 6), characterization surface guard (Task 1),
  ADR-021 + architecture.md (Task 3), ARCH-1 doc status incl. stale §4 correction
  (Task 4). All spec sections covered.
- **Placeholders:** none — full test, barrel, epoch, and doc-edit text inline; the
  verbatim-move steps name every declaration explicitly via the inventory map.
- **Consistency:** the surface-guard list, the declaration→file map, and the
  barrel `hide` names (`LastKnownIdentityPersistenceEpoch`,
  `lastKnownIdentityPersistenceEpochProvider`) all agree; the epoch rename is
  applied identically in the auth reference (Step 3) and planning reference
  (Step 5).

---

## Done when

- Four domain files exist; `providers.dart` declares nothing (barrel only).
- `flutter analyze` clean; `flutter test` fully green; surface guard green before
  and after.
- Epoch symbols hidden from the barrel; `meta` + `@internal` in place.
- ADR-021 added; `architecture.md` updated; ARCH-1 marked fixed (both halves).
