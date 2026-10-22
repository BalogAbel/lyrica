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

# Opt-in retry for `supabase start`, meant for CI: anonymous GHCR pulls from
# shared runner IPs can hit "toomanyrequests", and the CLI's own pull retry is
# too short for that limit. Enabled by a positive integer in
# SUPABASE_START_RETRIES (retries after the first attempt). The wait before
# retry N is SUPABASE_START_RETRY_DELAY (default 30) seconds times N. Every
# other command, and `start` without the variable, keeps the plain exec path.
start_retries=${SUPABASE_START_RETRIES:-}
case "$start_retries" in
'' | *[!0-9]*) start_retries=0 ;;
esac
start_retry_delay=${SUPABASE_START_RETRY_DELAY:-30}
case "$start_retry_delay" in
'' | *[!0-9]*) start_retry_delay=30 ;;
esac

if [ "${1:-}" != "start" ] || [ "$start_retries" -eq 0 ]; then
  exec npx --prefix "$TOOLING_DIR" supabase "$@"
fi

capture_dir=$(mktemp -d)
trap 'rm -rf "$capture_dir"' EXIT
attempt=0

while :; do
  # Stream stdout and stderr to their own streams while keeping a copy of
  # each, and carry the CLI's exit code out of the pipeline through a file.
  {
    {
      cli_status=0
      npx --prefix "$TOOLING_DIR" supabase "$@" || cli_status=$?
      echo "$cli_status" >"$capture_dir/status"
    } 2>&1 1>&3 | tee "$capture_dir/stderr" >&2
  } 3>&1 | tee "$capture_dir/stdout"
  status=$(cat "$capture_dir/status")

  if [ "$status" -eq 0 ]; then
    exit 0
  fi
  if [ "$attempt" -ge "$start_retries" ] ||
    ! cat "$capture_dir/stdout" "$capture_dir/stderr" | grep -q 'toomanyrequests'; then
    exit "$status"
  fi

  attempt=$((attempt + 1))
  sleep_seconds=$((start_retry_delay * attempt))
  echo "[supabase.sh] retrying supabase start (attempt $attempt/$start_retries) after GHCR rate limit, sleeping ${sleep_seconds}s" >&2
  sleep "$sleep_seconds"
done
