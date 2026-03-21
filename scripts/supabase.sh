#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TOOLING_DIR="$REPO_ROOT/tooling/supabase"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js and npm are required to run Supabase tooling." >&2
  echo "Install them first, then run: npm ci --prefix tooling/supabase" >&2
  exit 1
fi

if [ ! -d "$TOOLING_DIR/node_modules" ]; then
  echo "Supabase tooling dependencies are not installed." >&2
  echo "Run: npm ci --prefix tooling/supabase" >&2
  exit 1
fi

exec npx --prefix "$TOOLING_DIR" supabase "$@"
