#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

(cd apps/lyron_app && flutter test)
