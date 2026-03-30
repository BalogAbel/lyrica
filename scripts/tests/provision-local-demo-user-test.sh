#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

supabase_script="${SUPABASE_SCRIPT:-./scripts/supabase.sh}"
db_reset_script="${DB_RESET_SCRIPT:-./scripts/db-reset.sh}"
provision_demo_user_script="${PROVISION_DEMO_USER_SCRIPT:-./scripts/provision-local-demo-user.sh}"
sleep_bin="${SLEEP_BIN:-sleep}"
max_attempts="${PROVISION_USER_QUERY_MAX_ATTEMPTS:-5}"
retry_delay_seconds="${PROVISION_USER_QUERY_RETRY_DELAY_SECONDS:-1}"

membership_count_query="
  select count(*) as membership_count
  from public.memberships
  where organization_id = '11111111-1111-1111-1111-111111111111'
    and group_id is null
    and role_code = 'organization_member'
    and user_id = (
      select id
      from auth.users
      where email = 'demo@lyrica.local'
    );
"

auth_user_lookup_query="
  select id, email
  from auth.users
  where email = 'demo@lyrica.local';
"

"$supabase_script" start >/dev/null
"$db_reset_script" >/dev/null
"$provision_demo_user_script" >/dev/null
"$provision_demo_user_script" >/dev/null

extract_membership_count() {
  local query_result="$1"

  QUERY_RESULT="$query_result" REPO_ROOT="$repo_root" python3 - <<'PY'
import json
import os
import subprocess

payload = json.loads(
    subprocess.check_output(
        ["python3", f"{os.environ['REPO_ROOT']}/scripts/extract_supabase_json.py"],
        input=os.environ["QUERY_RESULT"],
        text=True,
    )
)
rows = payload if isinstance(payload, list) else payload.get("rows", [])
if len(rows) != 1:
    raise SystemExit(f"unexpected rows: {rows!r}")
print(rows[0]["membership_count"])
PY
}

query_result=""
membership_count=""

for attempt in $(seq 1 "$max_attempts"); do
  query_result="$("$supabase_script" db query -o json "$membership_count_query")"
  if membership_count="$(extract_membership_count "$query_result" 2>/dev/null)"; then
    break
  fi

  if [[ "$attempt" -lt "$max_attempts" ]]; then
    "$sleep_bin" "$retry_delay_seconds"
  fi
done

if [[ -z "$membership_count" ]]; then
  echo "Provisioning verification could not resolve the demo membership after $max_attempts attempts." >&2
  echo "Diagnostic auth.users lookup:" >&2
  "$supabase_script" db query -o json "$auth_user_lookup_query" >&2 || true
  echo "Diagnostic membership lookup:" >&2
  "$supabase_script" db query -o json "$membership_count_query" >&2 || true
  exit 1
fi

if [[ "$membership_count" != "1" ]]; then
  echo "expected one demo organization membership, got $membership_count" >&2
  exit 1
fi
