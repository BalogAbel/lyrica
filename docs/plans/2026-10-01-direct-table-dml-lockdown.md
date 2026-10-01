# Direct Table DML Lockdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Writes to every `public` application table go only through
`security definer` RPCs, enforced by grants and by RLS, and new `public`
objects start without privileges.

**Architecture:** One forward migration revokes write privileges from
`anon`/`authenticated`, drops the six `for all` policies and revokes the
`postgres` default privileges in `public`. The existing contract suites start
impersonating the real `authenticated` role, and a new contract suite pins
grants, policies, default privileges, read visibility and the uncovered RPCs.

**Tech Stack:** PostgreSQL 17 (Supabase local stack), bash + Python contract
scripts run through `docker exec ... psql`.

**Spec:** `docs/specs/2026-10-01-direct-table-dml-lockdown.md`. The spec's
D1–D8 and G1–G4 / B1–B4 labels are used below.

---

## Execution Model

- **Orchestrator:** the session that wrote the spec executes the tasks inline.
  It already holds the verified facts, so cold subagents would re-derive them.
- **Adversarial review (Task 6):** one Opus subagent on the whole diff, with
  one negative claim to disprove. Per-task subagent reviews are skipped: every
  task is a small SQL or script change, verified by running the full backend
  suite.
- **Verification:** `./scripts/backend-write-contracts.sh` is the full backend
  suite and runs after every task. `./scripts/verify.sh` (format, analyze,
  Flutter unit tests, coverage gate, dependency audit, migration lint, backend
  contracts, Flutter integration tests against local Supabase) runs after the
  migration and before the PR. Docker context must be `desktop-linux`.

## STOP Conditions

Stop and report instead of improvising if any of these happen:

- **STOP-1 (Task 1):** a suite fails after the role change for a reason other
  than a fixture written as the user. Moving such a fixture to the `postgres`
  path is allowed. Changing an assertion's meaning is not.
- **STOP-2 (Task 2):** on the pre-migration schema, a check the spec marks
  green (G4 and its negative control, B3, B4) fails, or a check marked red
  (G1, G2, G3, B1, B2) passes.
- **STOP-3 (Task 3):** any RPC call fails as `authenticated` after the
  migration, or B3 fails. Do not re-grant privileges to make it pass.
- **STOP-4 (Task 4):** a Flutter integration test fails on a read path.
- **STOP-5:** `supabase db lint` reports a new finding.

## File Map

- Create `supabase/migrations/202610010001_direct_table_dml_lockdown.sql`
  (D1, D2, D3).
- Create `scripts/tests/direct-table-dml-contract-test.sh` (D6).
- Modify `scripts/backend-write-contracts.sh` (run the new suite).
- Modify, D5 role impersonation:
  - `scripts/tests/planning-write-contract-test.sh`
  - `scripts/tests/planning-cascade-delete-contract-test.sh`
  - `scripts/tests/song-crud-write-contract-test.sh`
  - `scripts/tests/song-derived-metadata-contract-test.sh`
  - `scripts/tests/organization-read-only-role-test.sh`
- Modify `scripts/tests/capability-search-path-contract-test.sh` (comments
  only).
- Docs (D7): new ADR-039; `docs/architecture/architecture.md`; ADR-026,
  ADR-027 and ADR-038 notes; `docs/testing/testing-strategy.md`; the
  plan-delete spec and plan links; the roadmap; this spec's status; delete
  `docs/deferred/2026-09-30-direct-dml-bypasses-write-rpcs.md`.

---

### Task 1: Contract suites impersonate the real role (D5)

**Files:**
- Modify: `scripts/tests/planning-write-contract-test.sh` (`run_psql`)
- Modify: `scripts/tests/planning-cascade-delete-contract-test.sh`
  (`run_psql`, race-holder statement list)
- Modify: `scripts/tests/song-crud-write-contract-test.sh` (`run_psql`,
  `start_psql`)
- Modify: `scripts/tests/song-derived-metadata-contract-test.sh` (`run_psql`)
- Modify: `scripts/tests/organization-read-only-role-test.sh`
  (`run_sql_as_user`)

- [ ] **Step 1: Add the role switch to every claim block**

In each `run_psql` / `start_psql` / `run_sql_as_user` helper, the block

```python
            do $$
            begin
              perform set_config('request.jwt.claim.sub', {sql_quote(user_id)}, true);
              perform set_config('request.jwt.claim.role', 'authenticated', true);
            end $$;
            {sql}
```

becomes (indentation as in the file):

```python
            do $$
            begin
              perform set_config('request.jwt.claim.sub', {sql_quote(user_id)}, true);
              perform set_config('request.jwt.claim.role', 'authenticated', true);
            end $$;
            set local role authenticated;
            {sql}
```

In `planning-cascade-delete-contract-test.sh`, the race-holder statement
tuple gets the same switch after its two `set_config` lines:

