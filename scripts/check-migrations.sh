#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! compgen -G "supabase/migrations/*.sql" >/dev/null; then
  echo "No Supabase migrations found under supabase/migrations/."
  exit 1
fi

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI is required for migration checks."
  exit 1
fi

supabase db lint
