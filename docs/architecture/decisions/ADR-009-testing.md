# ADR-009: TDD And Strict Pre-Merge Verification

## Status

Accepted

## Context

AI-assisted development increases delivery speed, but it can also increase the risk of undocumented or weakly verified changes.

## Decision

Require TDD for behavior changes and strict pre-merge verification via analyze, tests, and migration checks.

## Consequences

- Better confidence in AI-assisted changes
- Slightly more upfront discipline required
- Testing strategy becomes part of project governance