```python
        for statement in (
            "begin;",
            f"select set_config('request.jwt.claim.sub', {sql_quote(demo_user_id)}, true);",
            "select set_config('request.jwt.claim.role', 'authenticated', true);",
            "set local role authenticated;",
            holder_sql,
            f"select 'race-holder-{tag}';",
        ):
```

Verified on 2026-10-01: in a multi-statement `psql -c` string, `set local role`
holds for the rest of the string, also across a later explicit `begin;`.

- [ ] **Step 2: Run the full backend suite on the pre-migration schema**

Run: `./scripts/backend-write-contracts.sh`
Expected: every suite passes. A failure caused by a fixture written as the user
is fixed by moving that statement to a `run_psql(...)` call without `user_id`.
Any other failure → STOP-1.

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/planning-write-contract-test.sh \
  scripts/tests/planning-cascade-delete-contract-test.sh \
  scripts/tests/song-crud-write-contract-test.sh \
  scripts/tests/song-derived-metadata-contract-test.sh \
  scripts/tests/organization-read-only-role-test.sh
git commit -m "test(backend): contract suites impersonate the authenticated role"
```

---

### Task 2: Red contract suite for direct table DML (D6)

**Files:**
- Create: `scripts/tests/direct-table-dml-contract-test.sh`
- Modify: `scripts/backend-write-contracts.sh`

- [ ] **Step 1: Write the suite**

Create `scripts/tests/direct-table-dml-contract-test.sh` with exactly this
content, then `chmod +x` it. It collects every failure before exiting, so a red
run lists each failing check by label.

<!-- extract:direct-table-dml-contract-test.sh -->
```bash
#!/usr/bin/env bash
set -euo pipefail

# Direct table DML contract (spec: docs/specs/2026-10-01-direct-table-dml-lockdown.md).
#
# Writes to public tables go only through security definer RPCs. This suite
# pins that from four structural angles (G1-G4) and four behavioural ones
# (B1-B4), impersonating real users with `set local role authenticated`.
# Every probe runs inside begin/rollback; nothing is committed.

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

if [[ "${BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP:-0}" != "1" ]]; then
  ./scripts/supabase.sh start >/dev/null
  ./scripts/db-reset.sh >/dev/null

  status_env="$(./scripts/supabase.sh status -o env)"
  eval "$status_env"

  if [[ -z "${API_URL:-}" ]]; then
    echo "Local Supabase is not running or did not return API_URL." >&2
    exit 1
  fi

  for _ in $(seq 1 30); do
    if curl --silent --fail "$API_URL/auth/v1/health" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  ./scripts/provision-local-demo-user.sh >/dev/null
fi

db_container_name="$(
  docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1
)"

if [[ -z "$db_container_name" ]]; then
  echo "Could not find the local Supabase database container." >&2
  exit 1
fi

python3 - "$db_container_name" <<'PY'
import subprocess
import sys
from textwrap import dedent

container = sys.argv[1]

ORG = "11111111-1111-1111-1111-111111111111"
HIDDEN_ORG = "11111111-1111-1111-1111-111111111112"
GROUP = "22222222-2222-2222-2222-222222222222"
SEED_SESSION = "55555555-5555-5555-5555-555555555551"

PROBE_USER = "d1000000-0000-4000-8000-000000000001"
READ_ONLY_USER = "d1000000-0000-4000-8000-000000000002"
ADMIN_USER = "d1000000-0000-4000-8000-000000000003"
GROUP_USER = "d1000000-0000-4000-8000-000000000004"
MEMBERSHIP_TARGET = "d1000000-0000-4000-8000-000000000011"
SONG_TARGET = "d1000000-0000-4000-8000-000000000012"
PLAN_TARGET = "d1000000-0000-4000-8000-000000000013"
SESSION_TARGET = "d1000000-0000-4000-8000-000000000014"
ITEM_TARGET = "d1000000-0000-4000-8000-000000000015"
ATTACHMENT_TARGET = "d1000000-0000-4000-8000-000000000016"
HIDDEN_MEMBERSHIP = "d1000000-0000-4000-8000-000000000017"

# Tables authenticated must keep reading through the table API (ADR-026).
# G1 enumerates pg_class, so a table added later is checked for write
# privileges even though it is not listed here.
READABLE_TABLES = [
    "organizations",
    "groups",
    "memberships",
    "songs",
    "plans",
    "sessions",
    "session_items",
    "attachments",
    "invitations",
    "invitation_redemption_attempts",
]

# Tables that used to carry a permissive `for all` write policy.
WRITE_POLICY_TABLES = [
    "songs",
    "plans",
    "sessions",
    "session_items",
    "attachments",
    "memberships",
]

# Tables whose per-user visibility B3 compares before and after.
VISIBILITY_TABLES = [
    "organizations",
    "groups",
    "memberships",
    "songs",
    "attachments",
    "plans",
    "sessions",
    "session_items",
]

