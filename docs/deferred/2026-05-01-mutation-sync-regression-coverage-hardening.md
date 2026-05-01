# Mutation sync regression coverage hardening

Status: Deferred

Classification: P2

## Context

A targeted Planning + Song mutation sync correctness and reconciliation audit found no broken invariant for:

- data loss
- duplicate application
- stale overwrite
- incorrect ordering
- connectivity retry
- app restart replay
- inconsistent local versus backend state

The focused Planning and Song mutation sync tests passed.

Verified commands:

- `flutter test test/application/planning test/application/song_library test/offline/planning test/offline/song_catalog`
- `bash scripts/tests/planning-write-contract-test.sh`
- `bash scripts/tests/song-crud-write-contract-test.sh`

## Gaps

- Planning accepted-write fallback is tested at controller callback level, but not through full provider/local-store integration for every mutation kind.
- Song pending mutation persistence across Drift database reopen is not explicitly tested.

## Required future tests

- Planning refresh failure after an accepted write updates the actual local projection for plan, session, session-item, and reorder paths.
- Song pending create, update, and delete mutations survive Drift database reopen.

## Timing

Defer unless mutation sync or reconciliation is changed.

Add this coverage before the next refactor touching mutation sync or reconciliation.

## Escalation

A mini worker is acceptable for adding focused tests only.

Require stronger review before changing sync or reconciliation logic.
