# Supabase CLI Query Output Robustness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Supabase-backed repository tests resilient to CLI status and update text around `db query` JSON output.

**Architecture:** Add one small repository helper that extracts the first valid JSON value from Supabase CLI stdout, then reuse it in the affected shell regression tests. This keeps the CLI wrapper unchanged while hardening the test consumers that currently assume pristine JSON and a single envelope shape.

**Tech Stack:** Bash, Python 3, Supabase CLI

---

### Task 1: Lock The Mixed-Output Failure Mode

**Files:**
- Create: `scripts/tests/extract-supabase-json-test.sh`
- Create: `scripts/extract_supabase_json.py`

- [ ] **Step 1: Write the failing regression test**

Create a shell test with sample `supabase db query` output that includes a status prefix, a JSON object, and an update-notice suffix.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/extract-supabase-json-test.sh`
Expected: FAIL before the helper exists.

### Task 2: Implement Shared JSON Extraction

**Files:**
- Create: `scripts/extract_supabase_json.py`
- Modify: `scripts/tests/provision-local-demo-user-test.sh`
- Modify: `scripts/tests/membership-uniqueness-migration-test.sh`

- [ ] **Step 1: Add the minimal helper**

Implement a Python helper that reads stdin, finds the first valid JSON value, and writes normalized JSON to stdout.

- [ ] **Step 2: Switch the affected tests to the helper**

Update the Supabase-backed regression tests that parse `db query` stdout so they feed the raw CLI output through the helper before asserting on rows from either an object envelope or a top-level array.

- [ ] **Step 3: Run the focused regression test to verify it passes**

Run: `bash scripts/tests/extract-supabase-json-test.sh`
Expected: PASS

### Task 3: Verify Against Real Local Supabase

**Files:**
- Verify only

- [ ] **Step 1: Run the provisioning regression test**

Run: `bash scripts/tests/provision-local-demo-user-test.sh`
Expected: PASS against the local Supabase stack even with CLI notices present.

- [ ] **Step 2: Run the migration regression test**

Run: `bash scripts/tests/membership-uniqueness-migration-test.sh`
Expected: PASS against the local Supabase stack even with CLI notices present.
