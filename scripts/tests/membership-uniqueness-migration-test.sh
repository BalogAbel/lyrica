#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

./scripts/supabase.sh start >/dev/null
./scripts/db-reset.sh >/dev/null
./scripts/provision-local-demo-user.sh >/dev/null

db_container_name="$(
  docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1
)"

if [[ -z "$db_container_name" ]]; then
  echo "Could not find the local Supabase database container." >&2
  exit 1
fi

user_query_result="$(
  ./scripts/supabase.sh db query "
    select id
    from auth.users
    where email = 'demo@lyrica.local';
  "
)"

user_id="$(
  QUERY_RESULT="$user_query_result" REPO_ROOT="$repo_root" python3 - <<'PY'
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
rows = payload.get("rows", [])
if len(rows) != 1:
    raise SystemExit(f"unexpected rows: {rows!r}")
raw_id = rows[0]["id"]
if isinstance(raw_id, list):
    if len(raw_id) != 16:
        raise SystemExit(f"unexpected uuid bytes: {raw_id!r}")
    hex_value = ''.join(f'{part:02x}' for part in raw_id)
    print(
        f"{hex_value[0:8]}-{hex_value[8:12]}-{hex_value[12:16]}-"
        f"{hex_value[16:20]}-{hex_value[20:32]}"
    )
else:
    print(raw_id)
PY
)"

./scripts/supabase.sh db query "
  drop index if exists public.memberships_organization_scope_unique_idx;
" >/dev/null

./scripts/supabase.sh db query "
  insert into public.memberships (organization_id, user_id, scope_type, role_code, status)
  values ('11111111-1111-1111-1111-111111111111', '$user_id', 'organization', 'organization_member', 'active');
" >/dev/null

docker exec \
  -i "$db_container_name" \
  psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  -f - \
  < supabase/migrations/20260323233000_fix_organization_membership_uniqueness.sql \
  >/dev/null
