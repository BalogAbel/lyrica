#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

./scripts/supabase.sh start >/dev/null
./scripts/db-reset.sh >/dev/null
./scripts/provision-local-demo-user.sh >/dev/null
./scripts/provision-local-demo-user.sh >/dev/null

query_result="$(
  ./scripts/supabase.sh db query "
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
)"

membership_count="$(
  QUERY_RESULT="$query_result" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["QUERY_RESULT"])
rows = payload.get("rows", [])
if len(rows) != 1:
    raise SystemExit(f"unexpected rows: {rows!r}")
print(rows[0]["membership_count"])
PY
)"

if [[ "$membership_count" != "1" ]]; then
  echo "expected one demo organization membership, got $membership_count" >&2
  exit 1
fi