failures: list[str] = []


def psql(sql: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            "docker", "exec", "-i", container,
            "psql", "-U", "postgres", "-d", "postgres",
            "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose",
            "-X", "-qAt", "-F", "\t",
        ],
        input=sql,
        capture_output=True,
        text=True,
        check=False,
    )


def must(sql: str) -> list[str]:
    result = psql(sql)
    if result.returncode != 0:
        raise SystemExit(f"harness sql failed:\n{sql}\nstderr: {result.stderr}")
    return [line for line in result.stdout.splitlines() if line.strip()]


def row(lines: list[str], tag: str) -> list[str] | None:
    for line in lines:
        fields = line.split("\t")
        if fields[0] == tag:
            return fields[1:]
    return None


def as_user(user_id: str) -> str:
    return dedent(
        f"""
        do $$
        begin
          perform set_config('request.jwt.claim.sub', '{user_id}', true);
          perform set_config('request.jwt.claim.role', 'authenticated', true);
        end $$;
        set local role authenticated;
        """
    )


demo_rows = must("select id from auth.users where email = 'demo@lyron.local';")
if len(demo_rows) != 1:
    raise SystemExit(f"expected exactly one demo user, got {demo_rows!r}")
DEMO = demo_rows[0]

# Probe rows, inserted as postgres inside each probe transaction. Every write
# target has no dependants, so a red run fails on the write itself.
FIXTURES = dedent(
    f"""
    insert into auth.users (id, email) values
      ('{PROBE_USER}', 's1-dml-probe@lyron.local'),
      ('{READ_ONLY_USER}', 's1-dml-read-only@lyron.local'),
      ('{ADMIN_USER}', 's1-dml-admin@lyron.local'),
      ('{GROUP_USER}', 's1-dml-group@lyron.local');
    insert into public.memberships
      (id, organization_id, user_id, group_id, scope_type, role_code, status)
    values
      ('{MEMBERSHIP_TARGET}', '{ORG}', '{PROBE_USER}', null,
       'organization', 'organization_member', 'active'),
      (gen_random_uuid(), '{ORG}', '{READ_ONLY_USER}', null,
       'organization', 'organization_read_only', 'active'),
      (gen_random_uuid(), '{ORG}', '{ADMIN_USER}', null,
       'organization', 'organization_admin', 'active'),
      (gen_random_uuid(), '{ORG}', '{GROUP_USER}', '{GROUP}',
       'group', 'group_member', 'active'),
      ('{HIDDEN_MEMBERSHIP}', '{HIDDEN_ORG}', '{PROBE_USER}', null,
       'organization', 'organization_member', 'active');
    insert into public.songs (id, organization_id, title, chordpro_source, slug)
    values ('{SONG_TARGET}', '{ORG}', 'S1 probe target',
            '{{title: S1 probe target}}', 's1-probe-target');
    insert into public.plans (id, organization_id, name, slug)
    values ('{PLAN_TARGET}', '{ORG}', 'S1 probe plan', 's1-probe-plan');
    insert into public.sessions (id, organization_id, plan_id, position, name, slug)
    values ('{SESSION_TARGET}', '{ORG}', '{PLAN_TARGET}', 1,
            'S1 probe session', 's1-probe-session');
    insert into public.session_items
      (id, organization_id, session_id, item_type, song_id, position)
    values ('{ITEM_TARGET}', '{ORG}', '{SEED_SESSION}', 'song', '{SONG_TARGET}', 1000);
    insert into public.attachments
      (id, organization_id, song_id, storage_bucket, storage_path, mime_type, file_name)
    values ('{ATTACHMENT_TARGET}', '{ORG}', '{SONG_TARGET}', 'attachments',
            's1/probe.pdf', 'application/pdf', 'probe.pdf');
    """
)

# The demo user is an organization_member: it holds canEditSongs,
# canManagePlans and canEditSessions, but not canManageOrganizationMembers.
PROMOTE_DEMO = dedent(
    f"""
    update public.memberships
    set role_code = 'organization_admin'
    where organization_id = '{ORG}'
      and user_id = '{DEMO}'
      and scope_type = 'organization';
    """
)

