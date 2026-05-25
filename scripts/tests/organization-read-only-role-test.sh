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
org_id = "11111111-1111-1111-1111-111111111111"
guest_id = "77777777-7777-7777-7777-777777777777"


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def run_sql(sql, expect_error=False):
    cmd = ["docker", "exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres",
           "-v", "ON_ERROR_STOP=1", "-X", "-qAt", "-F", "\t", "-c", sql]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if expect_error:
        if result.returncode == 0:
            raise SystemExit(f"expected failure, got success for: {sql}")
        return result.stderr
    if result.returncode != 0:
        raise SystemExit(f"sql failed: {sql}\nstderr: {result.stderr}")
    return result.stdout.strip()


def run_sql_as_user(sql, user_id):
    full_sql = dedent(f"""
        do $$
        begin
          perform set_config('request.jwt.claim.sub', {sql_quote(user_id)}, true);
          perform set_config('request.jwt.claim.role', 'authenticated', true);
        end $$;
        {sql}
    """)
    return run_sql(full_sql)


# 1. Enum value is present.
out = run_sql("select 'organization_read_only'::public.role_code;")
assert "organization_read_only" in out, out

# 2. Org-scope insert succeeds; group-scope insert fails.
run_sql(dedent(f"""
    insert into auth.users (id, email)
      values ('{guest_id}', 'guest@lyron.local')
      on conflict (id) do nothing;
    insert into public.memberships
      (organization_id, user_id, scope_type, role_code, status)
    values
      ('{org_id}', '{guest_id}', 'organization', 'organization_read_only', 'active')
      on conflict do nothing;
"""))

err = run_sql(dedent(f"""
    insert into public.memberships
      (organization_id, user_id, group_id, scope_type, role_code, status)
    values
      ('{org_id}', '{guest_id}',
       '22222222-2222-2222-2222-222222222222',
       'group', 'organization_read_only', 'active');
"""), expect_error=True)
assert "memberships_role_scope_consistency" in err, err

# 3. has_capability returns true for canViewSongs and false for writes when
#    auth.uid() is the guest user.
def cap(name, group_id="null"):
    return run_sql_as_user(
        f"select public.has_capability('{org_id}', '{name}', {group_id});",
        guest_id,
    )

assert "t" in cap("canViewSongs"), cap("canViewSongs")
for write_cap in ("canEditSongs", "canManagePlans", "canEditSessions",
                  "canManageOrganizationMembers", "canManageGroupMembers"):
    out = cap(write_cap)
    assert "f" in out, (write_cap, out)

# 4. Invitations check accepts the new role and rejects unknown ones.
run_sql(dedent(f"""
    insert into public.invitations
      (token, organization_id, role_code, expires_at)
    values
      ('test-guest-token', '{org_id}', 'organization_read_only',
       timezone('utc', now()) + interval '7 days');
"""))

err = run_sql(dedent(f"""
    insert into public.invitations
      (token, organization_id, role_code, expires_at)
    values
      ('test-group-token', '{org_id}', 'group_member',
       timezone('utc', now()) + interval '7 days');
"""), expect_error=True)
assert "invitations_role_code_check" in err, err

# 5. Combined membership: guest (org_read_only) who also holds group_member
#    in the same org must retain group-scope write capability.
group_id = "22222222-2222-2222-2222-222222222222"

run_sql(dedent(f"""
    insert into public.memberships
      (organization_id, group_id, user_id, scope_type, role_code, status)
    values
      ('{org_id}', '{group_id}', '{guest_id}', 'group', 'group_member', 'active')
      on conflict do nothing;
"""))

# When asked about the group scope, group_member (priority 4) wins over org_read_only (priority 5).
out = run_sql_as_user(
    f"select public.has_capability('{org_id}'::uuid, 'canEditSessions', '{group_id}'::uuid);",
    guest_id,
)
assert "t" in out, f"expected canEditSessions=true for group_member scope, got: {out!r}"

# When asked at org scope (no group_id), org_read_only wins — write cap still false.
out = run_sql_as_user(
    f"select public.has_capability('{org_id}'::uuid, 'canEditSongs');",
    guest_id,
)
assert "f" in out, f"expected canEditSongs=false for org_read_only scope, got: {out!r}"

print("organization-read-only-role-test combined-membership OK")
print("organization-read-only-role-test OK")
PY
