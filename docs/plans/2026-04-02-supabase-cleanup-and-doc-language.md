# Supabase Cleanup And Doc Language Implementation Plan

> Status: Implemented

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repository-owned Supabase stop convenience entrypoint and convert the remaining Hungarian repository spec content to English.

**Architecture:** Keep the existing `./scripts/supabase.sh` wrapper as the canonical CLI boundary and add one focused convenience script beside it. The new script should stop the currently configured local Supabase project by delegating to the wrapper, without introducing additional Docker cleanup policy. Documentation should describe the new command and keep specs and plans fully English without changing product behavior.

**Tech Stack:** Bash, Docker CLI, Supabase CLI wrapper, shell tests, Markdown

---

### Task 1: Capture The Stop Convenience Workflow In Tests

**Files:**
- Create: `scripts/tests/supabase-cleanup-test.sh`

- [x] **Step 1: Write the failing shell test**
- [x] **Step 2: Run the test to verify it fails because the cleanup script does not exist yet**
- [x] **Step 3: Assert the script delegates directly to `./scripts/supabase.sh stop`**
- [x] **Step 4: Keep the test scoped to the convenience-wrapper behavior**
- [x] **Step 5: Avoid introducing extra Docker cleanup policy into the script contract**

### Task 2: Implement The Repository Stop Entrypoint

**Files:**
- Create: `scripts/supabase-cleanup.sh`

- [x] **Step 1: Reuse `./scripts/supabase.sh` as the only Supabase CLI boundary**
- [x] **Step 2: Stop the current stack through `./scripts/supabase.sh stop`**
- [x] **Step 3: Keep the script focused on convenience rather than Docker-resource policy**
- [x] **Step 4: Preserve idempotent stop behavior through the underlying wrapper**
- [x] **Step 5: Avoid changing repository cleanup behavior beyond the dedicated stop entrypoint**

### Task 3: Document The New Cleanup Command

**Files:**
- Modify: `README.md`
- Modify: `docs/workflows/development-workflow.md`

- [x] **Step 1: Add `./scripts/supabase-cleanup.sh` to the common command lists**
- [x] **Step 2: Document that the script stops the current stack through the wrapper**
- [x] **Step 3: Keep the docs aligned with the repository wrapper-script guidance**

### Task 4: Convert Remaining Hungarian Spec Content To English

**Files:**
- Modify: `docs/specs/2026-03-26-mobile-and-tablet-reader-navigation.md`

- [x] **Step 1: Translate every remaining Hungarian sentence, bullet, and heading fragment to English**
- [x] **Step 2: Preserve the original product meaning and status metadata**
- [x] **Step 3: Re-scan the file to confirm no Hungarian prose remains**

### Task 5: Verify The Slice

**Files:**
- Test: `scripts/tests/supabase-cleanup-test.sh`

- [x] **Step 1: Run `bash scripts/tests/supabase-cleanup-test.sh`**
- [x] **Step 2: Run the existing shell regression tests that cover neighboring Supabase workflow behavior**
- [x] **Step 3: Run `./scripts/verify.sh --skip-migrations` only if the shell/documentation changes do not require the full backend-backed gate**
