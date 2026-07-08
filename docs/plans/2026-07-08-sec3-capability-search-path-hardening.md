# SEC-3 Capability `search_path` Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin `search_path = public` on `has_capability` and `get_my_capabilities`, guarded by a backend contract test so it cannot silently regress.

**Architecture:** An `alter function ... set search_path = public` migration (house style, per `202605160007_auth_boundary_hardening.sql`). A new backend contract test asserts `pg_proc.proconfig` for the three security helpers and is wired into the `backend_write_contracts` CI job. TDD: the guard test is written and observed failing before the migration is added.

**Tech Stack:** Postgres / Supabase migrations, bash + python3 + `docker exec psql` contract tests, `./scripts/supabase.sh db query`.

**Spec:** `docs/specs/2026-07-08-sec3-capability-search-path-hardening.md`

**Environment note:** The backend gates require a local Supabase stack (Docker). Use `./scripts/supabase.sh` (which shells `npx --prefix tooling/supabase supabase`). Docker is available; the Supabase CLI is only reachable through that wrapper, never a bare `supabase` command.

---

## File Structure

- Create: `scripts/tests/capability-search-path-contract-test.sh` — proconfig guard.
- Modify: `scripts/backend-write-contracts.sh` — wire the guard into the job.
- Create: `supabase/migrations/202607080001_capability_search_path_hardening.sql` — the fix.
- Modify: `docs/architecture/repository-review-2026-06-22.md` — mark SEC-3 fixed.

---

## Task 1: Guard test (failing first) + CI wiring

**Files:**
- Create: `scripts/tests/capability-search-path-contract-test.sh`
- Modify: `scripts/backend-write-contracts.sh`

- [ ] **Step 1: Write the guard test script**

Create `scripts/tests/capability-search-path-contract-test.sh` with exactly this
content (mirrors `scripts/tests/organization-read-only-role-test.sh` bootstrap
and `docker exec psql` pattern):

```bash
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
```

- [ ] **Step 2: Make it executable and wire it into the backend contracts job**

```bash
chmod +x scripts/tests/capability-search-path-contract-test.sh
```

In `scripts/backend-write-contracts.sh`, after the existing
`organization_read_only_test_script` invocation block at the end of the file,
append:

```bash
capability_search_path_test_script="${CAPABILITY_SEARCH_PATH_TEST_SCRIPT:-./scripts/tests/capability-search-path-contract-test.sh}"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$capability_search_path_test_script"
```

Also add the variable declaration near the other `*_test_script` declarations at
the top of the file for consistency (optional but preferred): declare
`capability_search_path_test_script` in the same block as the others, and drop
the inline re-declaration if you do.

- [ ] **Step 3: Run the guard test against the current schema — CONFIRM IT FAILS**

Run (full bootstrap, since no stack is up yet):

```bash
./scripts/tests/capability-search-path-contract-test.sh
```

Expected: FAILS with
`SEC-3 guard failed ... has_capability: proconfig lacks search_path=public` and
the same for `get_my_capabilities`. `current_organization_ids` should already
pass. Capture the failure output.

If the stack is slow to start, that is expected (Docker image pull + boot). Do
not skip the failing-first observation — it proves the guard bites.

- [ ] **Step 4: Commit the failing guard**

```bash
git add scripts/tests/capability-search-path-contract-test.sh scripts/backend-write-contracts.sh
git commit -m "test(backend): guard search_path on capability helpers"
```

---

## Task 2: Migration to pin `search_path` (make the guard pass)

**Files:**
- Create: `supabase/migrations/202607080001_capability_search_path_hardening.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/202607080001_capability_search_path_hardening.sql`:

```sql
-- SEC-3: pin a non-mutable search_path on the capability helpers.
-- has_capability lost its search_path when redefined in
-- 202605250002_organization_read_only_role_constraints.sql; get_my_capabilities
-- (202605280001) never carried one. current_organization_ids already sets it.
-- Matches the ALTER FUNCTION hardening style of
-- 202605160007_auth_boundary_hardening.sql.
alter function public.has_capability(uuid, text, uuid)
  set search_path = public;

alter function public.get_my_capabilities(uuid, uuid)
  set search_path = public;
```

