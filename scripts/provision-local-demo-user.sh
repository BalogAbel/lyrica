#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

readonly DEMO_EMAIL="demo@lyrica.local"
readonly DEMO_PASSWORD="LyricaDemo123!"
readonly DEMO_ORGANIZATION_ID="11111111-1111-1111-1111-111111111111"

status_env="$(./scripts/supabase.sh status -o env)"
eval "$status_env"

if [[ -z "${API_URL:-}" || -z "${SERVICE_ROLE_KEY:-}" ]]; then
  echo "Local Supabase is not running or did not return API credentials." >&2
  exit 1
fi

create_payload=$(
  cat <<EOF
{"email":"$DEMO_EMAIL","password":"$DEMO_PASSWORD","email_confirm":true}
EOF
)

create_response="$(
  curl --silent --show-error \
    --request POST \
    --url "$API_URL/auth/v1/admin/users" \
    --header "apikey: $SERVICE_ROLE_KEY" \
    --header "Authorization: Bearer $SERVICE_ROLE_KEY" \
    --header "Content-Type: application/json" \
    --data "$create_payload"
)"

user_id="$(
  RESPONSE="$create_response" node -e '
const response = JSON.parse(process.env.RESPONSE);
if (response.id) {
  process.stdout.write(response.id);
  process.exit(0);
}
if (response.error_code === "email_exists") {
  process.stdout.write("");
  process.exit(0);
}
console.error(JSON.stringify(response));
process.exit(1);
'
)"

if [[ -z "$user_id" ]]; then
  users_response="$(
    curl --silent --show-error \
      --url "$API_URL/auth/v1/admin/users?page=1&per_page=1000" \
      --header "apikey: $SERVICE_ROLE_KEY" \
      --header "Authorization: Bearer $SERVICE_ROLE_KEY"
  )"

  user_id="$(
    RESPONSE="$users_response" EMAIL="$DEMO_EMAIL" node -e '
const response = JSON.parse(process.env.RESPONSE);
const users = Array.isArray(response.users) ? response.users : [];
const match = users.find((user) => user.email === process.env.EMAIL);
if (!match) {
  console.error(JSON.stringify(response));
  process.exit(1);
}
process.stdout.write(match.id);
'
  )"

  update_payload=$(
    cat <<EOF
{"password":"$DEMO_PASSWORD","email_confirm":true}
EOF
  )

  curl --silent --show-error \
    --request PUT \
    --url "$API_URL/auth/v1/admin/users/$user_id" \
    --header "apikey: $SERVICE_ROLE_KEY" \
    --header "Authorization: Bearer $SERVICE_ROLE_KEY" \
    --header "Content-Type: application/json" \
    --data "$update_payload" \
    >/dev/null
fi

membership_sql=$(
  cat <<EOF
insert into public.memberships (organization_id, user_id, scope_type, role_code, status)
values ('$DEMO_ORGANIZATION_ID', '$user_id', 'organization', 'organization_member', 'active')
on conflict (organization_id, user_id, role_code)
where group_id is null and scope_type = 'organization' do update
set status = excluded.status;
EOF
)

./scripts/supabase.sh db query "$membership_sql" >/dev/null

echo "Provisioned demo user:"
echo "  email: $DEMO_EMAIL"
echo "  password: $DEMO_PASSWORD"
echo "  user_id: $user_id"