TABLE_PROBES = {
    "songs": {
        "target": SONG_TARGET,
        "insert": (
            "insert into public.songs (organization_id, title, chordpro_source, slug) "
            f"values ('{ORG}', 'S1 direct insert', '{{title: S1 direct insert}}', "
            "'s1-direct-insert')"
        ),
        "set": "title = 'S1 direct update'",
        "column": "title",
        "original": "S1 probe target",
        "promote": False,
    },
    "plans": {
        "target": PLAN_TARGET,
        "insert": (
            "insert into public.plans (organization_id, name, slug) "
            f"values ('{ORG}', 'S1 direct plan', 's1-direct-plan')"
        ),
        "set": "name = 'S1 direct update'",
        "column": "name",
        "original": "S1 probe plan",
        "promote": False,
    },
    "sessions": {
        "target": SESSION_TARGET,
        "insert": (
            "insert into public.sessions (organization_id, plan_id, position, name, slug) "
            f"values ('{ORG}', '{PLAN_TARGET}', 2, 'S1 direct session', "
            "'s1-direct-session')"
        ),
        "set": "name = 'S1 direct update'",
        "column": "name",
        "original": "S1 probe session",
        "promote": False,
    },
    "session_items": {
        "target": ITEM_TARGET,
        "insert": (
            "insert into public.session_items "
            "(organization_id, session_id, item_type, song_id, position) "
            f"values ('{ORG}', '{SESSION_TARGET}', 'song', '{SONG_TARGET}', 1)"
        ),
        "set": "position = 1001",
        "column": "position",
        "original": "1000",
        "promote": False,
    },
    "attachments": {
        "target": ATTACHMENT_TARGET,
        "insert": (
            "insert into public.attachments "
            "(organization_id, song_id, storage_bucket, storage_path, mime_type, file_name) "
            f"values ('{ORG}', '{SONG_TARGET}', 'attachments', 's1/direct.pdf', "
            "'application/pdf', 'direct.pdf')"
        ),
        "set": "file_name = 'direct-update.pdf'",
        "column": "file_name",
        "original": "probe.pdf",
        "promote": False,
    },
    "memberships": {
        "target": MEMBERSHIP_TARGET,
        "insert": (
            "insert into public.memberships "
            "(organization_id, user_id, scope_type, role_code, status) "
            f"values ('{ORG}', '{PROBE_USER}', 'organization', 'organization_admin', 'active')"
        ),
        "set": "role_code = 'organization_admin'",
        "column": "role_code",
        "original": "organization_member",
        "promote": True,
    },
}

# Harness self-check: the fixtures apply cleanly, so every later failure is
# about the statement under test.
must("begin;\n" + FIXTURES + PROMOTE_DEMO + "rollback;\n")

# --- G1: no write privilege for anon or authenticated on any public relation.
g1 = must(
    dedent(
        """
        select c.oid::regclass::text, r.role, p.privilege
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        cross join (values ('anon'), ('authenticated')) as r(role)
        cross join (values ('INSERT'), ('UPDATE'), ('REFERENCES')) as p(privilege)
        where n.nspname = 'public'
          and c.relkind in ('r', 'p', 'v', 'm', 'f')
          and has_any_column_privilege(r.role, c.oid, p.privilege)
        union all
        select c.oid::regclass::text, r.role, p.privilege
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        cross join (values ('anon'), ('authenticated')) as r(role)
        cross join (
          values ('DELETE'), ('TRUNCATE'), ('TRIGGER'), ('MAINTAIN')
        ) as p(privilege)
        where n.nspname = 'public'
          and c.relkind in ('r', 'p', 'v', 'm', 'f')
          and has_table_privilege(r.role, c.oid, p.privilege)
        union all
        select c.oid::regclass::text, 'anon', 'SELECT'
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relkind in ('r', 'p', 'v', 'm', 'f')
          and has_any_column_privilege('anon', c.oid, 'SELECT')
        order by 1, 2, 3;
        """
    )
)
for line in g1:
    failures.append(f"G1 forbidden privilege (relation, role, privilege): {line}")

readable = ", ".join(f"'public.{table}'" for table in READABLE_TABLES)
g1_select = must(
    f"select t from unnest(array[{readable}]) as t "
    "where not has_table_privilege('authenticated', t, 'SELECT');"
)
for line in g1_select:
    failures.append(f"G1 authenticated lost SELECT on {line}")

# --- G2: no policy in public permits a write.
g2 = must(
    dedent(
        """
        select p.polrelid::regclass::text, p.polname, p.polcmd
        from pg_policy p
        join pg_class c on c.oid = p.polrelid
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and (
            p.polcmd = '*'
            or (
              p.polcmd in ('a', 'w', 'd')
              and (
                coalesce(pg_get_expr(p.polqual, p.polrelid), 'false') <> 'false'
                or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), 'false') <> 'false'
              )
            )
          )
        order by 1, 2;
        """
    )
)
for line in g2:
    failures.append(f"G2 write-permitting policy (table, policy, cmd): {line}")

# --- G3: postgres's default privileges grant nothing to the API roles.
g3 = must(
    dedent(
        """
        select coalesce(n.nspname, '<all schemas>'), d.defaclobjtype,
               pg_get_userbyid(a.grantee), a.privilege_type
        from pg_default_acl d
        left join pg_namespace n on n.oid = d.defaclnamespace
        cross join lateral aclexplode(d.defaclacl) as a
        where pg_get_userbyid(d.defaclrole) = 'postgres'
          and (d.defaclnamespace = 0 or n.nspname = 'public')
          and pg_get_userbyid(a.grantee) in ('anon', 'authenticated', 'service_role')
        order by 1, 2, 3, 4;
        """
    )
)
for line in g3:
    failures.append(f"G3 default privilege (schema, objtype, grantee, privilege): {line}")

