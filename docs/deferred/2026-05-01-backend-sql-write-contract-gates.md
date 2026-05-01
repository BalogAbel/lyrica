# Backend SQL write contract scripts are not verify/CI gated

Status: Deferred

## Context

A targeted audit of backend SQL write contract scripts and CI/verify gating found that both backend write contract scripts exist and pass locally:

- `scripts/tests/planning-write-contract-test.sh`
- `scripts/tests/song-crud-write-contract-test.sh`

These scripts cover critical backend write invariants for authorization, optimistic concurrency control, dependency rejection, duplicate handling, remote-delete behavior, and SQL RPC correctness.

However, they are currently manual-only.

`./scripts/verify.sh` does not run either script.
CI runs `./scripts/verify.sh` and `./scripts/check-migrations.sh`, but does not directly run these write contract scripts.

## Risk

This is a P1 verification gap.

Backend SQL RPCs are the canonical write-acceptance boundary for authorization and optimistic concurrency. If the contract scripts are not part of the main merge/release gate, SQL/RLS/OCC regressions can merge without being caught by CI.

## Audit evidence

The audit confirmed:

- `bash scripts/tests/verify-test.sh` passed.
- `bash scripts/tests/planning-write-contract-test.sh` passed.
- `bash scripts/tests/song-crud-write-contract-test.sh` passed.
- `scripts/verify.sh` does not call either write contract script.
- `.github/workflows/ci.yml` runs `./scripts/verify.sh` and a migration lint job, but not the write contract scripts directly.
- `docs/testing/testing-strategy.md` currently overstates planning write contract coverage by implying it is included in `verify.sh`.

## Desired future state

Either:

1. Add both write contract scripts to `scripts/verify.sh`, and update `scripts/tests/verify-test.sh`; or
2. Add a dedicated CI job that runs both write contract scripts; and
3. Update `docs/testing/testing-strategy.md` so documented verification matches actual gates.

Documentation-only clarification is not sufficient as the final state, but may be acceptable temporarily while this remains deferred.

## Suggested implementation plan

Use Superpowers planning before implementation.

Planning artifacts created:

- `docs/specs/2026-05-01-backend-sql-write-contract-gates.md`
- `docs/plans/2026-05-01-backend-sql-write-contract-gates.md`

The plan should cover:

- where the write contract scripts should run
- whether they belong in `scripts/verify.sh` or a dedicated CI job
- runtime impact
- Supabase setup duplication
- wrapper-script compliance
- update to `scripts/tests/verify-test.sh`
- update to `docs/testing/testing-strategy.md`

## Required validation

- `bash scripts/tests/verify-test.sh`
- `bash scripts/tests/planning-write-contract-test.sh`
- `bash scripts/tests/song-crud-write-contract-test.sh`
- `./scripts/verify.sh`
- if CI config changes, local CI simulation via `./scripts/run-ci-locally.sh` where applicable

## Escalation

This should not be handled by an unconstrained mini worker without stronger review.

Escalate for:

- CI/release gate design
- Supabase lifecycle changes
- test runtime tradeoffs
- changes to SQL write contract scripts
