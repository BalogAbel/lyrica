#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$repo_root/apps/lyrica_app"
source "$repo_root/scripts/_flutter_device_network.sh"

supabase_script="${SUPABASE_SCRIPT:-$repo_root/scripts/supabase.sh}"
db_reset_script="${DB_RESET_SCRIPT:-$repo_root/scripts/db-reset.sh}"
provision_demo_user_script="${PROVISION_DEMO_USER_SCRIPT:-$repo_root/scripts/provision-local-demo-user.sh}"
flutter_bin="${FLUTTER_BIN:-flutter}"
flutter_device="${FLUTTER_DEVICE:-chrome}"

"$supabase_script" start
"$db_reset_script"
"$provision_demo_user_script"

status_env="$("$supabase_script" status -o env)"
eval "$status_env"

if [[ -z "${API_URL:-}" || -z "${ANON_KEY:-}" ]]; then
  echo "Local Supabase did not return API_URL and ANON_KEY." >&2
  exit 1
fi

resolved_api_url="$(resolve_flutter_host_url "$flutter_device" "$API_URL")"
prepare_flutter_device_network "$flutter_device" "$resolved_api_url"

cd "$app_dir"
"$flutter_bin" run \
  -d "$flutter_device" \
  --target lib/main.dart \
  --dart-define=SUPABASE_URL="$resolved_api_url" \
  --dart-define=SUPABASE_ANON_KEY="$ANON_KEY" \
  "$@"