g3_probe = must(
    dedent(
        """
        begin;
        create table public.s1_default_privilege_probe (
          id bigint generated always as identity primary key
        );
        create function public.s1_default_privilege_probe_fn()
        returns integer
        language sql
        as $$ select 1 $$;
        select 'table', r.role, p.privilege
        from (values ('anon'), ('authenticated'), ('service_role')) as r(role)
        cross join (
          values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
                 ('TRUNCATE'), ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')
        ) as p(privilege)
        where has_table_privilege(r.role, 'public.s1_default_privilege_probe', p.privilege)
        union all
        select 'sequence', r.role, p.privilege
        from (values ('anon'), ('authenticated'), ('service_role')) as r(role)
        cross join (values ('USAGE'), ('SELECT'), ('UPDATE')) as p(privilege)
        where has_sequence_privilege(
          r.role, 'public.s1_default_privilege_probe_id_seq', p.privilege
        )
        union all
        select 'function', pg_get_userbyid(a.grantee), a.privilege_type
        from pg_proc f
        cross join lateral aclexplode(coalesce(f.proacl, acldefault('f', f.proowner))) as a
        where f.oid = 'public.s1_default_privilege_probe_fn()'::regprocedure
          and pg_get_userbyid(a.grantee) in ('anon', 'authenticated', 'service_role');
        rollback;
        """
    )
)
for line in g3_probe:
    failures.append(f"G3 new object got a privilege (kind, role, privilege): {line}")

# --- G4: no security definer function in public is executable by anon
# (has_function_privilege also counts PUBLIC).
G4_SQL = dedent(
    """
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and has_function_privilege('anon', p.oid, 'EXECUTE')
    order by 1;
    """
)
for line in must(G4_SQL):
    failures.append(f"G4 security definer function executable by anon: {line}")

g4_control = must(
    "begin;\ngrant execute on function public.delete_account() to anon;\n"
    + G4_SQL
    + "rollback;\n"
)
if "delete_account()" not in g4_control:
    failures.append(
        f"G4 negative control: guard did not report a granted function, got {g4_control!r}"
    )


def setup(table: str, regrant: bool) -> str:
    probe = TABLE_PROBES[table]
    sql = "begin;\n" + FIXTURES
    if regrant:
        sql += f"grant insert, update, delete on public.{table} to authenticated;\n"
    if probe["promote"]:
        sql += PROMOTE_DEMO
    return sql + as_user(DEMO)


def expect_error(label: str, sql: str, message: str) -> None:
    result = psql(sql)
    if result.returncode == 0 or "42501" not in result.stderr or message not in result.stderr:
        failures.append(
            f"{label}: expected 42501 '{message}', got rc={result.returncode} "
            f"stderr={result.stderr.strip()[:400]!r}"
        )


# --- B1: the grant layer denies every direct write as a capable member.
for table, probe in TABLE_PROBES.items():
    target = probe["target"]
    denied = f"permission denied for table {table}"
    statements = {
        "insert": probe["insert"],
        "update": f"update public.{table} set {probe['set']} where id = '{target}'",
        "delete": f"delete from public.{table} where id = '{target}'",
        "truncate": f"truncate public.{table}",
    }
    for operation, statement in statements.items():
        expect_error(
            f"B1 {operation} on {table}",
            setup(table, regrant=False) + statement + ";\nrollback;\n",
            denied,
        )

# --- B2: with a grant re-added by mistake, RLS still denies every write.
for table, probe in TABLE_PROBES.items():
    target = probe["target"]
    expect_error(
        f"B2 insert on {table}",
        setup(table, regrant=True) + probe["insert"] + ";\nrollback;\n",
        f'new row violates row-level security policy for table "{table}"',
    )

    update_lines = psql(
        setup(table, regrant=True)
        + dedent(
            f"""
            with changed as (
              update public.{table} set {probe['set']} where id = '{target}' returning 1
            )
            select 'affected', count(*) from changed;
            reset role;
            select 'after', {probe['column']} from public.{table} where id = '{target}';
            rollback;
            """
        )
    )
    affected = row(update_lines.stdout.splitlines(), "affected")
    after = row(update_lines.stdout.splitlines(), "after")
    if update_lines.returncode != 0 or affected != ["0"] or after != [probe["original"]]:
        failures.append(
            f"B2 update on {table}: expected 0 rows and {probe['original']!r} kept, "
            f"got rc={update_lines.returncode} affected={affected} after={after} "
            f"stderr={update_lines.stderr.strip()[:300]!r}"
        )

    delete_lines = psql(
        setup(table, regrant=True)
        + dedent(
            f"""
            with gone as (
              delete from public.{table} where id = '{target}' returning 1
            )
            select 'affected', count(*) from gone;
            reset role;
            select 'after', count(*) from public.{table} where id = '{target}';
            rollback;
            """
        )
    )
    affected = row(delete_lines.stdout.splitlines(), "affected")
    after = row(delete_lines.stdout.splitlines(), "after")
    if delete_lines.returncode != 0 or affected != ["0"] or after != ["1"]:
        failures.append(
            f"B2 delete on {table}: expected 0 rows and the row kept, "
            f"got rc={delete_lines.returncode} affected={affected} after={after} "
            f"stderr={delete_lines.stderr.strip()[:300]!r}"
        )

