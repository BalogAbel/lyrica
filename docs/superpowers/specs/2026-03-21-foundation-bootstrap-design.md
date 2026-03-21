# Lyrica Foundation Bootstrap Design

## Goal

Establish a production-oriented repository foundation that is strong enough to guide architecture, product decisions, workflow, testing, and AI-assisted delivery without prematurely implementing product features.

## Recommended Approach

Create the repository as a documentation-first monorepo with a minimal but real Flutter application shell and a Supabase schema baseline. This keeps the foundation executable while preserving space for later iteration.

## Alternative Approaches Considered

### Approach A: Documentation-only bootstrap

Pros:

- Fastest setup
- Forces product and architecture thinking early

Cons:

- No executable foundation
- Higher drift risk between docs and implementation

### Approach B: Full vertical slice immediately

Pros:

- Faster user-visible progress
- Early end-to-end validation

Cons:

- Premature feature choices
- Higher chance of undocumented architecture

### Approach C: Foundation-first executable scaffold

Pros:

- Aligns code with docs early
- Keeps scope controlled
- Supports CI and TDD discipline from the start

Cons:

- Slightly more upfront work than docs-only

This repository uses Approach C.

## Design Summary

- Monorepo with a single Flutter application under `apps/`
- Supabase SQL migrations and policy helper stubs under `supabase/`
- ADRs for durable decisions
- Workflow docs for spec-plan-implement-test-doc loop
- Capability-based authorization documented and stubbed in SQL
- Drift-based offline foundation documented and represented in app structure

## Success Criteria

- Repository structure exists and is reviewable
- Core product/domain/architecture/testing/workflow docs exist with real content
- Flutter app compiles with architecture-aligned shell code
- Supabase baseline migration documents tenant, domain, and authorization foundations
- CI and scripts reflect intended developer workflow
