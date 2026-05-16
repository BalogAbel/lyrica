# Auth Schema Lint Follow-ups

## Context

The auth invite slice hardens anonymous access by revoking anon table access,
locking down security-definer RPC execution, and setting explicit function
`search_path` values for slice-owned helpers.

## Deferred Items

- `authenticated` GraphQL/table exposure remains intentionally unresolved in
  this slice. The Flutter repositories currently read `songs`, `plans`, and
  `sessions` directly through Supabase table APIs, with RLS enforcing tenant
  visibility. Removing authenticated table `SELECT` requires a separate read
  boundary redesign using read RPCs or controlled views.
- `unaccent` remains installed in `public`. Moving extensions out of `public`
  is database hygiene, but it requires a coordinated `slugify` migration and
  verification. It is not required to close the invite/auth boundary.

## Acceptance Criteria for a Future Slice

- Replace direct authenticated table reads with explicit read RPCs or views, or
  document why RLS-protected table reads remain the chosen architecture.
- Move `unaccent` to an extension schema and update `public.slugify` to call it
  through an explicit schema-qualified reference.