# --- B3: every user sees exactly the rows the select policies define.
EXPECTED_COUNTS = dedent(
    """
    with member_orgs as (
      select organization_id from public.memberships
      where user_id = '{user}' and status = 'active'
    ),
    song_orgs as (
      select organization_id from public.memberships
      where user_id = '{user}' and status = 'active' and scope_type = 'organization'
    )
    select 'expected',
      (select count(*) from public.organizations
        where id in (select organization_id from member_orgs)),
      (select count(*) from public.groups
        where organization_id in (select organization_id from member_orgs)),
      (select count(*) from public.memberships
        where organization_id in (select organization_id from member_orgs)),
      (select count(*) from public.songs
        where organization_id in (select organization_id from song_orgs)),
      (select count(*) from public.attachments
        where organization_id in (select organization_id from song_orgs)),
      (select count(*) from public.plans
        where organization_id in (select organization_id from member_orgs)),
      (select count(*) from public.sessions
        where organization_id in (select organization_id from member_orgs)),
      (select count(*) from public.session_items
        where organization_id in (select organization_id from member_orgs));
    """
)
ACTUAL_COUNTS = (
    "select 'actual', "
    + ", ".join(f"(select count(*) from public.{table})" for table in VISIBILITY_TABLES)
    + ";\n"
)

seen_positive = [False] * len(VISIBILITY_TABLES)
for label, user in (
    ("demo member", DEMO),
    ("read-only member", READ_ONLY_USER),
    ("organization admin", ADMIN_USER),
    ("group member", GROUP_USER),
):
    lines = must(
        "begin;\n"
        + FIXTURES
        + EXPECTED_COUNTS.replace("{user}", user)
        + as_user(user)
        + ACTUAL_COUNTS
        + "reset role;\nrollback;\n"
    )
    expected = row(lines, "expected")
    actual = row(lines, "actual")
    if expected is None or actual is None or expected != actual:
        failures.append(
            f"B3 {label}: visible counts {dict(zip(VISIBILITY_TABLES, actual or []))} "
            f"differ from policy counts {dict(zip(VISIBILITY_TABLES, expected or []))}"
        )
        continue
    for index, count in enumerate(expected):
        if int(count) > 0:
            seen_positive[index] = True

for table, positive in zip(VISIBILITY_TABLES, seen_positive):
    if not positive:
        failures.append(f"B3 vacuous: no user sees any row of {table}")

# --- B4: the RPCs no other suite calls still work as authenticated.
caps = must(
    "begin;\n"
    + as_user(DEMO)
    + f"select 'caps', array_to_string(public.get_my_capabilities('{ORG}', null), ',');\n"
    + "rollback;\n"
)
caps_row = row(caps, "caps")
if caps_row is None or "canViewSongs" not in caps_row[0].split(","):
    failures.append(f"B4 get_my_capabilities: expected canViewSongs, got {caps!r}")

deleted = psql(
    "begin;\n"
    + as_user(DEMO)
    + "select public.delete_account();\nreset role;\n"
    + f"select 'remaining', count(*) from auth.users where id = '{DEMO}';\n"
    + "rollback;\n"
)
remaining = row(deleted.stdout.splitlines(), "remaining")
if deleted.returncode != 0 or remaining != ["0"]:
    failures.append(
        f"B4 delete_account: expected the caller removed, got rc={deleted.returncode} "
        f"remaining={remaining} stderr={deleted.stderr.strip()[:300]!r}"
    )

if failures:
    raise SystemExit(
        "direct table DML contract failed:\n  " + "\n  ".join(failures)
    )

