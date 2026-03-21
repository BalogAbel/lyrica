# ADR-003: Riverpod

## Status

Accepted

## Context

The client needs explicit dependency wiring, testability, and predictable async state composition.

## Decision

Use Riverpod as the application state and dependency management solution.

## Consequences

- Better testability and dependency injection discipline
- Keeps state wiring explicit
- Requires team consistency in provider boundaries
