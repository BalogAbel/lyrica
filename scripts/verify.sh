#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

skip_migrations="${1:-}"

(cd apps/lyrica_app && dart format --output=none --set-exit-if-changed lib test)
(cd apps/lyrica_app && flutter analyze)
(cd apps/lyrica_app && flutter test)

if [[ "$skip_migrations" == "--skip-migrations" ]]; then
  exit 0
fi

./scripts/check-migrations.sh
./scripts/supabase.sh start
./scripts/db-reset.sh
./scripts/provision-local-demo-user.sh

status_env="$(./scripts/supabase.sh status -o env)"
eval "$status_env"

if [[ -z "${API_URL:-}" || -z "${ANON_KEY:-}" ]]; then
  echo "Local Supabase did not return API_URL and ANON_KEY." >&2
  exit 1
fi

(
  cd apps/lyrica_app &&
    flutter test test/integration/authenticated_song_reader_flow_test.dart \
      --dart-define=SUPABASE_URL="$API_URL" \
      --dart-define=SUPABASE_ANON_KEY="$ANON_KEY"
)
