# Backend SQL Write Contract Gates

> Status: Draft

## Goal

Close the P1 verification gap where the repository's backend SQL write contract scripts pass locally but are not part of the main local verify path or the main release gate.

## Problem

The repository already contains two high-value backend contract scripts:

- `scripts/tests/planning-write-contract-test.sh`
- `scripts/tests/song-crud-write-contract-test.sh`

They validate backend-enforced write acceptance at the canonical authorization and optimistic-concurrency boundary. Today they are manual-only. The main local verification entrypoint (`./scripts/verify.sh`) does not run them, and the primary CI workflow does not gate merges on them directly.

This leaves a release path where SQL RPC, RLS, authorization, duplicate-handling, or OCC regressions can merge even when the existing contract scripts would have caught them.

## Scope

- decide where backend SQL write contract scripts belong in the repository's enforced quality gates
- compare three gating strategies: verify-only, dedicated-CI-only, and hybrid
- define repository-owned expectations for local verification, CI verification, and CI-parity tooling
- define the documentation and regression-test updates required to keep repository guidance aligned with executable gates

## Non-Goals

- no changes to SQL write-contract semantics
- no expansion of the current backend write coverage beyond the existing planning and song CRUD contract suites
- no redesign of the Supabase wrapper strategy
- no migration from shell-based backend contract tests to another test framework in this slice

## Decision Drivers

- release safety for backend-owned authorization and OCC rules
- low drift between local developer workflow and CI workflow
- minimal duplicate Supabase lifecycle work
- fast enough default local verification to remain usable
- repository docs that accurately describe actual gates

## Current State

- `./scripts/verify.sh` runs formatting, analysis, Flutter tests, migration lint, Supabase reset/provisioning, backend-backed Flutter integration tests, and the manual-validation script contract test.
- `scripts/tests/verify-test.sh` asserts that current `verify.sh` sequence.
- `.github/workflows/ci.yml` runs `./scripts/verify.sh` in one job and `./scripts/check-migrations.sh` in another job.
- both write-contract scripts currently bootstrap Supabase independently and reset the database inside each script.
- `docs/testing/testing-strategy.md` currently overstates `verify.sh` coverage for planning write contracts.

## Option Evaluation

| Option | Correctness / release safety | Runtime cost | Supabase lifecycle duplication | Local developer experience | CI parity | Required docs updates | Tests to update |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1. Add both scripts to `scripts/verify.sh` | High. Main local and CI gate both fail on backend write regressions. | High. `verify.sh` becomes noticeably slower. | High if scripts remain as-is because each script starts/resets/provisions again after `verify.sh` already did backend setup. | Mixed. One command catches everything, but repeated backend setup makes default verify heavier. | High. Same entrypoint local and CI. | `docs/testing/testing-strategy.md`, `README.md`, workflow docs if verify contract changes materially. | `scripts/tests/verify-test.sh`; possibly new helper-script tests if setup is refactored. |
| 2. Add dedicated CI job only | High for merge safety, medium for pre-push local safety because default local verify still misses regressions. | Medium overall. Cost isolated to CI job and can run in parallel. | Medium. Duplication stays in dedicated backend-contract job only. | Better short local runtime, worse because developers can get green local verify and still fail CI on backend contracts. | Low to medium. Local default workflow drifts from enforced CI path. | `docs/testing/testing-strategy.md`, workflow docs, README CI guidance. | CI workflow coverage tests if any, `scripts/tests/run-ci-locally-test.sh` if local CI mirror changes. |
| 3. Hybrid: shared backend-contract gate used by local verify and dedicated CI job | Highest. Local verify and CI both cover backend write contracts, while CI can still expose the contract suite as a distinct gate. | Medium. Cost stays visible, but can be controlled by sharing setup and avoiding duplicate execution in CI. | Low to medium if implementation adds one shared backend-contract entrypoint and CI avoids running the suite twice. | Best balance. Default local verify stays authoritative; explicit backend-contract job keeps failures easy to locate. | High. Repository can keep `./scripts/verify.sh` as primary local gate and still mirror CI through `./scripts/run-ci-locally.sh`. | `docs/testing/testing-strategy.md`, `docs/workflows/development-workflow.md`, `README.md`, deferred entry status/update. | `scripts/tests/verify-test.sh`, `scripts/tests/run-ci-locally-test.sh`, and tests for any new shared backend-contract script. |

## Recommendation

Adopt option 3: hybrid gating.

Repository should add one shared backend write-contract gate entrypoint, run it from `./scripts/verify.sh` by default, and also surface it as a dedicated CI job so failures remain isolated and visible. CI should avoid double-running the same suite by giving `verify.sh` a documented skip path when the dedicated backend-contract job is active.

This keeps release safety high without normalizing repeated Supabase start/reset/provision cycles across every gate invocation.

## Required Outcome

- local default verify covers both backend write-contract suites
- primary CI gate blocks merge on both backend write-contract suites
- CI-parity local runner exposes the same gate split
- repository docs describe actual gate behavior without overstating coverage
