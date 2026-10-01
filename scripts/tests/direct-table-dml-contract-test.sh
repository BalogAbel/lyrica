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
SONG_PARENT = "d1000000-0000-4000-8000-000000000018"

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

# Probe rows, inserted as postgres inside each probe transaction. No row
# references a write target (child rows hang off SONG_PARENT, SEED_SESSION and
# PLAN_TARGET), so a red run fails on the write itself, not on a foreign key.
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
            '{{title: S1 probe target}}', 's1-probe-target'),
           ('{SONG_PARENT}', '{ORG}', 'S1 probe parent',
            '{{title: S1 probe parent}}', 's1-probe-parent');
    insert into public.plans (id, organization_id, name, slug)
    values ('{PLAN_TARGET}', '{ORG}', 'S1 probe plan', 's1-probe-plan');
    insert into public.sessions (id, organization_id, plan_id, position, name, slug)
    values ('{SESSION_TARGET}', '{ORG}', '{PLAN_TARGET}', 1,
            'S1 probe session', 's1-probe-session');
    insert into public.session_items
      (id, organization_id, session_id, item_type, song_id, position)
    values ('{ITEM_TARGET}', '{ORG}', '{SEED_SESSION}', 'song', '{SONG_PARENT}', 1000);
    insert into public.attachments
      (id, organization_id, song_id, storage_bucket, storage_path, mime_type, file_name)
    values ('{ATTACHMENT_TARGET}', '{ORG}', '{SONG_PARENT}', 'attachments',
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
            f"values ('{ORG}', '{SESSION_TARGET}', 'song', '{SONG_PARENT}', 1)"
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
            f"values ('{ORG}', '{SONG_PARENT}', 'attachments', 's1/direct.pdf', "
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

# --- G1: no write privilege for anon or authenticated on any public relation,
# and no privilege at all on a public sequence.
G1_SQL = dedent(
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
        union all
        select c.oid::regclass::text, r.role, p.privilege
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        cross join (values ('anon'), ('authenticated')) as r(role)
        cross join (values ('USAGE'), ('SELECT'), ('UPDATE')) as p(privilege)
        where n.nspname = 'public'
          and c.relkind = 'S'
          and has_sequence_privilege(r.role, c.oid, p.privilege)
        order by 1, 2, 3;
        """
)
for line in must(G1_SQL):
    failures.append(f"G1 forbidden privilege (relation, role, privilege): {line}")

g1_control = must(
    "begin;\ncreate sequence public.s1_sequence_probe;\n"
    "grant usage, update on sequence public.s1_sequence_probe to authenticated;\n"
    + G1_SQL
    + "rollback;\n"
)
if not any(line.startswith("s1_sequence_probe\t") for line in g1_control):
    failures.append(
        f"G1 negative control: guard did not report a granted sequence, got {g1_control!r}"
    )

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
        -- Explicit grants only: PUBLIC keeps EXECUTE through the global
        -- default (grantee OID 0), which a per-schema revoke cannot remove.
        -- Every function migration revokes it itself; G4 checks the result.
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


# --- G5: postgres owns every relation and function in public. An object owned
# by another role takes that role's default privileges, which this suite does
# not govern: `create extension` without `with schema extensions` puts
# supabase_admin-owned tables writable by anon into public.
G5_SQL = dedent(
    """
    select 'relation', c.oid::regclass::text, pg_get_userbyid(c.relowner)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and pg_get_userbyid(c.relowner) <> 'postgres'
    union all
    select 'function', p.oid::regprocedure::text, pg_get_userbyid(p.proowner)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and pg_get_userbyid(p.proowner) <> 'postgres'
    order by 1, 2;
    """
)
for line in must(G5_SQL):
    failures.append(f"G5 public object not owned by postgres (kind, name, owner): {line}")

g5_control = must(
    "begin;\ncreate table public.s1_owner_probe (id bigint primary key);\n"
    # A new owner needs CREATE on the schema; granted only inside this
    # rolled-back transaction.
    "grant create on schema public to service_role;\n"
    "alter table public.s1_owner_probe owner to service_role;\n"
    + G5_SQL
    + "rollback;\n"
)
if "relation\ts1_owner_probe\tservice_role" not in g5_control:
    failures.append(
        f"G5 negative control: guard did not report a foreign-owned table, got {g5_control!r}"
    )

# --- G6: every public table has RLS enabled, so B2's second layer exists for
# every table, not only the six probed below.
G6_SQL = dedent(
    """
    select c.oid::regclass::text
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity
    order by 1;
    """
)
for line in must(G6_SQL):
    failures.append(f"G6 public table without RLS: {line}")

g6_control = must(
    "begin;\ncreate table public.s1_rls_probe (id bigint primary key);\n"
    "alter table public.s1_rls_probe disable row level security;\n"
    + G6_SQL
    + "rollback;\n"
)
if "s1_rls_probe" not in g6_control:
    failures.append(
        f"G6 negative control: guard did not report a table without RLS, got {g6_control!r}"
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

# --- B3: every user sees exactly the rows the select policies define. Each
# table is compared as a row-set fingerprint (count and an md5 of the sorted
# ids), so a visible row swapped for a hidden one is caught, not only a count.
def fingerprint(table: str, predicate: str) -> str:
    return (
        f"(select count(*) || ':' || coalesce(md5(string_agg(id::text, ',' order by id)), '-') "
        f"from public.{table} {predicate})"
    )


MEMBER_ORGS = "(select organization_id from member_orgs)"
SONG_ORGS = "(select organization_id from song_orgs)"
POLICY_PREDICATES = {
    "organizations": f"where id in {MEMBER_ORGS}",
    "groups": f"where organization_id in {MEMBER_ORGS}",
    "memberships": f"where organization_id in {MEMBER_ORGS}",
    "songs": f"where organization_id in {SONG_ORGS}",
    "attachments": f"where organization_id in {SONG_ORGS}",
    "plans": f"where organization_id in {MEMBER_ORGS}",
    "sessions": f"where organization_id in {MEMBER_ORGS}",
    "session_items": f"where organization_id in {MEMBER_ORGS}",
}
EXPECTED_ROWS = (
    dedent(
        """
        with member_orgs as (
          select organization_id from public.memberships
          where user_id = '{user}' and status = 'active'
        ),
        song_orgs as (
          select organization_id from public.memberships
          where user_id = '{user}' and status = 'active' and scope_type = 'organization'
        )
        """
    )
    + "select 'expected', "
    + ", ".join(fingerprint(table, POLICY_PREDICATES[table]) for table in VISIBILITY_TABLES)
    + ";\n"
)
ACTUAL_ROWS = (
    "select 'actual', "
    + ", ".join(fingerprint(table, "") for table in VISIBILITY_TABLES)
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
        + EXPECTED_ROWS.replace("{user}", user)
        + as_user(user)
        + ACTUAL_ROWS
        + "reset role;\nrollback;\n"
    )
    expected = row(lines, "expected")
    actual = row(lines, "actual")
    if expected is None or actual is None or expected != actual:
        failures.append(
            f"B3 {label}: visible rows {dict(zip(VISIBILITY_TABLES, actual or []))} "
            f"differ from policy rows {dict(zip(VISIBILITY_TABLES, expected or []))}"
        )
        continue
    for index, value in enumerate(expected):
        if int(value.split(":", 1)[0]) > 0:
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
    "without explicit API-role grants (G3), no definer function is open to anon "
    "(G4), postgres owns every public object and every table has RLS (G5, G6), direct "
    "writes are denied by grants and by RLS (B1, B2), reads are unchanged (B3), "
    "and get_my_capabilities/delete_account work as authenticated (B4)."
)
PY
