# Supabase Tooling Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Supabase CLI management into `tooling/supabase`, route all repository usage through a wrapper script, and align CI and documentation with the new workflow.

**Architecture:** Keep Supabase project files under `supabase/` and add a narrow Node tooling workspace under `tooling/supabase/`. Repository scripts should depend only on `scripts/supabase.sh`, which centralizes CLI resolution, dependency checks, and argument forwarding.

**Tech Stack:** POSIX shell, npm, npx, GitHub Actions, Supabase CLI

---

### Task 1: Baseline And Tooling Workspace

**Files:**
- Create: `tooling/supabase/package.json`
- Create: `tooling/supabase/package-lock.json`
- Modify: `.gitignore`

- [ ] **Step 1: Record the current Supabase invocation points**

Run: `rg -n "supabase|npx supabase|setup-cli" README.md AGENTS.md docs scripts .github --glob '!**/node_modules/**'`
Expected: direct CLI calls and CI setup references are listed.

- [ ] **Step 2: Create the dedicated tooling manifest**

Add a minimal `package.json` under `tooling/supabase` with `supabase` as a dev dependency.

- [ ] **Step 3: Install tooling dependencies and capture a lockfile**

Run: `npm ci --prefix tooling/supabase`
Expected: `tooling/supabase/package-lock.json` is generated.

- [ ] **Step 4: Ignore local tooling artifacts**

Update `.gitignore` so `tooling/supabase/node_modules/` remains local only.

### Task 2: Wrapper And Script Refactor

**Files:**
- Create: `scripts/supabase.sh`
- Modify: `scripts/supabase-start.sh`
- Modify: `scripts/db-reset.sh`
- Modify: `scripts/db-seed.sh`
- Modify: `scripts/check-migrations.sh`
- Modify: `scripts/verify.sh`
- Modify: `scripts/bootstrap.sh`

- [ ] **Step 1: Add the wrapper script**

Implement a concise POSIX shell wrapper that validates `node`/`npm`, checks `tooling/supabase/node_modules`, and forwards all arguments to `npx --prefix`.

- [ ] **Step 2: Update repository scripts to use the wrapper**

Replace direct `supabase` calls with `./scripts/supabase.sh ...`.

- [ ] **Step 3: Keep script ergonomics clean**

Add concise failure messages and align bootstrap/verify messaging with the new workflow.

### Task 3: CI And Documentation

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/workflows/development-workflow.md`

- [ ] **Step 1: Update CI**

Install dependencies under `tooling/supabase` and use repository scripts rather than direct CLI setup assumptions.

- [ ] **Step 2: Update repository guidance**

Document the Node prerequisite for tooling, canonical wrapper usage, and the rule against root-level Supabase CLI setup.

- [ ] **Step 3: Remove outdated references**

Search again for stale `supabase` invocation patterns and clean them up.

### Task 4: Verification

**Files:**
- Verify only

- [ ] **Step 1: Verify script wiring**

Run: `./scripts/supabase.sh --help`
Expected: CLI help text or command usage is displayed through the wrapper.

- [ ] **Step 2: Verify migration script pathing**

Run: `./scripts/check-migrations.sh`
Expected: the script reaches Supabase CLI via the wrapper and either lints successfully or fails for an environment-specific Supabase reason, not because the CLI is missing.

- [ ] **Step 3: Verify repository references**

Run: `rg -n "npx supabase|command -v supabase|supabase/setup-cli|Supabase CLI" README.md AGENTS.md docs scripts .github --glob '!**/node_modules/**'`
Expected: direct invocation patterns are gone except for the new documented tooling rules.
