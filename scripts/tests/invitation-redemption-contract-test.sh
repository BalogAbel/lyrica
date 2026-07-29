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
import json
import subprocess
import sys
from textwrap import dedent

container = sys.argv[1]

ORG_ID = "11111111-1111-1111-1111-111111111111"
# Distinct callers so rate-limit state never leaks between cases.
BEARER_USER = "aaaaaaa1-0000-0000-0000-000000000001"
BOUND_USER = "aaaaaaa1-0000-0000-0000-000000000002"
WRONG_USER = "aaaaaaa1-0000-0000-0000-000000000003"

failures = []


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def run_sql(sql, expect_error=False):
    cmd = ["docker", "exec", "-i", container, "psql", "-U", "postgres",
           "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-X", "-qAt",
           "-F", "\t", "-c", sql]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if expect_error:
        if result.returncode == 0:
            raise SystemExit(f"expected failure, got success for: {sql}")
        return result.stderr
    if result.returncode != 0:
        raise SystemExit(f"sql failed: {sql}\nstderr: {result.stderr}")
    return result.stdout.strip()


def redeem_as(user_id, token):
    """Call redeem_invitation as the given authenticated caller."""
    sql = dedent(f"""
        do $$
        begin
          perform set_config('request.jwt.claim.sub', {sql_quote(user_id)}, true);
          perform set_config('request.jwt.claim.role', 'authenticated', true);
        end $$;
        select public.redeem_invitation({sql_quote(token)});
    """)
    return run_sql(sql)


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}: {detail}")


def make_user(user_id, email, confirmed=True):
    confirmed_at = "timezone('utc', now())" if confirmed else "null"
    email_sql = sql_quote(email) if email is not None else "null"
    run_sql(dedent(f"""
        insert into auth.users (id, email, email_confirmed_at)
          values ({sql_quote(user_id)}, {email_sql}, {confirmed_at})
          on conflict (id) do update
            set email = excluded.email,
                email_confirmed_at = excluded.email_confirmed_at;
    """))


def make_invitation(email=None, role="organization_member"):
    email_sql = sql_quote(email) if email is not None else "null"
    return run_sql(
        f"select public.create_invitation("
        f"{sql_quote(ORG_ID)}, {sql_quote(role)}::public.role_code, {email_sql});"
    )


# --- Case 1: the RPC returns a jsonb status envelope, not a bare uuid. --------
make_user(BEARER_USER, "bearer@lyron.local")
bearer_token = make_invitation(email=None)
raw = redeem_as(BEARER_USER, bearer_token)

try:
    payload = json.loads(raw)
except json.JSONDecodeError:
    payload = None

check(
    "case 1 contract shape",
    isinstance(payload, dict) and "status" in payload,
    f"redeem_invitation must return a jsonb object with a status key, got: {raw!r}",
)
check(
    "case 1 bearer redemption",
    isinstance(payload, dict) and payload.get("status") == "redeemed"
    and payload.get("organization_id") == ORG_ID,
    f"a bearer (null-email) invitation must still redeem, got: {raw!r}",
)

# --- Case 2: the outcome enum exists with the agreed values. -----------------
enum_values = run_sql(dedent("""
    select string_agg(e.enumlabel, ',' order by e.enumsortorder)
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'invitation_redemption_outcome';
"""))
check(
    "case 2 outcome enum",
    enum_values == "redeemed,not_found,expired,already_redeemed,"
                   "already_member,email_mismatch,rate_limited",
    f"unexpected invitation_redemption_outcome values: {enum_values!r}",
)

# --- Case 3: authenticated cannot write the audit table directly. ------------
for verb, statement in (
    ("insert", "insert into public.invitation_redemption_attempts "
               "(token_sha256, outcome) values (sha256('x'::bytea), 'not_found')"),
    ("update", "update public.invitation_redemption_attempts set outcome = 'redeemed'"),
    ("delete", "delete from public.invitation_redemption_attempts"),
):
    sql = dedent(f"""
        begin;
        select set_config('request.jwt.claim.sub', {sql_quote(BEARER_USER)}, true);
        select set_config('request.jwt.claim.role', 'authenticated', true);
        set local role authenticated;
        {statement};
        rollback;
    """)
    out = run_sql(sql, expect_error=True)
    check(
        f"case 3 audit {verb} denied",
        "denied" in out or "permission" in out or "violates row-level security" in out,
        f"authenticated {verb} on invitation_redemption_attempts was not denied: {out!r}",
    )

# A non-admin of the organization sees no attempt rows even though select is
# granted to authenticated: RLS scopes reads to organization admins.
run_sql(dedent(f"""
    insert into public.invitation_redemption_attempts
      (token_sha256, outcome, organization_id)
    values (sha256('rls-probe'::bytea), 'not_found', {sql_quote(ORG_ID)});
"""))
OUTSIDER = "aaaaaaa1-0000-0000-0000-0000000000ff"
make_user(OUTSIDER, "outsider@lyron.local")
visible = run_sql(dedent(f"""
    begin;
    select set_config('request.jwt.claim.sub', {sql_quote(OUTSIDER)}, true);
    select set_config('request.jwt.claim.role', 'authenticated', true);
    set local role authenticated;
    select count(*) from public.invitation_redemption_attempts;
    rollback;
""")).splitlines()[-1].strip()
check(
    "case 3 audit select scoped",
    visible == "0",
    f"a non-admin must not read another organization's attempts, saw {visible!r}",
)

if failures:
    raise SystemExit(
        "SEC-1 invitation redemption contract failed:\n  " + "\n  ".join(failures)
    )

print("SEC-1 invitation redemption contract passed.")
PY
