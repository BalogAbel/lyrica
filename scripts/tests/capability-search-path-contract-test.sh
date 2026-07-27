#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

if [[ "${BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP:-0}" != "1" ]]; then
  ./scripts/supabase.sh start >/dev/null
  ./scripts/db-reset.sh >/dev/null
  ./scripts/provision-local-demo-user.sh >/dev/null
fi

db_container_name="$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1)"

if [[ -z "$db_container_name" ]]; then
  echo "Could not find the local Supabase database container." >&2
  exit 1
fi

python3 - "$db_container_name" <<'PY'
import subprocess
import sys

container = sys.argv[1]

# Security helpers that must run with a pinned, non-mutable search_path.
required = ["current_organization_ids", "get_my_capabilities", "has_capability"]


def run_sql(sql):
    cmd = ["docker", "exec", "-i", container, "psql", "-U", "postgres",
           "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-X", "-qAt",
           "-F", "\t", "-c", sql]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"sql failed: {sql}\nstderr: {result.stderr}")
    return result.stdout.strip()


out = run_sql(
    """
    select p.proname, coalesce(array_to_string(p.proconfig, ','), '')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('has_capability', 'get_my_capabilities', 'current_organization_ids')
    order by p.proname;
    """
)

config_by_name = {}
for line in out.splitlines():
    if not line.strip():
        continue
    name, _, config = line.partition("\t")
    config_by_name[name] = config

failures = []
for name in required:
    config = config_by_name.get(name)
    if config is None:
        failures.append(f"{name}: function not found in schema public")
    elif "search_path=public" not in config:
        failures.append(f"{name}: proconfig lacks search_path=public (got: {config!r})")

if failures:
    raise SystemExit(
        "SEC-3 guard failed - security helpers missing pinned search_path:\n  "
        + "\n  ".join(failures)
    )

print("SEC-3 guard passed: all capability helpers pin search_path=public.")
PY
