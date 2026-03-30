# Provisioned Demo User Visibility Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize the demo-user provisioning regression check against short-lived post-provision visibility lag in CI.

**Architecture:** Keep the current provisioning script unchanged and harden only the regression check. Make the test script configurable for mocks, add a short retry loop around the membership query, and emit targeted diagnostics when the retry budget is exhausted.

**Tech Stack:** Bash, Python 3, Supabase CLI

---

### Task 1: Lock The Retry Contract With A Failing Script Test

**Files:**
- Create: `scripts/tests/provision-local-demo-user-script-test.sh`
- Modify: `scripts/tests/provision-local-demo-user-test.sh`

- [ ] **Step 1: Write the failing mock-driven test**

Create a script test that injects mock Supabase, reset, provision, and sleep commands. Make the membership query return empty rows twice and then a valid count on the third attempt.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/provision-local-demo-user-script-test.sh`
Expected: FAIL before the provision regression script supports retries and dependency injection.

### Task 2: Add Bounded Retry And Diagnostics

**Files:**
- Modify: `scripts/tests/provision-local-demo-user-test.sh`
- Test: `scripts/tests/provision-local-demo-user-script-test.sh`

- [ ] **Step 1: Add environment-overridable entrypoints**

Allow the regression script to override the Supabase, reset, provision, and sleep commands through environment variables so the retry behavior is testable without Docker.

- [ ] **Step 2: Add the retry window**

Retry the membership query a small fixed number of times with a short delay, stopping early as soon as the expected count can be parsed.

- [ ] **Step 3: Add final diagnostics**

If all attempts fail, print targeted `auth.users` and membership query diagnostics before exiting non-zero.

- [ ] **Step 4: Run the mock test to verify it passes**

Run: `bash scripts/tests/provision-local-demo-user-script-test.sh`
Expected: PASS

### Task 3: Verify Against Real Local Supabase

**Files:**
- Verify only

- [ ] **Step 1: Run the real provision regression**

Run: `bash scripts/tests/provision-local-demo-user-test.sh`
Expected: PASS against the local Supabase stack.
