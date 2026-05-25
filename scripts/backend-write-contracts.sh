#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

planning_write_contract_test_script="${PLANNING_WRITE_CONTRACT_TEST_SCRIPT:-./scripts/tests/planning-write-contract-test.sh}"
song_crud_write_contract_test_script="${SONG_CRUD_WRITE_CONTRACT_TEST_SCRIPT:-./scripts/tests/song-crud-write-contract-test.sh}"
supabase_script="${SUPABASE_SCRIPT:-./scripts/supabase.sh}"
db_reset_script="${DB_RESET_SCRIPT:-./scripts/db-reset.sh}"
provision_demo_user_script="${PROVISION_DEMO_USER_SCRIPT:-./scripts/provision-local-demo-user.sh}"

"$supabase_script" start >/dev/null
"$db_reset_script" >/dev/null

status_env="$("$supabase_script" status -o env)"
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

"$provision_demo_user_script" >/dev/null

BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$planning_write_contract_test_script"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$song_crud_write_contract_test_script"

organization_read_only_test_script="${ORGANIZATION_READ_ONLY_TEST_SCRIPT:-./scripts/tests/organization-read-only-role-test.sh}"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$organization_read_only_test_script"