print(
    "direct table DML contract passed: anon/authenticated hold no write "
    "privilege and no policy permits a write (G1, G2), new public objects start "
    "without privileges (G3), no definer function is open to anon (G4), direct "
    "writes are denied by grants and by RLS (B1, B2), reads are unchanged (B3), "
    "and get_my_capabilities/delete_account work as authenticated (B4)."
)
PY
```

- [ ] **Step 2: Run it in the backend runner**

In `scripts/backend-write-contracts.sh`, append after the
`create_invitation_service_role_gate_test_script` block:

```bash
direct_table_dml_test_script="${DIRECT_TABLE_DML_TEST_SCRIPT:-./scripts/tests/direct-table-dml-contract-test.sh}"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$direct_table_dml_test_script"
```

- [ ] **Step 3: Run the suite on the pre-migration schema and confirm the red set**

Run: `bash scripts/tests/direct-table-dml-contract-test.sh`
Expected: exit 1, listing failures labelled G1, G2, G3, B1 and B2, and none
labelled G4, B3, B4 or "harness". Anything else → STOP-2.

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/direct-table-dml-contract-test.sh scripts/backend-write-contracts.sh
git commit -m "test(backend): red -- direct table DML is denied to authenticated"
```

---

### Task 3: Lockdown migration (D1, D2, D3)

**Files:**
- Create: `supabase/migrations/202610010001_direct_table_dml_lockdown.sql`
- Modify: `scripts/tests/capability-search-path-contract-test.sh` (comments)

- [ ] **Step 1: Write the migration**

<!-- extract:202610010001_direct_table_dml_lockdown.sql -->
```sql
-- Direct table DML lockdown.
-- Spec: docs/specs/2026-10-01-direct-table-dml-lockdown.md; ADR-039.
--
-- Writes to the application tables go only through security definer RPCs,
-- which run as the table owner. This migration removes every other write path:
--   1. anon and authenticated lose every table privilege except SELECT for
--      authenticated (the ADR-026 read boundary). TRUNCATE ignores RLS, so it
--      must go even though no policy allows it.
--   2. The six permissive `for all` write policies are dropped. Each one is
--      already covered by its table's select policy: has_capability is true
--      only for an organization the caller is an active member of, and the
--      canEditSongs roles are a subset of the canViewSongs roles. No visible
--      row changes.
--   3. Objects postgres creates in public from now on start with no privileges
--      for anon, authenticated or service_role; each migration grants what it
--      needs explicitly.

revoke all on table
  public.organizations,
  public.groups,
  public.memberships,
  public.songs,
  public.plans,
  public.sessions,
  public.session_items,
  public.attachments,
  public.invitations,
  public.invitation_redemption_attempts
from anon, authenticated;

grant select on table
  public.organizations,
  public.groups,
  public.memberships,
  public.songs,
  public.plans,
  public.sessions,
  public.session_items,
  public.attachments,
  public.invitations,
  public.invitation_redemption_attempts
to authenticated;

drop policy "memberships are manageable by capability" on public.memberships;
drop policy "songs are editable with song edit capability" on public.songs;
drop policy "plans are editable with plan capability" on public.plans;
drop policy "sessions are editable with session capability" on public.sessions;
drop policy "session items inherit session edit capability" on public.session_items;
drop policy "attachments are editable to song editors" on public.attachments;

-- `revoke all`, not the four table privileges the Supabase guide lists: those
-- leave TRUNCATE, REFERENCES, TRIGGER and MAINTAIN granted on every new table.
-- PUBLIC keeps the PostgreSQL-global EXECUTE default on functions, which a
-- per-schema revoke cannot remove, so every function migration still revokes
-- from public, anon and authenticated explicitly.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated, service_role;
```

- [ ] **Step 2: Rewrite the stale comments in the capability suite**

In `scripts/tests/capability-search-path-contract-test.sh`, the comment above
`required_security_definer` and the comment above the memberships probe
describe the dropped `for all` memberships policy as the recursion path.
Replace them with:

```python
# Helpers that must additionally run as security definer. has_capability and
# current_organization_ids are called from RLS policies and read
# public.memberships themselves. Until 202610010001 the "memberships are
# manageable by capability" ALL policy called back into has_capability, so an
# invoker-rights helper recursed until "stack depth limit exceeded"; that
# policy is gone, and the pin stays so the helpers never depend on the
# caller's own memberships RLS. get_my_capabilities and can_manage_membership
# are intentionally invoker-rights and are not asserted here.
```

and

```python
# Behavioural guard: an authenticated read of public.memberships must succeed.
# It covers rows outside the caller's organizations too, so the probe seeds a
# second membership row in an organization the demo user does not belong to,
# inside the same begin/rollback block used to switch role - it is never
# committed.
```

The assertions do not change.

- [ ] **Step 3: Apply and run the new suite**

Run: `./scripts/db-reset.sh && ./scripts/provision-local-demo-user.sh && bash scripts/tests/direct-table-dml-contract-test.sh`
Expected: `direct table DML contract passed: ...`. Any B3 or RPC failure →
STOP-3.

- [ ] **Step 4: Run the full backend suite and the migration lint**

Run: `./scripts/backend-write-contracts.sh && ./scripts/check-migrations.sh`
Expected: every suite passes; `db lint` reports no new finding (STOP-5).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202610010001_direct_table_dml_lockdown.sql \
  scripts/tests/capability-search-path-contract-test.sh
