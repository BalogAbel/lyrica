# Backend SQL write contract scripts are not verify/CI gated

Status: Implemented

## Original Context

A targeted audit of backend SQL write contract scripts and CI/verify gating found that both backend write contract scripts exist and pass locally:

- `scripts/tests/planning-write-contract-test.sh`
- `scripts/tests/song-crud-write-contract-test.sh`

These scripts cover critical backend write invariants for authorization, optimistic concurrency control, dependency rejection, duplicate handling, remote-delete behavior, and SQL RPC correctness.

They were manual-only at the time of the audit.

`./scripts/verify.sh` did not run either script.
CI ran `./scripts/verify.sh` and `./scripts/check-migrations.sh`, but did not directly run these write contract scripts.

## Resolution

Implemented via the shared repository gate `./scripts/backend-write-contracts.sh`.

Current repository-owned behavior:

- Plain `./scripts/verify.sh` runs the backend write-contract gate locally.
- CI runs `./scripts/backend-write-contracts.sh` in a dedicated job for visibility.
- CI runs `./scripts/verify.sh --skip-backend-write-contracts` in the verify job to avoid duplicate execution.
- `./scripts/run-ci-locally.sh` mirrors the split CI shape with `verify`, `backend-write-contracts`, and `migrations` modes.

## Original Risk

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

## Delivered state

- `./scripts/backend-write-contracts.sh` is the shared backend SQL write-contract entrypoint.
- `./scripts/verify.sh` runs that gate by default.
- CI exposes the gate as a dedicated job and avoids duplicate execution in the verify job.
- Repository docs now describe the executable gates accurately.

## Validation

- `bash scripts/tests/verify-test.sh`
- `bash scripts/tests/backend-write-contracts-test.sh`
- `bash scripts/tests/planning-write-contract-test.sh`
- `bash scripts/tests/song-crud-write-contract-test.sh`
- `./scripts/verify.sh`
- if CI config changes, local CI simulation via `./scripts/run-ci-locally.sh` where applicable
