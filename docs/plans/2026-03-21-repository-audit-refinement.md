# Repository Audit And Refinement Implementation Plan

> Execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audit the bootstrapped repository, remove noise, align code/docs/schema/CI, and leave a reliable foundation without rebuilding the project.

**Architecture:** Work from the repository boundaries inward: first make the repository self-explanatory, then align database authorization and offline invariants, then tighten the Flutter shell and verification workflow. Prefer simplification over adding new abstractions.

**Tech Stack:** Flutter, Riverpod, go_router, Drift, Supabase, PostgreSQL RLS, GitHub Actions, shell scripts

---

### Task 1: Repository And Documentation Audit

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `apps/lyrica_app/README.md`
- Modify: `docs/product/vision.md`
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/workflows/development-workflow.md`
- Modify: `docs/workflows/ai-development.md`
- Modify: `docs/integrations/freeshow.md`
- Modify: `docs/architecture/decisions/*.md`
- Create: `docs/plans/2026-03-21-repository-audit-refinement.md`

- [ ] Step 1: Remove placeholder or tool-only wording from repository docs.
- [ ] Step 2: Ensure architecture, domain, authorization, offline, and workflow rules are fully described in vendor-neutral repository files.
- [ ] Step 3: Align app-level README and repository setup guidance with the actual monorepo structure.

### Task 2: Schema And Authorization Hardening

**Files:**
- Modify: `supabase/migrations/202603210001_initial_schema.sql`
- Modify: `supabase/seed/seed.sql`
- Modify: `scripts/check-migrations.sh`

- [ ] Step 1: Add failing verification coverage for the SQL invariants that are currently underdefined.
- [ ] Step 2: Tighten multi-tenant constraints, capability helpers, and RLS policies so organization and group scope are enforced consistently.
- [ ] Step 3: Make migration verification realistic in local development and CI.

### Task 3: Flutter Shell Simplification

**Files:**
- Modify: `apps/lyrica_app/lib/src/...`
- Modify: `apps/lyrica_app/test/...`
- Modify: `apps/lyrica_app/pubspec.yaml`

- [ ] Step 1: Replace bootstrap-demo messaging with architecture-aligned, minimal shell behavior.
- [ ] Step 2: Keep Riverpod, routing, and offline contracts, but remove fake or redundant abstraction where it adds no value.
- [ ] Step 3: Add or update tests so the shell documents the intended boundaries.

### Task 4: CI, Scripts, And Final Consistency Pass

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `scripts/*.sh`
- Modify: repository docs touched by verification outcomes

- [ ] Step 1: Make CI match the documented quality gates without overengineering.
- [ ] Step 2: Improve developer scripts so local setup and validation are explicit and repeatable.
- [ ] Step 3: Run verification, reconcile any last naming or documentation drift, and leave the repository in a coherent state.
