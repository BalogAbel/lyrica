# Local-First Manual Validation Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add repository-owned scripts and docs for repeatable manual validation of the local-first authenticated song-reading slice.

**Architecture:** Keep the workflow thin and wrapper-driven. New scripts should compose existing repository entrypoints for Supabase start/reset/provisioning and add one app launcher that preserves state between runs. A dedicated shell test should verify the command contract without depending on a live local stack.
The launcher must also support offline relaunch by falling back to the last cached local Supabase `dart-define` snapshot when `./scripts/supabase.sh status -o env` is unavailable because the stack is intentionally stopped.
For ADB-managed Android devices, including wireless Flutter targets exposed through `adb-..._adb-tls-connect._tcp` ids and plain Android serials, the launcher should keep the loopback URL stable and establish `adb reverse` for the local Supabase port before invoking Flutter.
The workflow documentation should treat browser relaunch as diagnostic-only and native Flutter targets as the required acceptance path for authenticated offline relaunch, while keeping automated persistent-cache reopen proof in the `./scripts/verify.sh` path distinct from that manual acceptance walkthrough.

**Tech Stack:** Bash, Flutter CLI, repository Supabase wrapper scripts, shell tests, Markdown docs

---

### Task 1: Add The Manual Validation Script Contract

**Files:**
- Create: `scripts/manual-validation/setup-local-first.sh`
- Create: `scripts/manual-validation/reset-validation-state.sh`
- Create: `scripts/manual-validation/run-local-first-app.sh`
- Create: `scripts/manual-validation/go-offline.sh`
- Create: `scripts/manual-validation/go-online.sh`
- Create: `scripts/manual-validation/print-checklist.sh`
- Create: `scripts/tests/local-first-manual-validation-scripts-test.sh`

- [ ] **Step 1: Write the failing shell test**
- [ ] **Step 2: Run the shell test to verify it fails**
- [ ] **Step 3: Implement the scripts with repository wrapper usage**
- [ ] **Step 4: Re-run the shell test to verify it passes**

### Task 2: Document The Manual Validation Workflow

**Files:**
- Modify: `README.md`
- Modify: `apps/lyrica_app/README.md`
- Modify: `docs/workflows/development-workflow.md`
- Modify: `docs/specs/2026-03-25-local-first-manual-validation-scripts.md`

- [ ] **Step 1: Add the script entrypoints and intended use to repository docs**
- [ ] **Step 2: Re-read the updated docs for consistency**

### Task 3: Verify The Workflow

**Files:**
- Test: `scripts/tests/local-first-manual-validation-scripts-test.sh`

- [ ] **Step 1: Run the manual-validation shell test**
- [ ] **Step 2: Run `./scripts/verify.sh` because this slice changes the local Supabase workflow behavior**