- [ ] **Step 2: Reset the DB so the new migration applies, then run the guard — CONFIRM IT PASSES**

```bash
./scripts/db-reset.sh
./scripts/tests/capability-search-path-contract-test.sh
```

(The stack is already running from Task 1, so `db-reset.sh` re-applies all
migrations including the new one. The guard test with default bootstrap also
resets, so either path applies the migration.)
Expected: `SEC-3 guard passed: all capability helpers pin search_path=public.`

- [ ] **Step 3: Run the migration lint gate — CONFIRM GREEN**

```bash
./scripts/check-migrations.sh
```

Expected: passes (db lint reports no errors on the new migration).

- [ ] **Step 4: Run the full backend write-contracts gate — CONFIRM GREEN**

```bash
./scripts/backend-write-contracts.sh
```

Expected: planning, song-crud, organization-read-only, and the new
capability-search-path guard all pass.

- [ ] **Step 5: Commit the migration**

```bash
git add supabase/migrations/202607080001_capability_search_path_hardening.sql
git commit -m "fix(db): pin search_path=public on capability helpers"
```

---

## Task 3: Mark SEC-3 fixed in the repository review

**Files:**
- Modify: `docs/architecture/repository-review-2026-06-22.md`

- [ ] **Step 1: Update the three SEC-3 references**

**a) Detail block (currently around lines 214-220).** The block ends with
`2 of 3 open.` Update the tally to reflect closure. Change the final sentence
from `... 2 of 3 open.` to:

```
... **Fixed (arch-spine-phase0-1)**: `has_capability` and `get_my_capabilities`
now pin `set search_path = public` (`supabase/migrations/202607080001_capability_search_path_hardening.sql`),
guarded by `scripts/tests/capability-search-path-contract-test.sh`. All 3 helpers closed.
```

Read the surrounding lines first to preserve markdown flow; keep the existing
explanatory sentences before it intact.

**b) `**Fixed**` digest (around lines 105-111, after the UX-3 bullet).** Add:

```markdown
- **SEC-3** (arch-spine-phase0-1 slice) — `has_capability` and
  `get_my_capabilities` now pin `set search_path = public`
  (`supabase/migrations/202607080001_capability_search_path_hardening.sql`),
  matching `current_organization_ids`. A backend contract test
  (`scripts/tests/capability-search-path-contract-test.sh`, wired into the
  `backend_write_contracts` job) guards all three helpers against silent
  regression.
```

**c) Remediation quick-wins list.** The current line reads exactly:

```markdown
- SEC-3: `set search_path = public` on the two remaining invoker-rights helpers
  (`has_capability`, `get_my_capabilities`); `current_organization_ids` already has it.
```

Replace it with:

```markdown
- ~~SEC-3: `set search_path = public` on the two remaining invoker-rights helpers (`has_capability`, `get_my_capabilities`); `current_organization_ids` already has it.~~ **Done (arch-spine-phase0-1).**
```

- [ ] **Step 2: Commit**

```bash
git add docs/architecture/repository-review-2026-06-22.md
git commit -m "docs(review): mark SEC-3 fixed (capability search_path hardening)"
```

---

## Self-Review

- **Spec coverage:** migration (Task 2), guard test + wiring (Task 1), TDD
  failing-first (Task 1 Step 3), lint + write-contract green (Task 2 Steps 3-4),
  SEC-3 doc status incl. the "2 of 3 open" tally (Task 3). All spec sections covered.
- **Placeholders:** none — full script, migration, and doc text inline.
- **Consistency:** function signatures `has_capability(uuid, text, uuid)` and
  `get_my_capabilities(uuid, uuid)` match the current definitions and the
  `auth_boundary_hardening` precedent; the guard test and migration name the same
  three helpers; the env var `CAPABILITY_SEARCH_PATH_TEST_SCRIPT` follows the
  existing `*_test_script` override convention.

---

## Done when

- Guard test failing first, then green after the migration.
- All three helpers pin `search_path=public` in `proconfig`.
- `check-migrations.sh` and `backend-write-contracts.sh` green locally.
- SEC-3 marked fixed in the review doc.
