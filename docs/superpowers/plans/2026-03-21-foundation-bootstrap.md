# Lyrica Foundation Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a repository foundation that captures architecture, domain, workflow, testing, and AI-development rules while providing a minimal executable Flutter and Supabase baseline.

**Architecture:** Documentation is created first to anchor decisions, then the Flutter shell and Supabase baseline are aligned to those decisions. CI, scripts, and tests complete the foundation so later feature work starts from explicit constraints.

**Tech Stack:** Flutter, Riverpod, go_router, Drift, Supabase, PostgreSQL RLS, GitHub Actions, shell scripts

---

### Task 1: Repository Foundation

**Files:**
- Create: `README.md`
- Create: `AGENTS.md`
- Create: `.gitignore`
- Create: `melos.yaml`

- [ ] Step 1: Write repository-level documents and root config.
- [ ] Step 2: Verify structure reflects the intended monorepo.
- [ ] Step 3: Commit foundation docs.

### Task 2: Product, Domain, Architecture, and Workflow Docs

**Files:**
- Create: `docs/product/vision.md`
- Create: `docs/domain/domain-model.md`
- Create: `docs/architecture/architecture.md`
- Create: `docs/testing/testing-strategy.md`
- Create: `docs/workflows/ai-development.md`
- Create: `docs/workflows/development-workflow.md`
- Create: `docs/integrations/freeshow.md`

- [ ] Step 1: Capture durable product and system decisions.
- [ ] Step 2: Document offline, authorization, and ChordPro constraints.
- [ ] Step 3: Commit documentation set.

### Task 3: Architectural Decision Records

**Files:**
- Create multiple files under `docs/architecture/decisions/`

- [ ] Step 1: Record core technology and workflow choices as ADRs.
- [ ] Step 2: Ensure each ADR includes context, decision, and consequences.
- [ ] Step 3: Commit ADRs.

### Task 4: Flutter Shell Via TDD

**Files:**
- Modify: `apps/lyrica_app/pubspec.yaml`
- Modify: `apps/lyrica_app/lib/main.dart`
- Create: `apps/lyrica_app/lib/src/...`
- Create: `apps/lyrica_app/test/...`

- [ ] Step 1: Add tests describing app bootstrap, routing, and offline foundation surfaces.
- [ ] Step 2: Run tests to verify they fail.
- [ ] Step 3: Implement the minimal architecture-aligned Flutter shell.
- [ ] Step 4: Run tests to verify green.
- [ ] Step 5: Commit Flutter shell.

### Task 5: Supabase Baseline

**Files:**
- Create: `supabase/config.toml`
- Create: `supabase/migrations/202603210001_initial_schema.sql`
- Create: `supabase/seed/seed.sql`

- [ ] Step 1: Define tenant, membership, content, planning, and attachment tables.
- [ ] Step 2: Add capability helper function stubs and baseline RLS policies.
- [ ] Step 3: Commit Supabase baseline.

### Task 6: CI, Scripts, and Verification

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `scripts/*.sh`

- [ ] Step 1: Add developer entrypoint scripts.
- [ ] Step 2: Add CI workflow for analyze, tests, and migration checks.
- [ ] Step 3: Run local verification.
- [ ] Step 4: Commit final bootstrap state.
