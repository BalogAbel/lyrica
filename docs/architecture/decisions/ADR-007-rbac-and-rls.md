# ADR-007: Capability-Based Authorization With RLS

## Status

Accepted

## Context

The product is multi-tenant and must enforce organization and group boundaries securely.

## Decision

Use Supabase Auth for identity, Postgres RLS for enforcement, and SQL functions to map memberships and roles into capabilities.

## Consequences

- Backend remains the authority for access control
- Frontend can remain focused on UX affordances
- Policy changes require disciplined SQL migrations and tests