git commit -m "fix(backend): revoke direct table DML and default privileges"
```

---

### Task 4: Full verification

- [ ] **Step 1: Run the whole repository gate**

Run: `./scripts/verify.sh`
Expected: exit 0. The Flutter integration tests read `songs`, `plans`,
`sessions` and `session_items` through PostgREST as the demo user, so this
is the end-to-end proof that D1 and D2 kept reads working. A read failure →
STOP-4.

---

### Task 5: Documentation (D7)

**Files:**
- Create: `docs/architecture/decisions/ADR-039-rpc-only-writes-and-explicit-grants.md`
- Modify: `docs/architecture/architecture.md` (the "RLS does not yet deny
  direct DML" paragraph)
- Modify: ADR-026, ADR-027, ADR-038 (append a dated correction note)
- Modify: `docs/testing/testing-strategy.md` (D5 rule, new suite)
- Modify: `docs/specs/2026-09-29-plan-delete-and-session-cascade.md`,
  `docs/plans/2026-09-29-plan-delete-and-session-cascade.md` (links)
- Modify: `docs/plans/2026-10-01-delivery-roadmap.md` (status note, S1 row,
  user actions)
- Modify: `docs/specs/2026-10-01-direct-table-dml-lockdown.md` (status,
  commits)
- Delete: `docs/deferred/2026-09-30-direct-dml-bypasses-write-rpcs.md`

- [ ] **Step 1: ADR-039.** Context (facts 1–8 of the spec in short), decision
  (D1–D4), consequences (writes need an RPC; a new table needs explicit
  grants, `service_role` included; PUBLIC function default stays and is
  guarded by G4; hosted toggle), rejected alternatives (keep `for all` as
  `for select`: redundant and doubles definer evaluation per row; revoke
  grants only: one layer, and a re-grant reopens the bypass; global `PUBLIC`
  function revoke: reaches every schema).
- [ ] **Step 2: architecture.md.** Replace the paragraph that starts "RLS does
  not yet deny direct DML" with the enforced model in two sentences and a link
  to ADR-039.
- [ ] **Step 3: ADR notes.** ADR-026 ("The write half of this question is
  already closed"), ADR-027 ("RLS denies direct DML") and ADR-038 (the I2, I4,
  I5 consequence and the Deferred entry) each get a note dated 2026-10-01:
  the statement held only for RPC writers until migration `202610010001`, and
  now holds for every writer. Link ADR-039.
- [ ] **Step 4: testing-strategy.md.** In the backend contract section: a suite
  that impersonates a user sets `set local role authenticated` as well as the
  claims, because `postgres` bypasses RLS and grants; the new suite pins
  G1–G4 for every future table and function.
- [ ] **Step 5: Links.** Replace links to the deferred file with links to this
  spec in the plan-delete spec, the plan-delete plan and ADR-038. Delete the
  deferred file.
- [ ] **Step 6: Roadmap.** Status note: S1 implemented on
  `fix/direct-dml-write-rpc-bypass` (PR link once open). S1 row: status. User
  actions: the hosted toggle plus the spec's D8 post-deploy query.
- [ ] **Step 7: Spec status.** `Status: Implemented`, with the commit list.
- [ ] **Step 8: Verify the links and commit**

Run: `grep -rn "direct-dml-bypasses-write-rpcs" docs apps scripts supabase README.md AGENTS.md`
Expected: no output.

```bash
git add -A docs
git commit -m "docs: RPC-only writes enforced by grants (ADR-039)"
```

---

### Task 6: Adversarial whole-diff review

- [ ] **Step 1: Dispatch one Opus reviewer** on `git diff main...HEAD` with
  this claim to disprove: "After this diff, (a) some role other than the table
  owner and `service_role` can still change a row of a `public` table without
  calling a `security definer` RPC, or new objects can start with such a
  privilege; or (b) some read or RPC call that worked before the diff now
  fails or returns different rows." The reviewer must read the migration, the
  new suite and the live local database (`docker exec supabase_db_lyron psql
  -U postgres`), and report each counterexample with a reproducing SQL
  statement.
- [ ] **Step 2: Fix confirmed findings with a red test first**, re-run
  `./scripts/backend-write-contracts.sh`, and repeat until the reviewer finds
  nothing substantive.

---

### Task 7: Pull request

- [ ] **Step 1:** Push the branch, open the PR to `main`. The body names
  the hosted user action (turn off "Default privileges for new entities"), the
  migration deploy, and the D8 post-deploy query.
- [ ] **Step 2:** Watch CI to green. Merge only with the user's approval.
- [ ] **Step 3 (after merge):** refresh the graph (`graphify . --update`) in a
  `chore(graph)` PR; a migration and a test script were added.
