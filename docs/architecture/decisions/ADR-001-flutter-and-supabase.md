# ADR-001: Flutter And Supabase

## Status

Accepted

## Context

The product must ship on Android, iOS, and Web with strong shared domain behavior and a cloud-backed backend.

## Decision

Use Flutter for the client application and Supabase for backend identity, database, and policy enforcement.

## Consequences

- Shared client behavior across MVP platforms
- Fast backend bootstrap using managed Postgres and Auth
- Requires clear handling of web-specific offline storage constraints
- Authorization remains database-centric instead of client-centric
