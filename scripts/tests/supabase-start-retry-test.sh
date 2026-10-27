#!/usr/bin/env bash
set -euo pipefail

# Covers the opt-in `supabase start` retry in scripts/supabase.sh. The wrapper
# is copied into a fake repo layout with stub node/npm/npx/sleep on PATH, so
# neither the real Supabase CLI nor Docker is touched, and no real waiting
# happens.

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

# Stub sleep: records the requested seconds instead of waiting.
cat >"$bin_dir/sleep" <<'STUB'
#!/bin/sh
echo "$*" >>"$SLEEP_LOG"
STUB

# Stub npx: logs each call and plays back the outcomes listed in
# STUB_OUTCOMES (space separated, the last one repeats). Every outcome writes
# an "OUT:" line to stdout and an "ERR:" line to stderr so a test can tell the
# streams apart:
#   rate     -> rate-limit message on stderr, exit 1
#   rate-out -> rate-limit message on stdout, exit 1
#   other    -> unrelated failure, exit 7
#   ok       -> success, exit 0
# Watchdog: past 20 calls the stub exits 99, so a retry loop that never stops
# fails the test quickly instead of hanging it.
cat >"$bin_dir/npx" <<'STUB'
#!/bin/sh
echo "npx:$*" >>"$STUB_LOG"
count=$(wc -l <"$STUB_LOG" | tr -d ' ')
if [ "$count" -gt 20 ]; then
  echo "stub: call limit exceeded (runaway retry loop)" >&2
  exit 99
fi
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
  echo "OUT: pulling images"
  echo "ERR: failed to pull docker image: toomanyrequests: retry-after" >&2
  exit 1
  ;;
rate-out)
  echo "OUT: failed to pull docker image: toomanyrequests: retry-after"
  echo "ERR: pulling images" >&2
  exit 1
  ;;
other)
  echo "OUT: working"
  echo "ERR: boom: something else broke" >&2
  exit 7
  ;;
ok)
  echo "OUT: started"
  echo "ERR: cli note" >&2
  exit 0
  ;;
esac
echo "stub: unknown outcome '$outcome'" >&2
exit 99
STUB
chmod +x "$bin_dir/node" "$bin_dir/npm" "$bin_dir/npx" "$bin_dir/sleep"

failures=0
case_delay=0

fail() {
  echo "FAIL $1" >&2
  failures=$((failures + 1))
}

# run_case <name> <expected-exit> <expected-calls> <outcomes> <retries> <args...>
# SUPABASE_START_RETRIES is unset when <retries> is "-". stdout and stderr go
# to separate files: out-<name>.txt and err-<name>.txt.
run_case() {
  local name="$1" expected_exit="$2" expected_calls="$3" outcomes="$4" retries="$5"
  shift 5
  local log="$tmp_dir/log-$name.txt" out="$tmp_dir/out-$name.txt" err="$tmp_dir/err-$name.txt"
  : >"$log"
  : >"$tmp_dir/sleep-$name.txt"
  local actual_exit=0
  if [[ "$retries" == "-" ]]; then
    env -u SUPABASE_START_RETRIES \
      PATH="$bin_dir:$PATH" STUB_LOG="$log" STUB_OUTCOMES="$outcomes" \
      SLEEP_LOG="$tmp_dir/sleep-$name.txt" SUPABASE_START_RETRY_DELAY="$case_delay" \
      "$fake_repo/scripts/supabase.sh" "$@" >"$out" 2>"$err" || actual_exit=$?
  else
    PATH="$bin_dir:$PATH" STUB_LOG="$log" STUB_OUTCOMES="$outcomes" \
      SLEEP_LOG="$tmp_dir/sleep-$name.txt" SUPABASE_START_RETRIES="$retries" \
      SUPABASE_START_RETRY_DELAY="$case_delay" \
      "$fake_repo/scripts/supabase.sh" "$@" >"$out" 2>"$err" || actual_exit=$?
  fi
  local actual_calls
  actual_calls=$(wc -l <"$log" | tr -d ' ')
  if [[ "$actual_exit" != "$expected_exit" || "$actual_calls" != "$expected_calls" ]]; then
    fail "$name: exit $actual_exit (want $expected_exit), calls $actual_calls (want $expected_calls)"
    sed 's/^/  out | /' "$out" >&2
    sed 's/^/  err | /' "$err" >&2
  else
    echo "ok   $name"
  fi
}

