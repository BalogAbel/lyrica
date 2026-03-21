#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/supabase.sh db query < supabase/seed/seed.sql
