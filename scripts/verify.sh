#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

skip_migrations=0
skip_backend_write_contracts=0
dart_bin="${DART_BIN:-dart}"
flutter_bin="${FLUTTER_BIN:-flutter}"
check_migrations_script="${CHECK_MIGRATIONS_SCRIPT:-./scripts/check-migrations.sh}"
supabase_script="${SUPABASE_SCRIPT:-./scripts/supabase.sh}"
db_reset_script="${DB_RESET_SCRIPT:-./scripts/db-reset.sh}"
supabase_cleanup_script="${SUPABASE_CLEANUP_SCRIPT:-./scripts/supabase-cleanup.sh}"
provision_demo_user_script="${PROVISION_DEMO_USER_SCRIPT:-./scripts/provision-local-demo-user.sh}"
provision_demo_user_test_script="${PROVISION_DEMO_USER_TEST_SCRIPT:-bash ./scripts/tests/provision-local-demo-user-test.sh}"
manual_validation_scripts_test_script="${MANUAL_VALIDATION_SCRIPTS_TEST_SCRIPT:-./scripts/tests/local-first-manual-validation-scripts-test.sh}"
backend_write_contracts_script="${BACKEND_WRITE_CONTRACTS_SCRIPT:-./scripts/backend-write-contracts.sh}"
coverage_gate_script="${COVERAGE_GATE_SCRIPT:-./scripts/coverage-gate.sh}"
dependency_audit_script="${DEPENDENCY_AUDIT_SCRIPT:-./scripts/dependency-audit.sh}"

for arg in "$@"; do
  case "$arg" in
  --skip-migrations)
    skip_migrations=1
    ;;
  --skip-backend-write-contracts)
    skip_backend_write_contracts=1
    ;;
  *)
    echo "Usage: ./scripts/verify.sh [--skip-migrations] [--skip-backend-write-contracts]" >&2
    exit 1
    ;;
  esac
done

(cd apps/lyron_app && "$dart_bin" format --output=none --set-exit-if-changed lib test)
(cd apps/lyron_app && "$flutter_bin" analyze)
(cd apps/lyron_app && "$flutter_bin" test --coverage)
"$coverage_gate_script"
"$dependency_audit_script"

if [[ "$skip_migrations" -eq 1 ]]; then
  exit 0
fi

"$check_migrations_script"

if [[ "$skip_backend_write_contracts" -eq 0 ]]; then
  "$backend_write_contracts_script"
fi

"$supabase_cleanup_script"
"$db_reset_script"
"$provision_demo_user_script"
eval "$provision_demo_user_test_script"

status_env="$("$supabase_script" status -o env)"
eval "$status_env"

if [[ -z "${API_URL:-}" || -z "${ANON_KEY:-}" || -z "${SERVICE_ROLE_KEY:-}" ]]; then
  echo "Local Supabase did not return API_URL, ANON_KEY, and SERVICE_ROLE_KEY." >&2
  exit 1
fi

(
  cd apps/lyron_app &&
    "$flutter_bin" test test/integration/authenticated_song_reader_flow_test.dart \
      --dart-define=SUPABASE_URL="$API_URL" \
      --dart-define=SUPABASE_ANON_KEY="$ANON_KEY" \
      --dart-define=SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
)

(
  cd apps/lyron_app &&
    "$flutter_bin" test test/integration/local_first_authenticated_song_reader_flow_test.dart \
      --dart-define=SUPABASE_URL="$API_URL" \
      --dart-define=SUPABASE_ANON_KEY="$ANON_KEY" \
      --dart-define=SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
)

(
  cd apps/lyron_app &&
    "$flutter_bin" test test/integration/plan_and_session_flow_test.dart \
      --dart-define=SUPABASE_URL="$API_URL" \
      --dart-define=SUPABASE_ANON_KEY="$ANON_KEY"
)

(
  cd apps/lyron_app &&
    "$flutter_bin" test test/integration/local_first_planning_read_flow_test.dart \
      --dart-define=SUPABASE_URL="$API_URL" \
      --dart-define=SUPABASE_ANON_KEY="$ANON_KEY"
)

(
  cd apps/lyron_app &&
    "$flutter_bin" test test/integration/offline_edit_relaunch_sync_flow_test.dart \
      --dart-define=SUPABASE_URL="$API_URL" \
      --dart-define=SUPABASE_ANON_KEY="$ANON_KEY"
)

(
  cd apps/lyron_app &&
    "$flutter_bin" test test/integration/two_device_conflict_matrix_test.dart \
      --dart-define=SUPABASE_URL="$API_URL" \
      --dart-define=SUPABASE_ANON_KEY="$ANON_KEY"
)

"$manual_validation_scripts_test_script"
