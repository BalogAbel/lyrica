# Direct Table DML Lockdown

> Status: Implemented (2026-10-01)

**Branch:** `fix/direct-dml-write-rpc-bypass`
**Roadmap slice:** S1 in `docs/plans/2026-10-01-delivery-roadmap.md`
**Deferred source:** `docs/deferred/2026-09-30-direct-dml-bypasses-write-rpcs.md`
(resolved and removed by this slice)
**ADR:** ADR-039, `docs/architecture/decisions/ADR-039-rpc-only-writes-and-explicit-grants.md`
**Plan:** `docs/plans/2026-10-01-direct-table-dml-lockdown.md`

## Implementation

Commits, in landed order (spec, plan and docs-only commits left out):

- `0af99cd` test(backend): contract suites impersonate the authenticated role
- `61d3b85` test(backend): red -- direct table DML is denied to authenticated
- `085db4a` fix(backend): revoke direct table DML and default privileges
- `2248f6f` test(backend): guard sequences, ownership and RLS on public objects
- `b0d05be` fix(backend): revoke table and sequence privileges schema-wide

Execution notes:

- **D5 found five fixture writes made as the user.** They moved to the
  `postgres` path with their assertions unchanged:
  - three simulated remote song deletes and an attachment fixture in
    `song-crud-write-contract-test.sh`;
  - the SEC-5 unique-index probe in `planning-write-contract-test.sh`.
    Under the real role, PostgreSQL omits a unique violation's key `DETAIL`
    for a user subject to RLS, which is how the probe surfaced.
- **D5 also broke race R6 of the cascade-delete suite.** That was a harness
  artifact, not a behaviour change. The race detector finds the waiter in
  `pg_stat_activity` by a tag comment, and `pg_stat_activity.query` is cut at
  `track_activity_query_size` (1 kB locally). The tag sat after the
  statement, at byte offsets 843–1023 across R1–R6. The new
  `set local role` line pushed R6's tag past the cut. The tag now precedes the
  statement, so its offset no longer depends on the statement's length.
- **Before the migration** the new suite failed exactly on G1, G2, G3, B1 and
  B2, and passed G4, B3 and B4. As `authenticated`, `TRUNCATE` on
  `session_items` and `memberships` succeeded, bypassing RLS.
- **Guard check:** with `EXECUTE` on `create_plan` revoked from
  `authenticated`, the planning suite now fails with
  `permission denied for function create_plan`. Before D5 it would have
  passed, running as `postgres`.
- **Lint:** `supabase db lint` reports only the existing warning in
  `get_my_capabilities` (migration `202605280001`, `text` to `text[]`).
- **Hosted deployment (2026-10-01):**
  - "Automatically expose new tables" is off.
  - The migration was applied by hand in the SQL editor, wrapped in
    `begin;` ... `commit;`, after a pre-check that the six policies exist.
  - The D8 check and an app smoke test (reads plus RPC writes) passed.
- **Review gate 1** (adversarial whole-diff review, one claim to disprove):
  - **Held:** grants, policies, read visibility and the RPCs. A containment
    probe over suspended and invited admins, group-scoped roles and a
    group-scoped plan found no row visible only through a dropped policy.
  - **Eight minor findings, all addressed:**
    - extensions created in `public` (D4, G5);
    - the `PUBLIC` function default (wording in Goals and ADR-039);
    - `service_role` `EXECUTE` on new functions (D4);
    - row locks by `authenticated` (Non-Goals);
    - the schema-wide revoke (D1);
    - sequences in G1;
    - an RLS-enabled guard (G6);
    - row sets instead of counts in B3.

## Problem

`authenticated` can write the application tables through the table API
(`/rest/v1/...`) and through `pg_graphql` mutations. Five tables carry a
`for all` RLS policy keyed on a capability, and `memberships` carries one keyed
on `can_manage_membership`. A capable member can therefore skip the RPC write
contract: version checks, slug rules, derived song metadata, the
`plans.content_version` bump (ADR-038 invariants I2, I4, I5), and for
`memberships` the invitation and redemption contracts with their audit trail
(ADR-018, ADR-025). The deferred document has the reproduction.

Supabase also grants privileges on every new `public` object to `anon`,
`authenticated` and `service_role` by default. Fixing only today's tables would
leave the personal-layer tables planned in S3 open again.

## Verified Facts

Checked on 2026-10-01 against a local database at migration `202609290001`
(PostgreSQL 17.6).

