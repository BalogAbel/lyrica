#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
app_dir="$repo_root/apps/lyrica_app"
source "$repo_root/scripts/manual-validation/_supabase_env.sh"

supabase_script="${SUPABASE_SCRIPT:-$repo_root/scripts/supabase.sh}"
flutter_bin="${FLUTTER_BIN:-flutter}"
flutter_device="${FLUTTER_DEVICE:-chrome}"
web_runtime_asset="$app_dir/web/sqlite3.wasm"

case "$flutter_device" in
  chrome|web-server)
    if [[ ! -f "$web_runtime_asset" ]]; then
      echo "Missing web runtime asset: $web_runtime_asset" >&2
      echo "The local-first web cache requires sqlite3.wasm." >&2
      exit 1
    fi
    ;;
esac

status_env=""

if status_env="$(cache_supabase_env "$supabase_script" 2>/dev/null)" &&
  [[ -n "$status_env" ]]; then
  :
else
  status_env="$(load_cached_supabase_env)"
fi

eval "$status_env"

if [[ -z "${API_URL:-}" || -z "${ANON_KEY:-}" ]]; then
  echo "Local Supabase did not return API_URL and ANON_KEY." >&2
  exit 1
fi

cd "$app_dir"
"$flutter_bin" run \
  -d "$flutter_device" \
  --target lib/main.dart \
  --dart-define=SUPABASE_URL="$API_URL" \
  --dart-define=SUPABASE_ANON_KEY="$ANON_KEY" \
  "$@"
