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


def redeem_payload(user_id, token):
    raw = redeem_as(user_id, token)
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"status": f"<unparsable: {raw!r}>"}


def attempt_rows(user_id):
    out = run_sql(dedent(f"""
        select outcome, coalesce(invitation_id::text, ''),
               coalesce(organization_id::text, ''), length(token_sha256)
        from public.invitation_redemption_attempts
        where actor_user_id = {sql_quote(user_id)}
        order by created_at;
    """))
    rows = []
    for line in out.splitlines():
        if line.strip():
            rows.append(line.split("\t"))
    return rows


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

# --- Case 4: the successful bearer redemption from case 1 was audited. -------
rows = attempt_rows(BEARER_USER)
check(
    "case 4 success audited",
    len(rows) == 1 and rows[0][0] == "redeemed" and rows[0][1] != ""
    and rows[0][2] == ORG_ID and rows[0][3] == "32",
    f"expected one audited 'redeemed' attempt with a 32-byte digest, got: {rows!r}",
)

# --- Case 5: an unknown token returns not_found and audits a null invitation. -
make_user(WRONG_USER, "wrong@lyron.local")
payload = redeem_payload(WRONG_USER, "definitely-not-a-real-token")
check(
    "case 5 not_found status",
    payload.get("status") == "not_found" and payload.get("organization_id") is None,
    f"unknown token must return not_found, got: {payload!r}",
)
rows = attempt_rows(WRONG_USER)
check(
    "case 5 not_found audited",
    len(rows) == 1 and rows[0][0] == "not_found" and rows[0][1] == ""
    and rows[0][2] == "" and rows[0][3] == "32",
    f"expected an audited not_found attempt with no invitation, got: {rows!r}",
)

# --- Case 6: a second redemption of the same token reports already_redeemed. --
SECOND_USER = "aaaaaaa1-0000-0000-0000-000000000004"
make_user(SECOND_USER, "second@lyron.local")
payload = redeem_payload(SECOND_USER, bearer_token)
check(
    "case 6 already_redeemed",
    payload.get("status") == "already_redeemed",
    f"a spent token must report already_redeemed, got: {payload!r}",
)

# --- Case 7: an expired invitation reports expired. --------------------------
EXPIRED_USER = "aaaaaaa1-0000-0000-0000-000000000005"
make_user(EXPIRED_USER, "expired@lyron.local")
expired_token = make_invitation(email=None)
run_sql(
    "update public.invitations set expires_at = now() - interval '1 day' "
    f"where token = {sql_quote(expired_token)};"
)
payload = redeem_payload(EXPIRED_USER, expired_token)
check(
    "case 7 expired",
    payload.get("status") == "expired",
    f"an expired token must report expired, got: {payload!r}",
)

# --- Case 8: an existing member reports already_member. ----------------------
member_token = make_invitation(email=None)
payload = redeem_payload(BEARER_USER, member_token)
check(
    "case 8 already_member",
    payload.get("status") == "already_member",
    f"an existing member must report already_member, got: {payload!r}",
)

# --- Case 9: no failed outcome may create a membership. ----------------------
membership_count = run_sql(dedent(f"""
    select count(*) from public.memberships
    where user_id in ({sql_quote(WRONG_USER)}, {sql_quote(SECOND_USER)},
                      {sql_quote(EXPIRED_USER)})
      and status = 'active';
"""))
check(
    "case 9 no membership from failures",
    membership_count == "0",
    f"failed redemptions must not create memberships, got {membership_count}",
)

# --- Case 10: grants survived the drop-and-recreate. -------------------------
grants = run_sql(dedent("""
    select
      has_function_privilege('authenticated', 'public.redeem_invitation(text)', 'execute'),
      has_function_privilege('anon', 'public.redeem_invitation(text)', 'execute'),
      has_function_privilege('authenticated',
        'public.record_invitation_redemption_attempt('
        'uuid, bytea, uuid, public.invitation_redemption_outcome, uuid)', 'execute');
""")).split("\t")
check(
    "case 10 execute grants",
    grants == ["t", "f", "f"],
    "expected redeem_invitation executable by authenticated only and the audit "
    f"helper executable by neither, got: {grants!r}",
)

# --- Case 11: an email-bound invitation redeems for the invited address. ------
make_user(BOUND_USER, "bound@lyron.local")
bound_token = make_invitation(email="BOUND@Lyron.local  ")
payload = redeem_payload(BOUND_USER, bound_token)
check(
    "case 11 bound redemption",
    payload.get("status") == "redeemed" and payload.get("organization_id") == ORG_ID,
    f"invited address must redeem, case-and-whitespace-insensitively, got: {payload!r}",
)