1. **Table grants.** All ten `public` tables (`organizations`, `groups`,
   `memberships`, `songs`, `plans`, `sessions`, `session_items`,
   `attachments`, `invitations`, `invitation_redemption_attempts`) are owned
   by `postgres`. `authenticated` holds `arwdDxtm` (every table privilege,
   including `TRUNCATE`) on nine of them and only `r` on
   `invitation_redemption_attempts`. `anon` holds nothing (migration
   `202605160007` revoked it). `service_role` holds `arwdDxtm`.
2. **Policies.** Six permissive `for all` policies exist:
   `memberships are manageable by capability`,
   `songs are editable with song edit capability`,
   `plans are editable with plan capability`,
   `sessions are editable with session capability`,
   `session items inherit session edit capability`,
   `attachments are editable to song editors`.
   `invitations` and `invitation_redemption_attempts` already have explicit
   `false` insert, update and delete policies. `organizations` and `groups`
   have only select policies.
3. **`TRUNCATE` ignores RLS.** `authenticated` can truncate nine tables
   regardless of policy. PostgREST and `pg_graphql` expose no truncate, so this
   is reachable only from a SQL session running as `authenticated`, but it is
   the same unwanted grant.
4. **Default privileges.** `pg_default_acl` for role `postgres` in schema
   `public` grants `arwdDxtm` on tables, `rwU` on sequences and `X` on
   functions to `anon`, `authenticated` and `service_role`.
5. **The documented revoke is incomplete.** The statement in the Supabase
   guide "Securing your API" (checked via Context7 on 2026-10-01) revokes only
   `select, insert, update, delete` on tables. A probe table created after it
   still gave `anon`, `authenticated` and `service_role` `Dxtm`, including
   `TRUNCATE`.
6. **Per-schema function revoke from `PUBLIC` is a no-op.** PostgreSQL adds
   per-schema default privileges to the global ones and cannot subtract a
   global grant per schema. After
   `alter default privileges for role postgres in schema public revoke execute on functions from public`,
   a probe function still had a `NULL` ACL, which means `PUBLIC` keeps
   `EXECUTE`.
7. **Write RPCs do not depend on caller grants.** Every write RPC is
   `security definer`, owned by `postgres`, with `search_path` pinned. `postgres`
   is not a superuser but has `BYPASSRLS` and owns the tables. Helpers called
   from inside a definer body (`bump_plan_content_version`,
   `record_invitation_redemption_attempt`, `slugify`, the
   `chordpro_derive_*` family) run with the definer's privileges.
8. **Existing contract tests never run as `authenticated`.** The planning,
   cascade-delete, song CRUD, derived-metadata and read-only-role suites set
   only `request.jwt.claim.sub` and `request.jwt.claim.role`, then run as
   `postgres`. A revoke would leave them green without proving anything about
   the real role. Only the invitation, service-role-gate and capability
   suites use `set local role`.
9. **No fixture writes as `authenticated`.**
   - `supabase/seed/seed.sql`, `scripts/db-seed.sh` and
     `scripts/provision-local-demo-user.sh` write through
     `./scripts/supabase.sh db query`, which runs as `postgres`.
   - The Flutter integration tests write with `serviceRoleClient`
     (`authenticated_song_reader_flow_test.dart`); their user clients only
     read.
   - The manual-validation scripts do not touch the database.
   - `supabase/snippets/auth_invite_tests.sql` only reads while it runs as
     `authenticated`.
   - The Flutter app makes no direct table writes; `.from(...)` is used only
     for reads (ADR-026).
10. **Function grants are already explicit.** Every `security definer`
    function in `public` has had `public`, `anon` and `authenticated` revoked
    and `authenticated` re-granted where it is an RPC. Only two invoker
    functions keep `PUBLIC` execute: `set_updated_at()` (a trigger function)
    and `get_my_capabilities(uuid, uuid)`.
11. **RPCs with no contract coverage:** `delete_account()` and
    `get_my_capabilities(uuid, uuid)`.

## Goals

- `anon` and `authenticated` hold no write privilege of any kind on any
  `public` table: no `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`,
  `TRIGGER` or `MAINTAIN`.
- No permissive RLS policy in `public` allows a write, so RLS denies direct
  writes even if a grant comes back by mistake.
- New tables, sequences and functions created by `postgres` in `public` start
  with no grant to `anon`, `authenticated` or `service_role`. Functions keep
  `PUBLIC` `EXECUTE` (fact 6), which each function migration revokes itself.
- Every row each role can read today stays readable, and nothing else becomes
  readable.
- Every write RPC keeps working when called as the real `authenticated` role.

