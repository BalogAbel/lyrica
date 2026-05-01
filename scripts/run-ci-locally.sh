#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

job="${1:-all}"
bootstrap_script="${BOOTSTRAP_SCRIPT:-./scripts/bootstrap.sh}"
bootstrap_supabase_script="${BOOTSTRAP_SUPABASE_SCRIPT:-./scripts/bootstrap-supabase.sh}"
verify_script="${VERIFY_SCRIPT:-./scripts/verify.sh}"
check_migrations_script="${CHECK_MIGRATIONS_SCRIPT:-./scripts/check-migrations.sh}"
backend_write_contracts_script="${BACKEND_WRITE_CONTRACTS_SCRIPT:-./scripts/backend-write-contracts.sh}"

case "$job" in
all)
  "$bootstrap_script"
  "$verify_script" --skip-backend-write-contracts
  "$bootstrap_supabase_script"
  "$backend_write_contracts_script"
  "$bootstrap_supabase_script"
  "$check_migrations_script"
  ;;
verify)
  "$bootstrap_script"
  "$verify_script" --skip-backend-write-contracts
  ;;
backend-write-contracts)
  "$bootstrap_supabase_script"
  "$backend_write_contracts_script"
  ;;
migrations)
  "$bootstrap_supabase_script"
  "$check_migrations_script"
  ;;
*)
  echo "Usage: ./scripts/run-ci-locally.sh [all|verify|backend-write-contracts|migrations]" >&2
  exit 1
  ;;
esac
