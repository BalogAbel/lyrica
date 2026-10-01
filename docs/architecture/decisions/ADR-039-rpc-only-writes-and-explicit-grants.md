# ADR-039: RPC-Only Writes Enforced by Grants and Explicit Privileges

**Status:** Accepted (2026-10-01; implemented on `fix/direct-dml-write-rpc-bypass`)
**Builds on:** ADR-007 (capability-based authorization with RLS), ADR-026
(RLS-protected read boundary)
**Corrects:** the "RLS denies direct DML" statements in ADR-026, ADR-027 and
ADR-038
**Context spec:** `docs/specs/2026-10-01-direct-table-dml-lockdown.md`
**Migration:** `supabase/migrations/202610010001_direct_table_dml_lockdown.sql`

## Context

Every write in the app goes through a `security definer` RPC that owns the
write contract: version checks, slug rules, derived song metadata, the
`plans.content_version` bump, and the invitation and redemption contracts.
The database did not enforce that path:

- `authenticated` held every table privilege, `TRUNCATE` included, on nine of
  the ten `public` tables.
- Six permissive `for all` policies let a capable member insert, update and
  delete `songs`, `plans`, `sessions`, `session_items`, `attachments` and
  `memberships` through the table API and `pg_graphql`, skipping the RPCs.
- `TRUNCATE` ignores RLS, so it was open regardless of policy.
- Supabase's default privileges gave every new `public` table, sequence and
  function to `anon`, `authenticated` and `service_role`.

Two details of the default-privilege mechanics shape the decision:

- The revoke in the Supabase guide names only `select, insert, update,
  delete`. A table created after it still gives `TRUNCATE`, `REFERENCES`,
  `TRIGGER` and `MAINTAIN` to all three roles.
- `PUBLIC` holds `EXECUTE` on new functions through a PostgreSQL-global
  default. A per-schema `revoke ... from public` cannot remove a global grant
  and is a no-op.

The write RPCs do not need any caller privilege: they are owned by `postgres`,
which owns the tables and has `BYPASSRLS`, and their `search_path` is pinned.

## Decision

1. **Grants.** `anon` and `authenticated` hold no privilege on the `public`
   tables except `SELECT` for `authenticated`, which is the ADR-026 read
   boundary. The migration revokes schema-wide, from every table and sequence
   in `public`, and grants `SELECT` back on the named tables only. A drifted
   database therefore keeps no stray grant. `service_role` keeps its grants on
   existing tables.
2. **Policies.** No permissive policy in `public` allows a write. The six
   `for all` policies are dropped, not narrowed to `for select`. Each was
   already covered by its table's select policy:
   - `has_capability` is true only for an organization in which the caller
     has an active membership, which is the `current_organization_ids()`
     predicate.
   - The `canEditSongs` roles are a subset of the `canViewSongs` roles.

   Explicit `false` deny policies, as on `invitations`, remain allowed.
3. **Default privileges.** For role `postgres` in schema `public`,
   `revoke all` on tables, sequences and functions from `anon`,
   `authenticated` and `service_role`. Local databases then match a hosted
   project whose Data API setting "Default privileges for new entities" is
   off. New tables and sequences start closed. New functions still give
   `PUBLIC` `EXECUTE` through the PostgreSQL-global default.
4. **Convention for every new `public` object:**
   - Enable RLS.
   - Grant `SELECT` to `authenticated` only if the client reads the table
     through the table API.
   - Never grant a write privilege to `anon` or `authenticated`.
   - Grant `service_role` explicitly where tests or operations need it.
   - Write through a `security definer` RPC owned by `postgres`, with a pinned
     `search_path`. Run `revoke all on function ... from public, anon,
     authenticated`, then grant `EXECUTE` to `authenticated`.
   - Grant nothing on sequences the RPCs use, because definer bodies run as
     the owner.
   - Grant `EXECUTE` to `service_role` explicitly on a function that
     operations or tests call with the service key. It is no longer a default.
   - Install extensions with `create extension ... with schema extensions`.
     Their objects are owned by `supabase_admin`, whose default ACL in `public`
     this decision cannot change and which leaves them writable by `anon`.
5. **Guards.** `scripts/tests/direct-table-dml-contract-test.sh` enumerates the
   catalog. The backend contract gate fails on any of these:
   - a table with a write grant, or a sequence with any grant, to `anon` or
     `authenticated`;
   - a write-permitting policy;
   - a default privilege for an API role;
   - a `security definer` function executable by `anon`;
   - a `public` object not owned by `postgres`;
   - a `public` table without RLS.

## Consequences

- RPC-only writes are a database property, so ADR-038's I2, I4 and I5 hold
  for every writer, not only for clients that use the RPCs.
- A feature that needs a new write path needs a new RPC. A direct table write
  from Flutter fails with `42501`.
- A new table is unreadable until its migration grants `SELECT`, and it is
  unusable by `service_role` until that is granted too. The same holds for
  `service_role` `EXECUTE` on a new function. The failure is loud and safe.
- `authenticated` can no longer take row locks with direct SQL
  (`SELECT ... FOR SHARE` or `FOR UPDATE` need `UPDATE`). PostgREST never
  issues them.
- The `PUBLIC` function default stays. The per-function revoke is still
  mandatory, and guard G4 checks it for definer functions.
- Contract suites that call RPCs as a user must `set local role
  authenticated`. Claims alone run as `postgres` and prove nothing about grants
  (`docs/testing/testing-strategy.md`).
- **Hosted project:** turn off "Default privileges for new entities" in the
  Data API settings. After deploying the migration, run the read-only check
  in the spec's D8.

## Rejected Alternatives

- **Narrow the `for all` policies to `for select`.** This changes no visible
  row, but each read would pay for a redundant `security definer` evaluation
  per row, and the policy names would misdescribe what they do.
- **Revoke grants only, keep the policies.** That leaves one layer: a later
  migration that re-grants a privilege by mistake would reopen the bypass for
  every capable member.
- **Drop the policies only, keep the grants.** RLS would then deny insert,
  update and delete, but `TRUNCATE` ignores RLS and would stay open.
- **Revoke the global `PUBLIC` function default** (`alter default privileges
  for role postgres revoke execute on functions from public`, without
  `in schema`). It reaches every schema `postgres` creates functions in,
  including extension installs. The per-function convention already covers
  the RPCs.