## Non-Goals

- **The read boundary.** ADR-026 stands: `authenticated` keeps `SELECT`, and
  RLS scopes reads.
- **`service_role` on existing tables.** It keeps its grants. The integration
  tests and operational scripts rely on them.
- **The global `PUBLIC` function default.** Revoking it needs
  `alter default privileges for role postgres revoke execute on functions from public`
  without `in schema`, which reaches every schema `postgres` creates functions
  in, including extension installs. The per-function convention (fact 10)
  plus guard G4 covers it instead.
- **Other roles' default privileges.** `supabase_admin` has its own default
  ACL in `public`, and `postgres` is not a member of `supabase_admin`, so it
  cannot change that ACL. A `postgres` migration still creates
  `supabase_admin`-owned objects through `create extension`. Installed into
  `public`, they would take that ACL: review gate 1 showed
  `address_standardizer_data_us` creating tables with RLS off that `anon`
  could delete from. D4 therefore installs extensions into `extensions`, and
  G5, G1 and G6 catch a violation.
- **Row locks by `authenticated`.** `SELECT ... FOR SHARE` and `FOR UPDATE`
  need `UPDATE` privilege, so `authenticated` can no longer take row locks with
  direct SQL. PostgREST never issues them, and the app does not use them.
- **The `storage`, `graphql` and `graphql_public` schemas.** Not application
  tables.
- **Flutter code.** No change.

## Design

### D1. Table grants

```sql
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
grant select on table <the ten tables of fact 1> to authenticated;
```

- **The revoke is schema-wide.** A drifted hosted database then loses the API
  roles' privileges on every table, view and sequence in `public`, not only
  on the ten known tables.
- **The grant is explicit.** `SELECT` comes back only on tables this migration
  names.
- Guard G1 enumerates every relation, so a later table that needs
  `SELECT` and lacks it fails the suite.

Review gate 1 suggested the schema-wide revoke. In a rolled-back probe, a
drift table and its sequence kept `INSERT` and `UPDATE` under the
explicit-list revoke and lost them under the schema-wide one.

### D2. Write policies

Drop the six `for all` policies. Do not recreate them as `for select`: each is
already covered by a select policy, so dropping them changes no visible row.

- `plans`, `sessions`, `session_items`: the edit policy uses
  `has_capability(organization_id, ...)`. `has_capability` returns true only
  when `auth.uid()` has an active membership whose `organization_id` equals
  its argument. That makes the row's organization a member of
  `current_organization_ids()`, which is the select policy.
- `memberships`: `can_manage_membership` calls `has_capability` on the row's
  organization, so the same argument applies.
- `songs`, `attachments`: the edit and view policies both call
  `has_capability(organization_id, cap)` with no group, so both resolve the
  same top-priority organization-scope role. The `canEditSongs` role set is a
  subset of the `canViewSongs` set.

Dropping them also removes a second `security definer` evaluation per row from
every song, plan and session read.

The explicit `false` write policies on `invitations` and
`invitation_redemption_attempts` stay. They are a correct second layer.

After D2, no permissive insert, update or delete policy exists in `public`.
Re-adding a grant by mistake then still fails: an insert raises
`new row violates row-level security policy`, and an update or delete matches
zero rows.

### D3. Default privileges

```sql
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated, service_role;
```

- **`revoke all`, not the four documented privileges** (fact 5). Otherwise
  every new table would still give `TRUNCATE`, `REFERENCES`, `TRIGGER` and
  `MAINTAIN` to all three roles.
- **`service_role` is included** for parity with the hosted Data API toggle
  "Default privileges for new entities" and with the Supabase guide. Local and
  hosted then start a new table in the same state. A new table that needs
  `service_role` grants it explicitly.
- **Functions:** this removes the explicit `anon`, `authenticated` and
  `service_role` defaults. `PUBLIC` keeps `EXECUTE` (fact 6), so the existing
  convention stays mandatory: every function migration runs
  `revoke all on function ... from public, anon, authenticated` and then
  grants exactly what it needs.

### D4. Convention for new `public` objects

ADR-039 records this, and `docs/architecture/architecture.md` points to it:

- Enable RLS.
- `grant select ... to authenticated` only if the client reads the table
  through the table API; never `insert`, `update`, `delete` or `truncate` to
  `anon` or `authenticated`.
- `grant ... to service_role` explicitly when tests or operations need it.
- Add no permissive `for all`, `insert`, `update` or `delete` policy. An
  explicit `false` deny policy is allowed.
