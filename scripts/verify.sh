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

if command -v supabase >/dev/null 2>&1; then
  ./scripts/check-migrations.sh
else
  echo "Skipping migration lint because Supabase CLI is not installed."
fi
