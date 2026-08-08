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
import sys
import subprocess
from textwrap import dedent

container = sys.argv[1]

ORG_ID = "11111111-1111-1111-1111-111111111111"

failures = []


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


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}: {detail}")


def create_invitation_as_role(role):
    """Call create_invitation with the session role set directly and no JWT
    claims at all (no request.jwt.claim.sub, no request.jwt.claim.role) --
    the raw-SQL-harness way to reproduce a session whose Postgres role is
    `role` but whose auth.uid() is null, independent of that role. Real
    PostgREST always sets both together; this harness can pull them apart,
    which is exactly the drift SEC-2 defends against.

    Wrapped in begin/rollback so a successful call leaves no invitation row
    behind -- each run_sql invocation is its own psql session, so nothing
    but an explicit rollback would otherwise undo the insert.
    """
    sql = dedent(f"""
        begin;
        set local role {role};
        select public.create_invitation(
          {sql_quote(ORG_ID)}::uuid,
          'organization_member'::public.role_code,
          null
        );
        rollback;
    """)
    return run_sql(sql)


def create_invitation_error_as_role(role):
    """Same caller shape as create_invitation_as_role, but captures the
    raised exception's SQLSTATE and message instead of letting psql fail,
    so the test can assert on the exact errcode rather than scraping
    stderr text.
    """
    sql = dedent(f"""
        set local role {role};
        create temp table if not exists sec2_error_capture (
          sqlstate text,
          message text
        );
        truncate sec2_error_capture;
        do $$
        declare
          v_sqlstate text;
          v_message text;
        begin
          begin
            perform public.create_invitation(
              {sql_quote(ORG_ID)}::uuid,
              'organization_member'::public.role_code,
              null
            );
          exception when others then
            get stacked diagnostics
              v_sqlstate = RETURNED_SQLSTATE,
              v_message = MESSAGE_TEXT;
            insert into sec2_error_capture values (v_sqlstate, v_message);
          end;
        end $$;
        select sqlstate, message from sec2_error_capture limit 1;
    """)
    row = run_sql(sql).split("\t")
    if len(row) != 2:
        raise SystemExit(
            f"expected create_invitation to raise for role={role!r} but it "
            f"did not (no row captured); raw output: {row!r}"
        )
    return row[0], row[1]


# --- Case A: the SEC-2 gap. authenticated role, auth.uid() null. -------------
# set local role authenticated WITHOUT request.jwt.claim.sub: the physical
# session role has EXECUTE on create_invitation, but auth.uid() is null.
# Before the fix, create_invitation treats null auth.uid() as automatic
# passage (no admin check, no role check) and this call SUCCEEDS -- the bug.
# After the fix, the null-caller branch must assert the session role is
# actually service_role and reject this case with 42501.
sqlstate, message = create_invitation_error_as_role("authenticated")
check(
    "case A null-caller non-service_role rejected",
    sqlstate == "42501",
    f"expected 42501 when authenticated role calls create_invitation with a "
    f"null auth.uid(), got sqlstate={sqlstate!r} message={message!r}",
)
# 42501 alone is also raised by a bare privilege-check failure (e.g. if the
# authenticated EXECUTE grant were ever revoked) -- pin the message too, so
# this test fails for the right reason if that grant ever changes.
check(
    "case A null-caller rejection is the SEC-2 gate, not a bare grant failure",
    message == "invitation_create_not_authorized",
    f"expected message='invitation_create_not_authorized', got {message!r}",
)

# --- Case B: the real null-caller path. service_role must still work. --------
token = create_invitation_as_role("service_role")
check(
    "case B service_role still creates invitations",
    bool(token) and len(token) > 0,
    f"service_role must still be able to create invitations with a null "
    f"auth.uid(), got: {token!r}",
)

if failures:
    raise SystemExit(
        "SEC-2 create_invitation service_role gate contract failed:\n  "
        + "\n  ".join(failures)
    )

print("SEC-2 create_invitation service_role gate contract passed.")
PY
