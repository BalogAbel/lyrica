#!/usr/bin/env bash
set -euo pipefail

resolve_adb_bin() {
  if [[ -n "${ADB_BIN:-}" ]]; then
    if [[ -x "$ADB_BIN" ]]; then
      printf '%s\n' "$ADB_BIN"
      return 0
    fi

    if command -v "$ADB_BIN" >/dev/null 2>&1; then
      command -v "$ADB_BIN"
      return 0
    fi

    echo "Missing adb binary: $ADB_BIN" >&2
    return 1
  fi

  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return 0
  fi

  local candidate=""
  for candidate in \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "${HOME:-}/Library/Android/sdk/platform-tools/adb"
  do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

can_prepare_android_adb_device() {
  local flutter_device="$1"
  local adb_bin="$2"

  "$adb_bin" -s "$flutter_device" get-state >/dev/null 2>&1
}

is_known_non_android_flutter_device() {
  local flutter_device="$1"

  case "$flutter_device" in
    all|chrome|web-server|macos|windows|linux)
      return 0
      ;;
  esac

  return 1
}

prepare_flutter_device_network() {
  local flutter_device="$1"
  local url="$2"
  local adb_bin=""
  local host=""
  local port=""

  if [[ "$url" =~ ^https?://([^/:]+):([0-9]+) ]]; then
    host="${BASH_REMATCH[1]}"
    port="${BASH_REMATCH[2]}"
  fi

  case "$host" in
    127.0.0.1|localhost)
      if is_known_non_android_flutter_device "$flutter_device"; then
        return 0
      fi

      if ! adb_bin="$(resolve_adb_bin)"; then
        echo "Set ADB_BIN or install Android platform-tools." >&2
        exit 1
      fi

      if can_prepare_android_adb_device "$flutter_device" "$adb_bin"; then
        "$adb_bin" -s "$flutter_device" reverse "tcp:$port" "tcp:$port"
      fi
      ;;
  esac
}

resolve_flutter_host_url() {
  local flutter_device="$1"
  local url="$2"

  case "$flutter_device" in
    emulator-*)
      url="${url/127.0.0.1/10.0.2.2}"
      url="${url/localhost/10.0.2.2}"
      ;;
  esac

  printf '%s\n' "$url"
}
