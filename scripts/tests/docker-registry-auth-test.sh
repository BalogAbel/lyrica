#!/usr/bin/env bash
set -euo pipefail

# Covers scripts/docker-registry-auth.sh, which writes registry credentials
# into a Docker config under an exact registry key. Only dummy credentials are
# used, HOME is pointed at a temp dir, and the real Docker config is never
# touched.

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$repo_root/scripts/docker-registry-auth.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

dummy_user="dummy-user"
dummy_token="dummy-token-DO-NOT-LEAK-0123456789"

failures=0

fail() {
  echo "FAIL $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok   $1"
}

# Portable octal mode: GNU stat first, BSD stat as the fallback.
mode_of() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

# run_script <name> <env-assignments...> -- <args...>
# Runs the script with a clean environment (HOME in a temp dir, no
# DOCKER_CONFIG unless given). Output lands in out-<name>.txt / err-<name>.txt
# and the exit code in $actual_exit.
actual_exit=0
run_script() {
  local name="$1"
  shift
  local -a env_args=()
  while [[ "$1" != "--" ]]; do
    env_args+=("$1")
    shift
  done
  shift
  actual_exit=0
  env -u DOCKER_CONFIG -u REGISTRY_USERNAME -u REGISTRY_TOKEN \
    HOME="$tmp_dir/home-$name" ${env_args[@]+"${env_args[@]}"} \
    sh "$script" "$@" >"$tmp_dir/out-$name.txt" 2>"$tmp_dir/err-$name.txt" || actual_exit=$?
}

# The token must never reach stdout or stderr, nor its base64 form.
expect_no_leak() {
  local name="$1" auth
  auth="$(printf '%s:%s' "$dummy_user" "$dummy_token" | base64 | tr -d '\n')"
  for stream in out err; do
    if grep -qF -- "$dummy_token" "$tmp_dir/$stream-$name.txt" ||
      grep -qF -- "$auth" "$tmp_dir/$stream-$name.txt"; then
      fail "$name: credential leaked on $stream"
    fi
  done
}

expected_auth="$(printf '%s:%s' "$dummy_user" "$dummy_token" | base64 | tr -d '\n')"

# (a) config.json under the key docker.io, auth = base64(user:token), 600/700.
mkdir -p "$tmp_dir/home-write"
cfg="$tmp_dir/write-cfg"
run_script write DOCKER_CONFIG="$cfg" REGISTRY_USERNAME="$dummy_user" \
  REGISTRY_TOKEN="$dummy_token" -- docker.io
if [[ "$actual_exit" != 0 ]]; then
  fail "write: exit $actual_exit (want 0)"
elif [[ ! -f "$cfg/config.json" ]]; then
  fail "write: config.json missing"
else
  want="{\"auths\":{\"docker.io\":{\"auth\":\"$expected_auth\"}}}"
  got="$(cat "$cfg/config.json")"
  if [[ "$got" != "$want" ]]; then
    fail "write: unexpected config.json content"
    echo "  want | $want" >&2
    echo "  got  | $got" >&2
  elif [[ "$(mode_of "$cfg/config.json")" != "600" ]]; then
    fail "write: config.json mode $(mode_of "$cfg/config.json") (want 600)"
  elif [[ "$(mode_of "$cfg")" != "700" ]]; then
    fail "write: config dir mode $(mode_of "$cfg") (want 700)"
  else
    ok "write-docker-io-key-and-modes"
  fi
fi
expect_no_leak write

# (g) the JSON is valid and has the documented shape.
if command -v python3 >/dev/null 2>&1; then
  if python3 -I - "$cfg/config.json" "$expected_auth" <<'PY'; then
import json, sys
data = json.load(open(sys.argv[1]))
assert list(data) == ["auths"], data
assert list(data["auths"]) == ["docker.io"], data
assert data["auths"]["docker.io"] == {"auth": sys.argv[2]}, data
PY
    ok "write-json-round-trip"
  else
    fail "write-json-round-trip: JSON shape mismatch"
  fi
fi

# (b) a different registry argument is used as the key.
mkdir -p "$tmp_dir/home-other"
cfg="$tmp_dir/other-cfg"
run_script other DOCKER_CONFIG="$cfg" REGISTRY_USERNAME="$dummy_user" \
  REGISTRY_TOKEN="$dummy_token" -- registry.example.test
