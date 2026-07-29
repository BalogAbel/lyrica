#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

if [[ "${BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP:-0}" != "1" ]]; then
  ./scripts/supabase.sh start >/dev/null
  ./scripts/db-reset.sh >/dev/null
  ./scripts/provision-local-demo-user.sh >/dev/null
fi

db_container_name="$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1)"

if [[ -z "$db_container_name" ]]; then
  echo "Could not find the local Supabase database container." >&2
  exit 1
fi

python3 - "$db_container_name" <<'PY'
import subprocess
import sys
from textwrap import dedent

container = sys.argv[1]
demo_email = "demo@lyron.local"

# Security helpers that must run with a pinned, non-mutable search_path.
required_search_path = ["current_organization_ids", "get_my_capabilities", "has_capability"]

# Helpers that must additionally run as security definer. has_capability and
# current_organization_ids are read from inside RLS policies on
# public.memberships (the "memberships are manageable by capability" ALL
# policy, via can_manage_membership) - without security definer their own
# read of public.memberships re-enters that same policy and recurses until
# "stack depth limit exceeded". get_my_capabilities and can_manage_membership
# are intentionally invoker-rights and are not asserted here.
required_security_definer = ["current_organization_ids", "has_capability"]


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def run_sql(sql):
    cmd = ["docker", "exec", "-i", container, "psql", "-U", "postgres",
           "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-X", "-qAt",
           "-F", "\t", "-c", sql]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"sql failed: {sql}\nstderr: {result.stderr}")
    return result.stdout.strip()


def run_sql_capture(sql):
    cmd = ["docker", "exec", "-i", container, "psql", "-U", "postgres",
           "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-X", "-qAt",
           "-F", "\t", "-c", sql]
    return subprocess.run(cmd, capture_output=True, text=True)


out = run_sql(
    """
    select p.proname, coalesce(array_to_string(p.proconfig, ','), ''), p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('has_capability', 'get_my_capabilities', 'current_organization_ids')
    order by p.proname;
    """
)

info_by_name = {}
for line in out.splitlines():
    if not line.strip():
        continue
    name, _, rest = line.partition("\t")
    config, _, secdef = rest.partition("\t")
    info_by_name[name] = (config, secdef)

failures = []
for name in required_search_path:
    info = info_by_name.get(name)
    if info is None:
        failures.append(f"{name}: function not found in schema public")
        continue
    config, _secdef = info
    if "search_path=public" not in config:
        failures.append(f"{name}: proconfig lacks search_path=public (got: {config!r})")

for name in required_security_definer:
    info = info_by_name.get(name)
    if info is None:
        failures.append(f"{name}: function not found in schema public")
        continue
    _config, secdef = info
    if secdef != "t":
        failures.append(f"{name}: prosecdef is not true (got: {secdef!r}) - not security definer")

# Behavioural guard: an authenticated read of public.memberships must not
# recurse through the "memberships are manageable by capability" policy.
#
# That policy only gets evaluated for rows the *other*, non-recursive SELECT
# policy ("memberships are visible inside organization", driven by
# current_organization_ids()) does not already make visible - a demo user
# reading only their own membership row short-circuits before ever calling
# has_capability. So this probe seeds a second membership row, in an
# organization the demo user does not belong to, inside the same
# begin/rollback block used to switch role - it is never committed.
other_org_id = "11111111-1111-1111-1111-111111111112"
other_user_id = "99999999-9999-9999-9999-999999999999"

demo_user_id = run_sql(f"select id from auth.users where email = {sql_quote(demo_email)} limit 1;")

if not demo_user_id:
    failures.append(
        f"could not find demo user ({demo_email}) to exercise an authenticated memberships read"
    )
else:
    membership_probe_sql = dedent(f"""
        begin;
        insert into auth.users (id, email)
          values ({sql_quote(other_user_id)}, 'capability-contract-probe@lyron.local')
          on conflict (id) do nothing;
        insert into public.memberships
          (organization_id, user_id, scope_type, role_code, status)
        values
          ({sql_quote(other_org_id)}, {sql_quote(other_user_id)}, 'organization',
           'organization_member', 'active')
          on conflict do nothing;
        select set_config('request.jwt.claim.sub', {sql_quote(demo_user_id)}, true);
        select set_config('request.jwt.claim.role', 'authenticated', true);
        set local role authenticated;
        select count(*) from public.memberships;
        rollback;
    """)
    probe = run_sql_capture(membership_probe_sql)
    if probe.returncode != 0:
        failures.append(
            "authenticated 'select count(*) from public.memberships' failed "
            "(has_capability RLS recursion?): " + probe.stderr.strip()
        )

if failures:
    raise SystemExit(
        "capability security-helper guard failed "
        "(search_path / security definer / memberships-read recursion):\n  "
        + "\n  ".join(failures)
    )

print(
    "capability security-helper guard passed: search_path=public pinned, "
    "has_capability/current_organization_ids are security definer, and an "
    "authenticated memberships read does not recurse."
)
PY
