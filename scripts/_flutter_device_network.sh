#!/usr/bin/env bash
set -euo pipefail

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
