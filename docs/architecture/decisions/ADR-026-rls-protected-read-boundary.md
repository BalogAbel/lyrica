# ADR-026: RLS-Protected Read Boundary

- Status: Accepted
- Date: 2026-07-29
- Spec: `docs/specs/2026-07-29-read-boundary-and-derived-song-metadata.md`
- Plan: `docs/plans/2026-07-29-read-boundary-and-derived-song-metadata.md`
- Closes: `docs/deferred/2026-05-16-auth-schema-lint-followups.md` (read-boundary half)

## Context

The auth-invite slice (`202605160007_auth_boundary_hardening.sql`) locked
down anonymous table access and security-definer RPC execution, but
deliberately left one question open: should `authenticated` keep table-level
`SELECT` on `songs`, `plans`, and `sessions`, given that the Flutter
repositories read them directly through the Supabase table API rather than
through an RPC?

Measured surface, verified against the repository rather than assumed:

| | count |
|---|---|
| direct table **reads** (`.from(...).select(...)`) | 8 |
| direct table **writes** | **0** |
| files containing them | 3, all under `lib/src/infrastructure/` |
| tables touched | `songs` (4), `plans` (3), `sessions` (1) |

Call sites: `supabase_song_repository.dart:19,26,34`,
`supabase_song_mutation_repository.dart:13`,
`supabase_planning_repository.dart:26,38,48,63`.

The write half of this question is already closed: there are zero direct
table writes, and every mutation goes through a `security definer` RPC with
RLS denying direct DML.

## Decision

The read boundary stays on RLS-protected table reads. No repository code
changes.

RLS is the enforcement layer today, and it would remain the enforcement layer
behind a `security_invoker` view or be **re-implemented** inside a read RPC.
Replacing the reads changes who spells the query, not who enforces access —
a hand-written tenant predicate in each read RPC is a second place to get it
wrong.

The eight reads feed the local-first projection sync, which the repository
review's own §6 identifies as the highest-risk subsystem in the codebase.
Rewriting them buys no authorization guarantee and spends risk where there is
least margin.

**Consequence, stated plainly:** `authenticated` keeps table `SELECT`, so the
PostgREST and `pg_graphql` surfaces stay reachable — RLS-scoped, but
reachable. That is the accepted trade.

## Rejected alternatives

**`security_invoker` views** (available on PostgreSQL 17.6). Would narrow the
exposed surface without adding authorization logic, and is the strongest of
the alternatives considered. Rejected because the benefit is defence in
depth against a surface RLS already governs, while the cost lands on three
repositories and the projection-sync tests, and every future column has to be
tracked in two places (the table and the view).

**Read RPCs.** Tightest against table exposure, but duplicates the tenant
predicate per RPC, discards PostgREST's column-projection behaviour, and
rewrites the riskiest subsystem in the repository for no additional
authorization guarantee — RLS already enforces the predicate a hand-written
RPC would have to reimplement.

## Consequences

- No Flutter repository changes; no projection-sync test changes.
- The three read repositories continue to read `songs`, `plans`, and
  `sessions` directly through the Supabase table API under RLS.
- A future slice that wants to narrow the PostgREST/`pg_graphql` surface
  further should revisit `security_invoker` views first, since it was judged
  the strongest of the rejected alternatives — not because this ADR expects
  that to happen.
