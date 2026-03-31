# Local CI Entrypoint Implementation Plan

> Status: Implemented

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single local command that mirrors the repository's current GitHub Actions jobs and their script ordering.

**Architecture:** Keep the new entrypoint as a thin shell wrapper around `bootstrap.sh`, `bootstrap-supabase.sh`, `verify.sh`, and `check-migrations.sh`. Validate dispatch behavior with a focused script test that swaps in mock scripts through environment overrides.

**Tech Stack:** Bash, Python 3, GitHub Actions workflow parity

---

### Task 1: Lock The Intended Dispatch Contract

**Files:**
- Create: `scripts/tests/run-ci-locally-test.sh`
- Create: `scripts/run-ci-locally.sh`
- Create: `scripts/bootstrap-supabase.sh`

- [ ] **Step 1: Write the failing regression test**

Create a shell test that injects mock bootstrap, verify, and migration scripts, then asserts the call sequence for `all`, `verify`, and `migrations`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/run-ci-locally-test.sh`
Expected: FAIL because the new entrypoint does not exist yet.

### Task 2: Add The Local CI Wrapper

**Files:**
- Create: `scripts/run-ci-locally.sh`
- Test: `scripts/tests/run-ci-locally-test.sh`

- [ ] **Step 1: Add the minimal wrapper**

Implement `./scripts/run-ci-locally.sh` with `all`, `verify`, and `migrations` modes that call the existing repository scripts in CI order, and add `./scripts/bootstrap-supabase.sh` as the local equivalent of the migrations job's tooling install step.

- [ ] **Step 2: Run the script test to verify it passes**

Run: `bash scripts/tests/run-ci-locally-test.sh`
Expected: PASS

### Task 3: Update Durable Workflow Guidance

**Files:**
- Modify: `README.md`
- Modify: `docs/workflows/development-workflow.md`
- Create: `docs/specs/2026-03-29-local-ci-entrypoint.md`
- Create: `docs/plans/2026-03-29-local-ci-entrypoint.md`

- [ ] **Step 1: Document the local CI command**

Add `./scripts/run-ci-locally.sh` to the workflow guidance and explain the available modes briefly.
