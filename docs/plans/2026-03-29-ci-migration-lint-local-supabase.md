# CI Migration Lint Local Supabase Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make migration lint reliable in CI and local usage by having the repository entrypoint start or reuse local Supabase before `db lint`.

**Architecture:** Keep the bootstrap behavior inside `scripts/check-migrations.sh` so both GitHub Actions and local developers use the same contract. Protect that contract with a focused shell regression test and document it in the repository workflow references.

**Tech Stack:** Bash, Python 3, GitHub Actions, Supabase CLI wrapper

---

### Task 1: Lock The Desired Script Contract With A Failing Test

**Files:**
- Create: `scripts/tests/check-migrations-test.sh`
- Test: `scripts/check-migrations.sh`

- [ ] **Step 1: Write the failing regression test**

Create a shell test that injects a mock `SUPABASE_SCRIPT`, runs `scripts/check-migrations.sh`, and expects the log sequence `supabase:start` then `supabase:db lint`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/check-migrations-test.sh`
Expected: FAIL because the current script only calls `db lint`.

### Task 2: Make The Migration Entrypoint Self-Bootstrapping

**Files:**
- Modify: `scripts/check-migrations.sh`
- Modify: `scripts/verify.sh`
- Test: `scripts/tests/check-migrations-test.sh`
- Test: `scripts/tests/verify-test.sh`

- [ ] **Step 1: Add the minimal implementation**

Update `scripts/check-migrations.sh` to resolve `SUPABASE_SCRIPT` like the other repository scripts and call `"$supabase_script" start` before `"$supabase_script" db lint`. Remove the now-redundant explicit `start` call from `scripts/verify.sh` so the broader verification flow reuses the same script contract.

- [ ] **Step 2: Run the regression tests to verify they pass**

Run: `bash scripts/tests/check-migrations-test.sh`
Expected: PASS with the ordered `start` then `db lint` calls.

Run: `bash scripts/tests/verify-test.sh`
Expected: PASS without a redundant second `supabase:start` entry after `check-migrations`.

### Task 3: Refresh Durable Repository Guidance

**Files:**
- Modify: `README.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/workflows/development-workflow.md`
- Create: `docs/specs/2026-03-29-ci-migration-lint-local-supabase.md`
- Create: `docs/plans/2026-03-29-ci-migration-lint-local-supabase.md`

- [ ] **Step 1: Document the script contract**

Update repository guidance so `./scripts/check-migrations.sh` is described as starting or reusing local Supabase before linting, and clarify that CI relies on the same script contract.

- [ ] **Step 2: Save the spec and plan**

Record the decision and implementation path in vendor-neutral repository docs under `docs/specs/` and `docs/plans/`.

### Task 4: Verify The End-To-End Change

**Files:**
- Verify only

- [ ] **Step 1: Run the focused regression test**

Run: `bash scripts/tests/check-migrations-test.sh`
Expected: PASS

- [ ] **Step 2: Run the broader repository script verification**

Run: `bash scripts/tests/verify-test.sh`
Expected: PASS