# expect_in <name> <file> <pattern> <description>
expect_in() {
  if ! grep -q -- "$3" "$2"; then
    fail "$1: $4 missing"
    sed 's/^/  | /' "$2" >&2
  fi
}

# expect_not_in <name> <file> <pattern> <description>
expect_not_in() {
  if grep -q -- "$3" "$2"; then
    fail "$1: $4 leaked"
    sed 's/^/  | /' "$2" >&2
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
  fail "start-args-forwarded: unexpected CLI invocation"
  sed 's/^/  | /' "$tmp_dir/log-start-args-forwarded.txt" >&2
fi

# A retry announces itself on stderr and names the attempt.
run_case retry-message 0 2 "rate ok" 3 start
expect_in retry-message "$tmp_dir/err-retry-message.txt" \
  '\[supabase.sh\] retrying supabase start (attempt 1/3) after a registry rate limit, sleeping 0s' \
  "retry notice on stderr"

# Streams stay separate. A rate limit reported on stdout only must still be
# detected, and neither stream may receive the other's text.
run_case split-stdout-rate 0 3 "rate-out rate-out ok" 3 start
f="$tmp_dir"
expect_in split-stdout-rate "$f/out-split-stdout-rate.txt" 'OUT: started' "success text on stdout"
expect_in split-stdout-rate "$f/out-split-stdout-rate.txt" 'OUT: failed to pull docker image: toomanyrequests' "rate message on stdout"
expect_in split-stdout-rate "$f/err-split-stdout-rate.txt" 'ERR: cli note' "CLI stderr text on stderr"
expect_in split-stdout-rate "$f/err-split-stdout-rate.txt" '\[supabase.sh\] retrying supabase start (attempt 2/3)' "retry notice on stderr"
expect_not_in split-stdout-rate "$f/out-split-stdout-rate.txt" 'ERR:' "stderr text in stdout"
expect_not_in split-stdout-rate "$f/out-split-stdout-rate.txt" '\[supabase.sh\]' "retry notice in stdout"
expect_not_in split-stdout-rate "$f/err-split-stdout-rate.txt" 'OUT:' "stdout text in stderr"

run_case split-stderr-rate 0 3 "rate rate ok" 3 start
expect_in split-stderr-rate "$f/out-split-stderr-rate.txt" 'OUT: started' "success text on stdout"
expect_in split-stderr-rate "$f/err-split-stderr-rate.txt" 'ERR: failed to pull docker image: toomanyrequests' "rate message on stderr"
expect_in split-stderr-rate "$f/err-split-stderr-rate.txt" 'ERR: cli note' "CLI stderr text on stderr"
expect_in split-stderr-rate "$f/err-split-stderr-rate.txt" '\[supabase.sh\] retrying supabase start (attempt 2/3)' "retry notice on stderr"
expect_not_in split-stderr-rate "$f/out-split-stderr-rate.txt" 'ERR:' "stderr text in stdout"
expect_not_in split-stderr-rate "$f/out-split-stderr-rate.txt" '\[supabase.sh\]' "retry notice in stdout"
expect_not_in split-stderr-rate "$f/err-split-stderr-rate.txt" 'OUT:' "stdout text in stderr"

# The wait grows linearly with the attempt number.
case_delay=5
run_case delay-linear 0 3 "rate rate ok" 3 start
if [[ "$(tr '\n' ' ' <"$tmp_dir/sleep-delay-linear.txt")" != "5 10 " ]]; then
  fail "delay-linear: sleeps were '$(tr '\n' ' ' <"$tmp_dir/sleep-delay-linear.txt")', want '5 10 '"
fi

# Leading zeros must not be read as octal (08 and 09 are not valid octal).
case_delay=08
run_case delay-leading-zero 0 3 "rate rate ok" 3 start
if [[ "$(tr '\n' ' ' <"$tmp_dir/sleep-delay-leading-zero.txt")" != "8 16 " ]]; then
  fail "delay-leading-zero: sleeps were '$(tr '\n' ' ' <"$tmp_dir/sleep-delay-leading-zero.txt")', want '8 16 '"
fi
case_delay=00
run_case delay-all-zeros 0 2 "rate ok" 1 start
if [[ "$(tr '\n' ' ' <"$tmp_dir/sleep-delay-all-zeros.txt")" != "0 " ]]; then
  fail "delay-all-zeros: sleeps were '$(tr '\n' ' ' <"$tmp_dir/sleep-delay-all-zeros.txt")', want '0 '"
fi
case_delay=0

if [[ "$failures" -ne 0 ]]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "supabase-start-retry-test: all checks passed"
