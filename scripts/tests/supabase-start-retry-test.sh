#!/usr/bin/env bash
set -euo pipefail

# Covers the opt-in `supabase start` retry in scripts/supabase.sh. The wrapper
# is copied into a fake repo layout with stub node/npm/npx on PATH, so neither
# the real Supabase CLI nor Docker is touched.

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_repo="$tmp_dir/repo"
bin_dir="$tmp_dir/bin"
mkdir -p "$fake_repo/scripts" "$fake_repo/tooling/supabase/node_modules" "$bin_dir"
cp "$repo_root/scripts/supabase.sh" "$fake_repo/scripts/supabase.sh"

for tool in node npm; do
  printf '#!/bin/sh\nexit 0\n' >"$bin_dir/$tool"
done

# Stub npx: logs each call and plays back the outcomes listed in
# STUB_OUTCOMES (space separated, the last one repeats):
#   rate  -> GHCR rate limit message, exit 1
#   other -> unrelated failure, exit 7
#   ok    -> success, exit 0
cat >"$bin_dir/npx" <<'STUB'
#!/bin/sh
echo "npx:$*" >>"$STUB_LOG"
count=$(wc -l <"$STUB_LOG" | tr -d ' ')
outcome=""
index=0
for candidate in $STUB_OUTCOMES; do
  index=$((index + 1))
  outcome="$candidate"
  if [ "$index" -eq "$count" ]; then
    break
  fi
done
case "$outcome" in
rate)
  echo "failed to pull docker image: toomanyrequests: retry-after" >&2
  exit 1
  ;;
other)
  echo "boom: something else broke" >&2
  exit 7
  ;;
ok)
  echo "started"
  exit 0
  ;;
esac
echo "stub: unknown outcome '$outcome'" >&2
exit 99
STUB
chmod +x "$bin_dir/node" "$bin_dir/npm" "$bin_dir/npx"

failures=0

# run_case <name> <expected-exit> <expected-calls> <outcomes> <retries> <args...>
# SUPABASE_START_RETRIES is unset when <retries> is "-".
run_case() {
  local name="$1" expected_exit="$2" expected_calls="$3" outcomes="$4" retries="$5"
  shift 5
  local log="$tmp_dir/log-$name.txt" out="$tmp_dir/out-$name.txt"
  : >"$log"
  local actual_exit=0
  if [[ "$retries" == "-" ]]; then
    env -u SUPABASE_START_RETRIES \
      PATH="$bin_dir:$PATH" STUB_LOG="$log" STUB_OUTCOMES="$outcomes" \
      SUPABASE_START_RETRY_DELAY=0 \
      "$fake_repo/scripts/supabase.sh" "$@" >"$out" 2>&1 || actual_exit=$?
  else
    PATH="$bin_dir:$PATH" STUB_LOG="$log" STUB_OUTCOMES="$outcomes" \
      SUPABASE_START_RETRIES="$retries" SUPABASE_START_RETRY_DELAY=0 \
      "$fake_repo/scripts/supabase.sh" "$@" >"$out" 2>&1 || actual_exit=$?
  fi
  local actual_calls
  actual_calls=$(wc -l <"$log" | tr -d ' ')
  if [[ "$actual_exit" != "$expected_exit" || "$actual_calls" != "$expected_calls" ]]; then
    echo "FAIL $name: exit $actual_exit (want $expected_exit), calls $actual_calls (want $expected_calls)" >&2
    sed 's/^/  | /' "$out" >&2
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

# (a) two rate-limit failures, then success: exit 0 after 3 calls.
run_case rate-then-success 0 3 "rate rate ok" 3 start

# (b) a different failure is never retried and keeps its exit code.
run_case other-error 7 1 "other" 3 start

# (c) retries disabled (variable unset): single call even on a rate limit.
run_case disabled-unset 1 1 "rate" - start
run_case disabled-zero 1 1 "rate" 0 start

# (d) retries exhausted: N+1 calls, the CLI's own nonzero exit code.
run_case exhausted 1 4 "rate" 3 start

# (e) non-start commands are never retried.
run_case status-not-retried 1 1 "rate" 3 status -o env

# Arguments after `start` still reach the CLI unchanged.
run_case start-args-forwarded 0 1 "ok" 3 start -x storage-api
if ! grep -qx 'npx:--prefix '"$fake_repo"'/tooling/supabase supabase start -x storage-api' \
  "$tmp_dir/log-start-args-forwarded.txt"; then
  echo "FAIL start-args-forwarded: unexpected CLI invocation:" >&2
  sed 's/^/  | /' "$tmp_dir/log-start-args-forwarded.txt" >&2
  failures=$((failures + 1))
fi

# A retry announces itself on stderr and names the attempt.
run_case retry-message 0 2 "rate ok" 3 start
if ! grep -q '\[supabase.sh\] retrying supabase start (attempt 1/3) after GHCR rate limit, sleeping 0s' \
  "$tmp_dir/out-retry-message.txt"; then
  echo "FAIL retry-message: retry notice missing from output" >&2
  sed 's/^/  | /' "$tmp_dir/out-retry-message.txt" >&2
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "supabase-start-retry-test: all checks passed"
