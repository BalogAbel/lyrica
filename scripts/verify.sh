#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

skip_migrations="${1:-}"
dart_bin="${DART_BIN:-dart}"
flutter_bin="${FLUTTER_BIN:-flutter}"
check_migrations_script="${CHECK_MIGRATIONS_SCRIPT:-./scripts/check-migrations.sh}"
supabase_script="${SUPABASE_SCRIPT:-./scripts/supabase.sh}"
db_reset_script="${DB_RESET_SCRIPT:-./scripts/db-reset.sh}"
provision_demo_user_script="${PROVISION_DEMO_USER_SCRIPT:-./scripts/provision-local-demo-user.sh}"
provision_demo_user_test_script="${PROVISION_DEMO_USER_TEST_SCRIPT:-bash ./scripts/tests/provision-local-demo-user-test.sh}"
manual_validation_scripts_test_script="${MANUAL_VALIDATION_SCRIPTS_TEST_SCRIPT:-./scripts/tests/local-first-manual-validation-scripts-test.sh}"

(cd apps/lyron_app && "$dart_bin" format --output=none --set-exit-if-changed lib test)
(cd apps/lyron_app && "$flutter_bin" analyze)
(cd apps/lyron_app && "$flutter_bin" test)

if [[ "$skip_migrations" == "--skip-migrations" ]]; then
  exit 0
fi

"$check_migrations_script"
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

"$manual_validation_scripts_test_script"
