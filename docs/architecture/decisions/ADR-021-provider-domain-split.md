# ADR-021: Provider Domain Split

- Status: Accepted
- Date: 2026-07-08
- Related: `docs/architecture/repository-review-2026-06-22.md` (ARCH-1)
- Spec: `docs/specs/2026-07-08-arch1-provider-domain-split.md`
- Plan: `docs/plans/2026-07-08-arch1-provider-domain-split.md`

## Context

`providers.dart` was a 776-line dependency-injection god-file (ARCH-1, High
severity in the 2026-06-22 repository review): every Riverpod provider for
auth, song catalog, planning, and shared infrastructure lived in one file,
regardless of domain. The `PlanningMutationReconciler` half of ARCH-1 was
already extracted into an injectable, independently testable unit
(`b2d1053`, `application/planning/planning_mutation_reconciler.dart`). The
remaining god-file split is this decision.

## Decision

Split `providers.dart` into four domain-scoped files behind a re-export
barrel:

- `core_providers.dart` — infra + shared Drift database lifecycle
  (`syncOverviewProvider`, `supabaseClientProvider`, the shared song-catalog
  and planning-local database singletons, `closeSharedDatabases()`) and the
  shared last-known-identity persistence epoch.
- `auth_providers.dart` — auth repository, active-organization resolution,
  app auth controller, last-known-identity persistence, invitations,
  membership, and capability resolution.
- `song_catalog_providers.dart` — song catalog store, remote repository,
  session verification, foreground state, and the catalog controller.
- `planning_providers.dart` — the verified-empty-membership cleanup
  coordinator, planning local store/mutation store, planning read/write
  repositories, planning sync controllers, and active planning context.

`providers.dart` becomes a barrel that `export`s the four files (plus the
pre-existing `song_library_providers.dart` re-export), so all existing
`import '.../application/providers.dart'` call sites are untouched — zero
call-site churn.

The shared last-known-identity persistence epoch is relocated to
`core_providers.dart`, renamed public (`LastKnownIdentityPersistenceEpoch` /
`lastKnownIdentityPersistenceEpochProvider`) and annotated `@internal`
(`package:meta`), and `hide`-n from the `providers.dart` barrel so it stays
off the public application-provider surface while remaining readable by both
`auth_providers.dart` and `planning_providers.dart`.

File-level import cycles between `planning_providers.dart` and
`song_catalog_providers.dart` are accepted: Dart supports cyclic library
imports, and Riverpod providers initialize lazily, so the DI wiring's
inherent interconnection (the catalog controller reads the planning cleanup
coordinator; planning write service reads the song catalog store) is
expressed directly rather than contorted to force an acyclic file graph.

A characterization test (`test/application/providers_test.dart`) pins the
full 40-provider public surface exported through the barrel, both before and
after the split, as a compile-time guard against silently dropping or
renaming a provider during the move.

## Consequences

- Zero call-site churn: all 46 existing importers of `providers.dart` are
  unaffected.
- Smaller, domain-cohesive provider files replace one 776-line god-file.
- `providers.dart` remains the single application-provider entry point for
  the rest of the codebase.
- Import cycles between `planning_providers.dart` and
  `song_catalog_providers.dart` mean the four domain files are not
  independently importable as a strict layered DAG — accepted as reasonable
  for a DI composition layer, not a domain-model layer.
- ARCH-1 is now fully addressed: the reconciler extraction (`b2d1053`) plus
  this file split together retire the god-file finding.
