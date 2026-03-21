#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/supabase.sh start
