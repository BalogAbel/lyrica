#!/usr/bin/env bash
set -euo pipefail

manual_validation_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$manual_validation_dir/../.." && pwd)"

supabase_env_file="${SUPABASE_ENV_FILE:-$repo_root/scripts/manual-validation/.supabase-env}"

normalize_supabase_env() {
  local raw_env="$1"

  printf '%s\n' "$raw_env" | awk '
    /^[A-Z0-9_]+=.+$/ {
      split($0, parts, "=")
      if (parts[1] == "API_URL" || parts[1] == "ANON_KEY") {
        print
      }
    }
  '
}

validate_supabase_env() {
  local status_env
  status_env="$(normalize_supabase_env "$1")"

  [[ -n "$status_env" ]] || return 1

  local api_url=""
  local anon_key=""
  eval "$status_env"
  [[ -n "${API_URL:-}" ]] && api_url="$API_URL"
  [[ -n "${ANON_KEY:-}" ]] && anon_key="$ANON_KEY"

  [[ -n "$api_url" && -n "$anon_key" ]]
}

cache_supabase_env() {
  local supabase_script="$1"
  local raw_env=""
  local status_env

  if ! raw_env="$("$supabase_script" status -o env)"; then
    return 1
  fi

  status_env="$(normalize_supabase_env "$raw_env")"
  if ! validate_supabase_env "$status_env"; then
    return 1
  fi

  mkdir -p "$(dirname "$supabase_env_file")"
  printf '%s\n' "$status_env" >"$supabase_env_file"
  printf '%s\n' "$status_env"
}

load_cached_supabase_env() {
  if [[ ! -f "$supabase_env_file" ]]; then
    echo "Missing cached local Supabase env: $supabase_env_file" >&2
    echo "Run ./scripts/manual-validation/setup-local-first.sh or bring the backend online first." >&2
    return 1
  fi

  local status_env
  status_env="$(cat "$supabase_env_file")"

  if ! validate_supabase_env "$status_env"; then
    echo "Cached local Supabase env is missing API_URL or ANON_KEY: $supabase_env_file" >&2
    echo "Run ./scripts/manual-validation/go-online.sh or ./scripts/manual-validation/setup-local-first.sh to refresh it." >&2
    return 1
  fi

  printf '%s\n' "$status_env"
}
