#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! compgen -G "supabase/migrations/*.sql" >/dev/null; then
  echo "No Supabase migrations found under supabase/migrations/."
  exit 1
fi

./scripts/supabase.sh db lint
