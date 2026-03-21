# ADR-002: Monorepo

## Status

Accepted

## Context

Architecture, schema, workflow, and product decisions must evolve together and stay versioned.

## Decision

Use a monorepo with top-level `apps/`, `supabase/`, `docs/`, `scripts/`, and `.github/` folders.

## Consequences

- Shared visibility of app, backend, and docs changes
- Easier cross-cutting review
- Requires clear boundaries to avoid coupling
