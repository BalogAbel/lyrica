# Native Offline Relaunch Verification Hardening Spec

> Status: Implemented

## Goal

Close the verification gap in the local-first authenticated song-reading slice by proving persistent local cache reopen behavior through a storage seam that survives controller and database re-creation, while keeping native-target manual validation as the acceptance path for true offline relaunch and avoiding device-boot automation in repository quality gates.

## Problem

The repository currently documents native Flutter targets as the acceptance path for authenticated offline relaunch, but the automated local-first integration coverage only proves cached reading inside one process with an in-memory database. That is weaker than the documented claim.

## Scope

- Add an automated persistent-storage reopen seam for the authenticated song catalog cache.
- Replace the current in-memory same-process relaunch-style proof with a test that closes and reopens the local cache from persistent storage.
- Keep the proof focused on authenticated cached song-list and song-reader availability after one successful online sync and a later offline relaunch-style reopen.
- Keep the existing manual validation workflow and native-target acceptance rule, but tighten the docs so the automated proof and the manual acceptance path are clearly distinguished.
- Keep the slice read-only and preserve the existing `SongSummary` plus raw `SongSource` repository contract.

## Non-Goals

- No full simulator or device reboot automation in `./scripts/verify.sh`.
- No new product behavior in the Flutter UI beyond what is required for the test seam.
- No new organization-switching behavior.
- No backend schema or RLS changes.
- No browser hard-offline relaunch guarantee.

## Core Rules

- The automated test must prove that the active authenticated catalog remains readable after the original cache connection is closed and a new cache connection is opened against the same persisted local storage.
- The automated proof must not rely on `SongCatalogDatabase.inMemory()` for the relaunch scenario.
- The automated proof is a persistent-cache reopen proof, not a full native app relaunch proof.
- The reopen proof remains a native-style persistence seam, not a browser persistence claim.
- Repository docs must state clearly that:
  - automated verification proves persistent local cache reopen behavior
  - native Flutter manual validation remains the required acceptance path for authenticated offline relaunch
  - browser offline relaunch remains best-effort only

## Required Test Coverage

### Integration Coverage

Add or update coverage to prove:

- one successful authenticated backend sync writes the active catalog into persistent local storage
- the original local catalog database can be closed
- a new local catalog database instance can be opened against the same persisted storage
- when connectivity is unavailable after reopen, the cached catalog and raw song source remain readable for the authenticated user context

### Regression Coverage

Preserve coverage for:

- explicit sign-out removing cached authenticated access
- hard replace semantics for a newer full snapshot

## Documentation Requirements

Update these repository docs so they describe:

- [README.md](/Users/abelbalog/Documents/Development/private/lyrica/README.md)
- [apps/lyrica_app/README.md](/Users/abelbalog/Documents/Development/private/lyrica/apps/lyrica_app/README.md)
- [docs/product/vision.md](/Users/abelbalog/Documents/Development/private/lyrica/docs/product/vision.md)
- [docs/architecture/architecture.md](/Users/abelbalog/Documents/Development/private/lyrica/docs/architecture/architecture.md)
- [docs/architecture/decisions/2026-03-25-local-first-authenticated-song-catalog-cache.md](/Users/abelbalog/Documents/Development/private/lyrica/docs/architecture/decisions/2026-03-25-local-first-authenticated-song-catalog-cache.md)
- [docs/testing/testing-strategy.md](/Users/abelbalog/Documents/Development/private/lyrica/docs/testing/testing-strategy.md)
- [docs/workflows/development-workflow.md](/Users/abelbalog/Documents/Development/private/lyrica/docs/workflows/development-workflow.md)
- [docs/specs/2026-03-25-local-first-cached-authenticated-song-reading.md](/Users/abelbalog/Documents/Development/private/lyrica/docs/specs/2026-03-25-local-first-cached-authenticated-song-reading.md)
- [docs/specs/2026-03-25-local-first-manual-validation-scripts.md](/Users/abelbalog/Documents/Development/private/lyrica/docs/specs/2026-03-25-local-first-manual-validation-scripts.md)
- [docs/plans/2026-03-25-local-first-cached-authenticated-song-reading.md](/Users/abelbalog/Documents/Development/private/lyrica/docs/plans/2026-03-25-local-first-cached-authenticated-song-reading.md)

Those docs must stay consistent about:

- local-first verification expectations
- native versus browser acceptance boundaries
- the difference between automated persistent-cache reopen proof and native manual validation

## Success Criteria

- `apps/lyrica_app/test/integration/local_first_authenticated_song_reader_flow_test.dart` is hardened so the local-first integration slot exercises persistent cache reopen instead of only same-process memory state.
- `./scripts/verify.sh` executes that hardened integration test in the existing local-first slot.
- Repository docs no longer overclaim what the automated gate proves.
- The native manual validation workflow remains the acceptance path for authenticated offline relaunch.
