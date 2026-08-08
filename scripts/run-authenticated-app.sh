#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$repo_root/apps/lyron_app"
source "$repo_root/scripts/_flutter_device_network.sh"

supabase_script="${SUPABASE_SCRIPT:-$repo_root/scripts/supabase.sh}"
db_reset_script="${DB_RESET_SCRIPT:-$repo_root/scripts/db-reset.sh}"
provision_demo_user_script="${PROVISION_DEMO_USER_SCRIPT:-$repo_root/scripts/provision-local-demo-user.sh}"
flutter_bin="${FLUTTER_BIN:-flutter}"
flutter_device="${FLUTTER_DEVICE:-chrome}"
demo_email="${DEMO_EMAIL:-demo@lyron.local}"

# The web redirect target must be listed in supabase/config.toml
# additional_redirect_urls, so the port is pinned instead of letting Flutter
# pick a random one.
web_port="${FLUTTER_WEB_PORT:-8080}"
android_package="${ANDROID_APPLICATION_ID:-io.lyron.chords}"

is_web_flutter_device() {
  case "$1" in
    chrome|edge|web-server)
      return 0
      ;;
  esac

  return 1
}

"$supabase_script" start
"$db_reset_script"
"$provision_demo_user_script"

status_env="$("$supabase_script" status -o env)"
eval "$status_env"

if [[ -z "${API_URL:-}" || -z "${ANON_KEY:-}" ]]; then
  echo "Local Supabase did not return API_URL and ANON_KEY." >&2
  exit 1
fi

if [[ -z "${SERVICE_ROLE_KEY:-}" ]]; then
  echo "Local Supabase did not return SERVICE_ROLE_KEY, cannot mint a demo magic link." >&2
  exit 1
fi

resolved_api_url="$(resolve_flutter_host_url "$flutter_device" "$API_URL")"
prepare_flutter_device_network "$flutter_device" "$resolved_api_url"

if is_web_flutter_device "$flutter_device"; then
  app_url="http://localhost:$web_port"
  redirect_to="$app_url"
else
  app_url=""
  redirect_to="io.lyron.app://auth/callback"
fi

# Ask GoTrue for a magic link the same way the sign-in screen would, except the
# admin endpoint hands the link back instead of mailing it.
generate_link_payload=$(
  EMAIL="$demo_email" REDIRECT_TO="$redirect_to" node -e '
process.stdout.write(
  JSON.stringify({
    type: "magiclink",
    email: process.env.EMAIL,
    redirect_to: process.env.REDIRECT_TO,
  }),
);
'
)

# GoTrue reads redirect_to from the body, but falls back to the query string,
# so both carry it.
encoded_redirect_to="$(REDIRECT_TO="$redirect_to" node -e '
process.stdout.write(encodeURIComponent(process.env.REDIRECT_TO));
')"

generate_link_response="$(
  curl --silent --show-error \
    --request POST \
    --url "$API_URL/auth/v1/admin/generate_link?redirect_to=$encoded_redirect_to" \
    --header "apikey: $SERVICE_ROLE_KEY" \
    --header "Authorization: Bearer $SERVICE_ROLE_KEY" \
    --header "Content-Type: application/json" \
    --data "$generate_link_payload"
)"

action_link="$(
  RESPONSE="$generate_link_response" node -e '
const response = JSON.parse(process.env.RESPONSE);
if (typeof response.action_link === "string" && response.action_link.length > 0) {
  process.stdout.write(response.action_link);
  process.exit(0);
}
console.error(JSON.stringify(response));
process.exit(1);
'
)"

magic_link="$(resolve_flutter_host_url "$flutter_device" "$action_link")"

echo
echo "Demo sign-in link for $demo_email:"
echo
echo "  $magic_link"
echo
echo "The link is single use and consumes the token on the first open, so wait"
echo "until Flutter reports the app is running, then open it."

if is_web_flutter_device "$flutter_device"; then
  echo "It lands on $app_url with the session already established, skipping the sign-in screen."
else
  echo "Open it on the device itself; it redirects into $redirect_to."
  echo "On an Android device or emulator:"
  echo
  echo "  adb -s $flutter_device shell am start -a android.intent.action.VIEW -d '$magic_link' $android_package"
fi
echo

flutter_args=(
  -d "$flutter_device"
  --target lib/main.dart
  --dart-define=SUPABASE_URL="$resolved_api_url"
  --dart-define=SUPABASE_ANON_KEY="$ANON_KEY"
)

if is_web_flutter_device "$flutter_device"; then
  flutter_args+=(--web-port "$web_port")
fi

cd "$app_dir"
"$flutter_bin" run "${flutter_args[@]}" "$@"