# --- Case 12: a different caller cannot redeem an email-bound invitation. -----
MISMATCH_USER = "aaaaaaa1-0000-0000-0000-000000000006"
make_user(MISMATCH_USER, "someone.else@lyron.local")
mismatch_token = make_invitation(email="invited@lyron.local")
payload = redeem_payload(MISMATCH_USER, mismatch_token)
check(
    "case 12 email_mismatch",
    payload.get("status") == "email_mismatch",
    f"a non-invited caller must be refused, got: {payload!r}",
)
still_open = run_sql(
    "select redeemed_at is null from public.invitations "
    f"where token = {sql_quote(mismatch_token)};"
)
check(
    "case 12 invitation untouched",
    still_open == "t",
    "a refused redemption must leave the invitation unredeemed",
)
membership_count = run_sql(
    "select count(*) from public.memberships "
    f"where user_id = {sql_quote(MISMATCH_USER)} and status = 'active';"
)
check(
    "case 12 no membership",
    membership_count == "0",
    f"email mismatch must not create a membership, got {membership_count}",
)
rows = attempt_rows(MISMATCH_USER)
check(
    "case 12 mismatch audited",
    len(rows) == 1 and rows[0][0] == "email_mismatch" and rows[0][1] != ""
    and rows[0][2] == ORG_ID,
    f"expected one audited email_mismatch attempt against the org, got: {rows!r}",
)

# --- Case 13: unconfirmed and address-less callers are refused too. -----------
UNCONFIRMED_USER = "aaaaaaa1-0000-0000-0000-000000000007"
make_user(UNCONFIRMED_USER, "unconfirmed@lyron.local", confirmed=False)
unconfirmed_token = make_invitation(email="unconfirmed@lyron.local")
payload = redeem_payload(UNCONFIRMED_USER, unconfirmed_token)
check(
    "case 13 unconfirmed refused",
    payload.get("status") == "email_mismatch",
    f"an unconfirmed address must not satisfy the binding, got: {payload!r}",
)

NO_EMAIL_USER = "aaaaaaa1-0000-0000-0000-000000000008"
make_user(NO_EMAIL_USER, None)
no_email_token = make_invitation(email="anybody@lyron.local")
payload = redeem_payload(NO_EMAIL_USER, no_email_token)
check(
    "case 13 address-less refused",
    payload.get("status") == "email_mismatch",
    f"a caller with no address must be refused, got: {payload!r}",
)

# --- Case 14: ten suspicious attempts trip the limit for a valid token. ------
PROBER_USER = "aaaaaaa1-0000-0000-0000-000000000009"
make_user(PROBER_USER, "prober@lyron.local")
valid_token = make_invitation(email=None)

for i in range(10):
    payload = redeem_payload(PROBER_USER, f"guess-{i}")
    check(
        f"case 14 probe {i} not_found",
        payload.get("status") == "not_found",
        f"probe {i} should report not_found, got: {payload!r}",
    )

payload = redeem_payload(PROBER_USER, valid_token)
check(
    "case 14 rate limited",
    payload.get("status") == "rate_limited",
    f"the 11th attempt must be rate limited even with a valid token, got: {payload!r}",
)
membership_count = run_sql(
    "select count(*) from public.memberships "
    f"where user_id = {sql_quote(PROBER_USER)} and status = 'active';"
)
check(
    "case 14 no membership while limited",
    membership_count == "0",
    f"a rate-limited call must not create a membership, got {membership_count}",
)
check(
    "case 14 token still redeemable",
    run_sql("select redeemed_at is null from public.invitations "
            f"where token = {sql_quote(valid_token)};") == "t",
    "a rate-limited call must leave the invitation unredeemed",
)

# --- Case 15: benign outcomes do not accumulate toward the limit. ------------
PATIENT_USER = "aaaaaaa1-0000-0000-0000-00000000000a"
make_user(PATIENT_USER, "patient@lyron.local")
spent_token = make_invitation(email=None)
run_sql(dedent(f"""
    update public.invitations
    set redeemed_at = now(), redeemed_by = {sql_quote(BEARER_USER)}
    where token = {sql_quote(spent_token)};
"""))
for i in range(12):
    payload = redeem_payload(PATIENT_USER, spent_token)
    check(
        f"case 15 benign attempt {i}",
        payload.get("status") == "already_redeemed",
        f"benign retry {i} must stay already_redeemed, got: {payload!r}",
    )

patient_token = make_invitation(email=None)
payload = redeem_payload(PATIENT_USER, patient_token)
check(
    "case 15 not locked out",
    payload.get("status") == "redeemed",
    f"benign retries must not lock a real user out, got: {payload!r}",
)

# --- Case 16: audit rows have a scheduled retention job. ---------------------
retention = run_sql(dedent("""
    select coalesce(string_agg(jobname || '|' || schedule, ','), '')
    from cron.job
    where jobname = 'cleanup-invitation-redemption-attempts';
"""))
check(
    "case 16 retention job",
    retention.startswith("cleanup-invitation-redemption-attempts|"),
    f"expected a scheduled retention job for the audit table, got: {retention!r}",
)

if failures:
    raise SystemExit(
        "SEC-1 invitation redemption contract failed:\n  " + "\n  ".join(failures)
    )

print("SEC-1 invitation redemption contract passed.")
PY
