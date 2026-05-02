# Local-First Lifecycle And Persistence Regression Hardening Spec

## Status

Planned

## Goal

Add P2 regression coverage for local-first lifecycle and persistence behavior without changing production behavior.

This spec covers:

- Song session-expiry cache policy regression coverage.
- Planning accepted-write fallback regression coverage.
- Song pending mutation persistence across Drift database reopen.

## Context

This work resolves the test/documentation portions of:

- `docs/deferred/2026-05-01-song-session-expiry-cache-policy-hardening.md`
- `docs/deferred/2026-05-01-mutation-sync-regression-coverage-hardening.md`

The current behavior is treated as intentional unless new regression tests expose a real bug.

## Scope

### A. Song auth/session lifecycle coverage

Add tests and documentation proving:

- Explicit sign-out deletes persisted authenticated song cache and song mutations.
- Session expiry clears active song catalog access and blocks cached authenticated reads.
- Session expiry preserves persisted song cache rows unless a separately approved policy change says otherwise.
- Connectivity-unverifiable auth/session state can still use cached song fallback for the last authenticated context.
- Re-sign-in restores the auth boundary before cached song data becomes readable again.

### B. Planning accepted-write fallback coverage

Add provider/local-store integration tests proving accepted planning writes reconcile into the actual local projection when remote refresh fails.

Coverage must include:

- Plan create/edit.
- Session create/rename/delete.
- Session reorder.
- Session item create/delete/reorder.

### C. Song pending mutation persistence across Drift DB reopen

Add file-backed Drift reopen tests proving pending song mutations survive app/database restart.

Coverage must include:

- Pending create.
- Pending update.
- Pending delete.
- Read overlay behavior after reopen.
- Sync replay visibility through mutation reads after reopen.

## Non-Goals

- No production behavior changes.
- No backend schema, RPC, RLS, or authorization changes.
- No redesign of auth/session lifecycle state.
- No redesign of planning or song mutation reconciliation.
- No broad refactor of provider wiring or Drift stores.

## Documentation Requirements

Update `docs/testing/testing-strategy.md` so the repository explicitly names:

- Song session-expiry cache policy regression coverage.
- Provider/local-store accepted-write fallback regression coverage.
- Song pending mutation persistence across Drift reopen.

Update the deferred P2 items only after the corresponding tests are added and pass.

## Acceptance Criteria

- The implementation follows `docs/plans/2026-05-02-local-first-lifecycle-persistence-regression-hardening.md`.
- All added coverage is tests/docs only unless escalation is triggered.
- Focused validation commands in the plan pass.
- `docs/testing/testing-strategy.md` documents the new regression coverage.
- Deferred P2 items are updated to reflect completed coverage or remaining gaps.

## Escalation Rule

If a planned test fails because production behavior violates the intended invariant:

- Stop the tests/docs-only sweep.
- Do not patch production code inside the same unreviewed task.
- Record the failing assertion, affected invariant, and suspected production file.
- Create or update a follow-up implementation spec/plan before behavior changes.
- Require stronger review before changing auth/session lifecycle, sync reconciliation, Drift persistence, or backend-enforced authorization behavior.