- Writes go through a `security definer` RPC owned by `postgres`, with a
  pinned `search_path`, with `public`, `anon` and `authenticated` revoked and
  `authenticated` granted.
- Grants for a sequence the RPCs use are not needed: definer bodies run as the
  owner.
- A function that operations or tests call as `service_role` grants it
  `EXECUTE` explicitly. Since D3, `service_role` no longer gets it by default
  (review gate 1). `create_invitation` already grants it explicitly.
- Extensions go into the `extensions` schema
  (`create extension ... with schema extensions`). Their objects are owned by
  `supabase_admin` and would otherwise take its default ACL in `public`.

### D5. Contract tests impersonate the real role

Every contract-suite helper that impersonates a user adds
`set local role authenticated;` after the JWT claim setup, so RPC calls run
under the real role (fact 8). Affected:

- `scripts/tests/planning-write-contract-test.sh` (`run_psql`)
- `scripts/tests/planning-cascade-delete-contract-test.sh` (`run_psql` and the
  race-waiter session setup)
- `scripts/tests/song-crud-write-contract-test.sh` (both claim blocks)
- `scripts/tests/song-derived-metadata-contract-test.sh` (`run_psql`)
- `scripts/tests/organization-read-only-role-test.sh` (`run_sql_as_user`)

A call made without a user id stays `postgres`. That is the fixture path.
Each changed suite must still pass against the pre-migration schema before the
migration lands. If a suite then fails because it wrote fixtures as the user,
that fixture moves to the `postgres` path. If it fails for any other reason,
STOP (see the plan).

`docs/testing/testing-strategy.md` records the rule: a contract test that
impersonates a user sets the role, not only the claims.

### D6. New contract suite

Add `scripts/tests/direct-table-dml-contract-test.sh` and run it from
`scripts/backend-write-contracts.sh`. All probes run inside
`begin; ... rollback;`, so nothing is committed.

**Structural guards:**

- **G1, grants.**
  - For every relation in `public` (`relkind` in `r`, `p`, `v`, `m`, `f`),
    `has_table_privilege` is false for `anon` and `authenticated` on `INSERT`,
    `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER` and `MAINTAIN`,
    and false for `anon` on `SELECT`.
  - For every sequence in `public`, `has_sequence_privilege` is false for
    `anon` and `authenticated` on `USAGE`, `SELECT` and `UPDATE`. A negative
    control grants one probe sequence and asserts that the guard reports it.
  - `authenticated` has `SELECT` on the ten tables of fact 1.
- **G2, policies.** No policy in `public` has command `ALL`. Every `INSERT`,
  `UPDATE` or `DELETE` policy in `public` has `USING` and `WITH CHECK`
  expressions that are literally `false` or absent (an insert policy has no
  `USING`, a delete policy no `WITH CHECK`).
- **G3, default privileges.** No `pg_default_acl` entry for `postgres` in
  `public` grants anything to `anon`, `authenticated` or `service_role` for
  tables, sequences or functions. A behavioural probe also creates a table
  with an identity column and a function, then asserts that `anon`,
  `authenticated` and `service_role` have no privilege on the table and its
  sequence, and that the function ACL lists none of the three roles.
- **G4, definer functions.** No `security definer` function in `public` is
  executable by `anon` (`has_function_privilege`, which also counts
  `PUBLIC`). A negative control grants `EXECUTE` on one definer function to
  `anon` inside the rolled-back transaction and asserts the guard query
  reports it.
- **G5, ownership.** `postgres` owns every relation and function in `public`.
  An object owned by another role takes that role's default privileges, which
  G3 does not see. A negative control hands a probe table to `service_role`.
- **G6, RLS.** Every `public` table (`relkind` `r` or `p`) has RLS enabled, so
  B2's second layer exists for every table. A negative control disables RLS
  on a probe table.

**Behaviour, as `authenticated`** (claims set and `set local role
authenticated`):

- **B1, grant layer.** As the demo user (an `organization_member` with
  `canEditSongs`, `canManagePlans` and `canEditSessions`), each of `INSERT`,
  `UPDATE`, `DELETE` and `TRUNCATE` on `songs`, `plans`, `sessions`,
  `session_items` and `attachments` fails with SQLSTATE `42501`. For
  `memberships`, the demo user is promoted to `organization_admin` inside the
  transaction first, so `can_manage_membership` holds. Insert payloads are
  valid rows, so before the migration they succeed. The test asserts `42501`
  specifically, never "any error".