want="{\"auths\":{\"registry.example.test\":{\"auth\":\"$expected_auth\"}}}"
if [[ "$actual_exit" == 0 && -f "$cfg/config.json" && "$(cat "$cfg/config.json")" == "$want" ]]; then
  ok "other-registry-key"
else
  fail "other-registry-key: exit $actual_exit, content '$(cat "$cfg/config.json" 2>/dev/null || true)'"
fi
expect_no_leak other

# Overwrites a stale config.json in the (expected fresh) directory.
mkdir -p "$cfg"
printf 'stale' >"$cfg/config.json"
run_script overwrite DOCKER_CONFIG="$cfg" REGISTRY_USERNAME="$dummy_user" \
  REGISTRY_TOKEN="$dummy_token" -- registry.example.test
if [[ "$actual_exit" == 0 && "$(cat "$cfg/config.json")" == "$want" ]]; then
  ok "overwrites-existing-config"
else
  fail "overwrites-existing-config"
fi

# (c) missing username or token: exit 0, no file, notice on stderr.
for variant in no-user no-token both-empty; do
  mkdir -p "$tmp_dir/home-$variant"
  cfg="$tmp_dir/$variant-cfg"
  user="$dummy_user"
  token="$dummy_token"
  case "$variant" in
  no-user) user="" ;;
  no-token) token="" ;;
  both-empty) user="" token="" ;;
  esac
  run_script "$variant" DOCKER_CONFIG="$cfg" REGISTRY_USERNAME="$user" \
    REGISTRY_TOKEN="$token" -- docker.io
  if [[ "$actual_exit" != 0 ]]; then
    fail "$variant: exit $actual_exit (want 0)"
  elif [[ -e "$cfg" ]]; then
    fail "$variant: config dir created"
  elif [[ ! -s "$tmp_dir/err-$variant.txt" ]]; then
    fail "$variant: no notice on stderr"
  elif [[ -s "$tmp_dir/out-$variant.txt" ]]; then
    fail "$variant: unexpected stdout"
  else
    ok "$variant-anonymous-notice"
  fi
  expect_no_leak "$variant"
done

# Variables entirely unset behave like empty ones.
mkdir -p "$tmp_dir/home-unset"
cfg="$tmp_dir/unset-cfg"
run_script unset DOCKER_CONFIG="$cfg" -- docker.io
if [[ "$actual_exit" == 0 && ! -e "$cfg" && -s "$tmp_dir/err-unset.txt" ]]; then
  ok "unset-credentials-anonymous-notice"
else
  fail "unset-credentials-anonymous-notice: exit $actual_exit"
fi

# (d) DOCKER_CONFIG unset or empty: exit 2, nothing written under HOME.
for variant in cfg-unset cfg-empty; do
  mkdir -p "$tmp_dir/home-$variant"
  if [[ "$variant" == cfg-empty ]]; then
    run_script "$variant" DOCKER_CONFIG= REGISTRY_USERNAME="$dummy_user" \
      REGISTRY_TOKEN="$dummy_token" -- docker.io
  else
    run_script "$variant" REGISTRY_USERNAME="$dummy_user" \
      REGISTRY_TOKEN="$dummy_token" -- docker.io
  fi
  if [[ "$actual_exit" != 2 ]]; then
    fail "$variant: exit $actual_exit (want 2)"
  elif [[ -n "$(ls -A "$tmp_dir/home-$variant")" ]]; then
    fail "$variant: wrote into HOME: $(ls -A "$tmp_dir/home-$variant")"
  elif [[ ! -s "$tmp_dir/err-$variant.txt" ]]; then
    fail "$variant: no message on stderr"
  else
    ok "$variant-refuses-without-docker-config"
  fi
  expect_no_leak "$variant"
done

# (e) missing registry argument: exit 2, nothing written.
mkdir -p "$tmp_dir/home-noarg"
cfg="$tmp_dir/noarg-cfg"
run_script noarg DOCKER_CONFIG="$cfg" REGISTRY_USERNAME="$dummy_user" \
  REGISTRY_TOKEN="$dummy_token" --
if [[ "$actual_exit" == 2 && ! -e "$cfg" && -s "$tmp_dir/err-noarg.txt" ]]; then
  ok "missing-registry-argument"
else
  fail "missing-registry-argument: exit $actual_exit"
fi
expect_no_leak noarg

if [[ "$failures" -ne 0 ]]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "docker-registry-auth-test: all checks passed"
