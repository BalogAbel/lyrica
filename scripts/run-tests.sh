#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

(cd apps/lyrica_app && flutter test)