- **B2, RLS layer.** In the same setup, `postgres` first re-grants `INSERT`,
  `UPDATE` and `DELETE` on those six tables to `authenticated`, still inside
  the rolled-back transaction. Then each insert fails with
  `new row violates row-level security policy`. Each update and delete
  affects zero rows, verified by `postgres` re-reading the target rows
  unchanged. The seed has no attachment, so `postgres` inserts one target
  attachment first, inside the same transaction.
- **B3, read preservation.** For four users, each table's row set as
  `authenticated` matches the rows the select policies define, computed as
  `postgres`. A row set is compared by its count plus an md5 of the sorted ids
  (review gate 1), so a visible row swapped for a hidden one is caught. The
  users are the demo user, plus three created inside the transaction: an
  `organization_read_only` member, an `organization_admin` and a
  group-scoped `group_member`. The tables are `organizations`, `groups`,
  `memberships`, `songs`, `attachments`, `plans`, `sessions` and
  `session_items`. Run against both the old and the new schema, this proves D2
  changed no visibility.
- **B4, uncovered RPCs.** As the demo user, `get_my_capabilities` returns the
  member's capability row, and `delete_account()` deletes the caller's
  `auth.users` row (rolled back).

**Red and green expectations against the pre-migration schema:**

| Check | Before migration | After |
|---|---|---|
| G1, G2, G3, B1, B2 | red | green |
| G4, G5, G6 (with their negative controls), B3, B4 | green | green |

G4, G5, G6, B3 and B4 are regression guards. G4, G5 and G6 prove they can fail
through their negative controls. B3 must stay green on both sides, which is the point of the check.

### D7. Documentation

- `docs/architecture/architecture.md`: replace the "RLS does not yet deny
  direct DML" paragraph with the enforced model and a link to ADR-039.
- ADR-039 (new): RPC-only writes enforced by grants and policies; explicit
  grants for new objects; the D4 convention; the facts 5 and 6 caveats.
- ADR-026, ADR-027, ADR-038: append a dated correction note. Their claim that
  RLS denied direct DML was true only from this slice on.
- `docs/testing/testing-strategy.md`: the D5 rule and the new suite.
- `docs/deferred/2026-09-30-direct-dml-bypasses-write-rpcs.md`: removed, per
  the tracking rule. Links to it in the 2026-09-29 plan-delete spec and plan
  and in ADR-038 are updated to this spec.
- `docs/plans/2026-10-01-delivery-roadmap.md`: status note and S1 row.
- `scripts/tests/capability-search-path-contract-test.sh`: its comment names
  the dropped `for all` memberships policy as the recursion path. Rewrite the
  comment. The assertions stay: both helpers remain `security definer`, and
  the memberships read stays as a smoke check.

### D8. Deployment

- The client is unchanged and never writes tables directly, so the migration
  can deploy before or after any client release.
- **User action:** in the hosted Data API settings, turn off "Default
  privileges for new entities". The dashboard now labels it "Automatically
  expose new tables".
- **Apply the migration by hand** in the hosted SQL editor, wrapped in
  `begin;` ... `commit;`. Do not use `supabase db push`: the hosted
  migration history is out of sync (`docs/workflows/development-workflow.md`,
  "Hosted Migration Deployment").
- **Post-deploy check:** a read-only query, run in the hosted SQL editor:

  ```sql
  select c.relname, array_to_string(c.relacl, ' ')
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
  order by 1;

  select d.defaclobjtype, array_to_string(d.defaclacl, ' ')
  from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace
  where n.nspname = 'public' and pg_get_userbyid(d.defaclrole) = 'postgres';

  select polrelid::regclass, polname, polcmd
  from pg_policy p join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and p.polcmd <> 'r'
  order by 1, 2;
  ```

  Expected: `authenticated=r` and no `anon` entry on every table; no `anon`,
  `authenticated` or `service_role` in the default ACLs; only the six `false`
  deny policies on `invitations` and `invitation_redemption_attempts` in the
  third result.
- **Rollback:** a forward migration that re-grants
  `insert, update, delete` to `authenticated` and recreates the six policies
  from `202603210001_initial_schema.sql`. Not expected: the app does not use
  the removed privileges.

## Risks

- **A definer RPC depends on an invoker privilege.** Fact 7 says none does,
  and D5 proves it by running every covered RPC as `authenticated`. B4 covers
  the rest.
- **Hosted drift.** The hosted database could have objects or grants the local
  one lacks. The explicit table list (D1) and the post-deploy check (D8)
  bound this.
- **A future migration forgets the convention.** G1 to G4 fail the backend
  contract job for any new table, policy or definer function that breaks it.
