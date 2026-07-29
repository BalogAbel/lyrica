# SEC-1 Invitation Redemption Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close SEC-1 by making invitation redemption email-bound when the invitation carries an email, rate-limited per caller, and fully audited — all enforced in PostgreSQL.

**Architecture:** `public.redeem_invitation` stops raising for business outcomes and returns `jsonb` instead, so the transaction commits and an audit row survives on every path. A new `public.invitation_redemption_attempts` table records each attempt; a caller-keyed count over that table implements the rate limit. The Flutter client is updated to the status-based contract and remains UX-only.

**Tech Stack:** PostgreSQL 15 (Supabase), plpgsql security-definer functions, RLS, `pg_cron`, bash + python3 contract test scripts, Flutter/Dart with `supabase_flutter`.

**Spec:** `docs/specs/2026-07-29-sec1-invitation-redemption-hardening.md`

---

## Background the implementer needs

- Migrations live in `supabase/migrations/` and are applied in filename order by
  `./scripts/db-reset.sh`. Filenames are `YYYYMMDDNNNN_snake_case.sql`. The
  highest existing is `202607080001_capability_search_path_hardening.sql`.
- Backend contract tests are bash scripts under `scripts/tests/` that shell into
  the local Supabase database container with `docker exec ... psql` and run
  assertions from an inlined python3 heredoc. They are chained from
  `./scripts/backend-write-contracts.sh`, which boots Supabase, resets the DB and
  provisions the demo user once, then runs each script with
  `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1`.
- Test scripts simulate an authenticated caller by setting
  `request.jwt.claim.sub` and `request.jwt.claim.role` via `set_config(..., true)`
  inside a `do $$ ... $$` block, in the **same** psql invocation as the statement
  under test (the `true` third argument makes the setting transaction-local).
- Running as `postgres` bypasses RLS. To assert an RLS denial the script must
  `set local role authenticated` inside an explicit transaction.
- The demo user is `demo@lyron.local`, organization
  `11111111-1111-1111-1111-111111111111`.
- `create_invitation` skips its admin check when `auth.uid()` is null, so the
  test script can create invitations directly as `postgres` without simulating an
  admin session.
- `sha256(bytea)` is a built-in PostgreSQL function (no `pgcrypto` needed);
  `extensions.gen_random_bytes` is the schema-qualified form used by
  `create_invitation`.

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `scripts/tests/invitation-redemption-contract-test.sh` | create | Full outcome-matrix contract test for redemption |
| `scripts/backend-write-contracts.sh` | modify | Chain the new test script |
| `supabase/migrations/202607290001_invitation_redemption_audit.sql` | create | Outcome enum, attempts table, index, RLS, grants, retention job |
| `supabase/migrations/202607290002_invitation_redemption_contract.sql` | create | Audit-write helper, `redeem_invitation` rewrite, grant restoration |
| `apps/lyron_app/lib/src/domain/auth/invitation_error.dart` | modify | New error cases; status-based mapping replaces message-based |
| `apps/lyron_app/lib/src/infrastructure/auth/supabase_invitation_repository.dart` | modify | Parse the jsonb response |
| `apps/lyron_app/lib/src/shared/app_strings.dart` | modify | Copy for the two new outcomes |
| `apps/lyron_app/lib/src/presentation/auth/redeem_progress_screen.dart` | modify | Render the two new outcomes |
| `apps/lyron_app/test/infrastructure/auth/supabase_invitation_repository_test.dart` | modify | Cover the jsonb contract |
| `apps/lyron_app/test/domain/auth/invitation_error_test.dart` | create | Cover `invitationErrorFromStatus` |
| `docs/architecture/decisions/ADR-025-invitation-redemption-model.md` | create | The redemption model decision |
| `docs/architecture/repository-review-2026-06-22.md` | modify | Mark SEC-1 fixed |
| `docs/architecture/architecture.md` | modify | Auth boundary description |
| `docs/testing/testing-strategy.md` | modify | Register the new contract test |

The two migrations split by responsibility: one owns the audit schema, one owns
the function contract. Tasks 3–5 each edit migration 202607290002 rather than
adding a new migration per behaviour — the file has not been merged yet, and
`./scripts/db-reset.sh` reapplies from scratch, so editing it keeps the final
history readable. Task 6 edits 202607290001 for the same reason.

---

### Task 1: Contract test harness with a failing contract-shape assertion

**Files:**
- Create: `scripts/tests/invitation-redemption-contract-test.sh`
- Modify: `scripts/backend-write-contracts.sh`

- [ ] **Step 1: Write the failing test script**

Create `scripts/tests/invitation-redemption-contract-test.sh`:

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
import json
import subprocess
import sys
from textwrap import dedent

container = sys.argv[1]

ORG_ID = "11111111-1111-1111-1111-111111111111"
# Distinct callers so rate-limit state never leaks between cases.
BEARER_USER = "aaaaaaa1-0000-0000-0000-000000000001"
BOUND_USER = "aaaaaaa1-0000-0000-0000-000000000002"
WRONG_USER = "aaaaaaa1-0000-0000-0000-000000000003"

failures = []


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def run_sql(sql, expect_error=False):
    cmd = ["docker", "exec", "-i", container, "psql", "-U", "postgres",
           "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-X", "-qAt",
           "-F", "\t", "-c", sql]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if expect_error:
        if result.returncode == 0:
            raise SystemExit(f"expected failure, got success for: {sql}")
        return result.stderr
    if result.returncode != 0:
        raise SystemExit(f"sql failed: {sql}\nstderr: {result.stderr}")
    return result.stdout.strip()


def redeem_as(user_id, token):
    """Call redeem_invitation as the given authenticated caller."""
    sql = dedent(f"""
        do $$
        begin
          perform set_config('request.jwt.claim.sub', {sql_quote(user_id)}, true);
          perform set_config('request.jwt.claim.role', 'authenticated', true);
        end $$;
        select public.redeem_invitation({sql_quote(token)});
    """)
    return run_sql(sql)


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}: {detail}")


def make_user(user_id, email, confirmed=True):
    confirmed_at = "timezone('utc', now())" if confirmed else "null"
    email_sql = sql_quote(email) if email is not None else "null"
    run_sql(dedent(f"""
        insert into auth.users (id, email, email_confirmed_at)
          values ({sql_quote(user_id)}, {email_sql}, {confirmed_at})
          on conflict (id) do update
            set email = excluded.email,
                email_confirmed_at = excluded.email_confirmed_at;
    """))


def make_invitation(email=None, role="organization_member"):
    email_sql = sql_quote(email) if email is not None else "null"
    return run_sql(
        f"select public.create_invitation("
        f"{sql_quote(ORG_ID)}, {sql_quote(role)}::public.role_code, {email_sql});"
    )


# --- Case 1: the RPC returns a jsonb status envelope, not a bare uuid. --------
make_user(BEARER_USER, "bearer@lyron.local")
bearer_token = make_invitation(email=None)
raw = redeem_as(BEARER_USER, bearer_token)

try:
    payload = json.loads(raw)
except json.JSONDecodeError:
    payload = None

check(
    "case 1 contract shape",
    isinstance(payload, dict) and "status" in payload,
    f"redeem_invitation must return a jsonb object with a status key, got: {raw!r}",
)
check(
    "case 1 bearer redemption",
    isinstance(payload, dict) and payload.get("status") == "redeemed"
    and payload.get("organization_id") == ORG_ID,
    f"a bearer (null-email) invitation must still redeem, got: {raw!r}",
)

if failures:
    raise SystemExit(
        "SEC-1 invitation redemption contract failed:\n  " + "\n  ".join(failures)
    )

print("SEC-1 invitation redemption contract passed.")
PY
```

- [ ] **Step 2: Make it executable and chain it from the suite**

```bash
chmod +x scripts/tests/invitation-redemption-contract-test.sh
```

Append to the end of `scripts/backend-write-contracts.sh`:

```bash
invitation_redemption_test_script="${INVITATION_REDEMPTION_TEST_SCRIPT:-./scripts/tests/invitation-redemption-contract-test.sh}"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$invitation_redemption_test_script"
```

- [ ] **Step 3: Run it to verify it fails**

Run: `./scripts/tests/invitation-redemption-contract-test.sh`

Expected: FAIL. `redeem_invitation` still returns a bare uuid, so `json.loads`
either fails or yields a string, and case 1 reports
`redeem_invitation must return a jsonb object with a status key`.

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/invitation-redemption-contract-test.sh scripts/backend-write-contracts.sh
git commit -m "test(db): add failing invitation redemption contract test

Pins the jsonb status envelope that redemption must return, and that a
null-email invitation stays a bearer credential. Fails against the current
uuid-returning function.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Audit schema migration

**Files:**
- Create: `supabase/migrations/202607290001_invitation_redemption_audit.sql`
- Modify: `scripts/tests/invitation-redemption-contract-test.sh`

- [ ] **Step 1: Write the failing tests for the audit schema**

In the test script, insert these cases immediately **before** the trailing
`if failures:` block:

```python
# --- Case 2: the outcome enum exists with the agreed values. -----------------
enum_values = run_sql(dedent("""
    select string_agg(e.enumlabel, ',' order by e.enumsortorder)
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'invitation_redemption_outcome';
"""))
check(
    "case 2 outcome enum",
    enum_values == "redeemed,not_found,expired,already_redeemed,"
                   "already_member,email_mismatch,rate_limited",
    f"unexpected invitation_redemption_outcome values: {enum_values!r}",
)

# --- Case 3: authenticated cannot write the audit table directly. ------------
for verb, statement in (
    ("insert", "insert into public.invitation_redemption_attempts "
               "(token_sha256, outcome) values (sha256('x'::bytea), 'not_found')"),
    ("update", "update public.invitation_redemption_attempts set outcome = 'redeemed'"),
    ("delete", "delete from public.invitation_redemption_attempts"),
):
    sql = dedent(f"""
        begin;
        select set_config('request.jwt.claim.sub', {sql_quote(BEARER_USER)}, true);
        select set_config('request.jwt.claim.role', 'authenticated', true);
        set local role authenticated;
        {statement};
        rollback;
    """)
    out = run_sql(sql, expect_error=True)
    check(
        f"case 3 audit {verb} denied",
        "denied" in out or "permission" in out or "violates row-level security" in out,
        f"authenticated {verb} on invitation_redemption_attempts was not denied: {out!r}",
    )

# A non-admin of the organization sees no attempt rows even though select is
# granted to authenticated: RLS scopes reads to organization admins.
run_sql(dedent(f"""
    insert into public.invitation_redemption_attempts
      (token_sha256, outcome, organization_id)
    values (sha256('rls-probe'::bytea), 'not_found', {sql_quote(ORG_ID)});
"""))
OUTSIDER = "aaaaaaa1-0000-0000-0000-0000000000ff"
make_user(OUTSIDER, "outsider@lyron.local")
visible = run_sql(dedent(f"""
    begin;
    select set_config('request.jwt.claim.sub', {sql_quote(OUTSIDER)}, true);
    select set_config('request.jwt.claim.role', 'authenticated', true);
    set local role authenticated;
    select count(*) from public.invitation_redemption_attempts;
    rollback;
""")).splitlines()[-1].strip()
check(
    "case 3 audit select scoped",
    visible == "0",
    f"a non-admin must not read another organization's attempts, saw {visible!r}",
)
```

`make_user` is defined above; the outsider needs an `auth.users` row before it
can be referenced as a caller.

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/tests/invitation-redemption-contract-test.sh`

Expected: FAIL with `unexpected invitation_redemption_outcome values: ''` — the
type does not exist yet.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/202607290001_invitation_redemption_audit.sql`:

```sql
-- SEC-1: persisted audit trail for every invitation redemption attempt.
-- Redemption outcomes are returned, not raised, so these rows survive the
-- transaction and can also back a count-based rate limit.

create type public.invitation_redemption_outcome as enum (
  'redeemed',
  'not_found',
  'expired',
  'already_redeemed',
  'already_member',
  'email_mismatch',
  'rate_limited'
);

create table public.invitation_redemption_attempts (
  id uuid primary key default gen_random_uuid(),
  -- Null when the presented token matches no invitation.
  invitation_id uuid references public.invitations(id) on delete set null,
  -- The raw token is a bearer credential; only its digest is retained so that
  -- repeated attempts can be correlated without creating a second leak surface.
  token_sha256 bytea not null,
  -- Nullable with on delete set null so the hourly orphan-user cleanup in
  -- 202605160006_pg_cron_orphan_cleanup.sql is never blocked by audit rows.
  actor_user_id uuid references auth.users(id) on delete set null,
  outcome public.invitation_redemption_outcome not null,
  organization_id uuid references public.organizations(id) on delete cascade,
  -- Plain now() rather than timezone('utc', now()): the value is timestamptz,
  -- so the extra conversion is redundant, and the rate-limit window compares
  -- against now() directly.
  created_at timestamptz not null default now()
);

-- Shaped for the rate-limit count: caller, recent first, suspicious outcomes only.
create index invitation_redemption_attempts_rate_limit_idx
  on public.invitation_redemption_attempts (actor_user_id, created_at desc)
  where outcome in ('not_found', 'email_mismatch');

alter table public.invitation_redemption_attempts enable row level security;

-- Organization admins can review attempts against their own organization.
-- Rows with a null organization_id (unresolved tokens) belong to no
-- organization and stay service_role-only by design.
create policy invitation_redemption_attempts_select_org_admin
  on public.invitation_redemption_attempts
  for select
  to authenticated
  using (
    organization_id is not null
    and exists (
      select 1
      from public.memberships m
      where m.user_id = auth.uid()
        and m.organization_id = invitation_redemption_attempts.organization_id
        and m.scope_type = 'organization'
        and m.role_code = 'organization_admin'
        and m.status = 'active'
    )
  );

-- Writes happen only through the security-definer redemption path.
create policy invitation_redemption_attempts_no_direct_insert
  on public.invitation_redemption_attempts for insert
  to authenticated
  with check (false);

create policy invitation_redemption_attempts_no_direct_update
  on public.invitation_redemption_attempts for update
  to authenticated
  using (false);

create policy invitation_redemption_attempts_no_direct_delete
  on public.invitation_redemption_attempts for delete
  to authenticated
  using (false);

revoke all on table public.invitation_redemption_attempts from anon, authenticated;
grant select on table public.invitation_redemption_attempts to authenticated;
```

- [ ] **Step 4: Reset the database and run the test**

```bash
./scripts/db-reset.sh && ./scripts/tests/invitation-redemption-contract-test.sh
```

Expected: cases 2 and 3 pass; case 1 still fails on the contract shape (the
function is untouched so far).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290001_invitation_redemption_audit.sql scripts/tests/invitation-redemption-contract-test.sh
git commit -m "feat(db): add invitation redemption audit table

Outcome enum, attempt table keyed for the rate-limit query, RLS that denies
all direct writes and scopes reads to organization admins, and a token digest
column so the bearer token itself is never copied into the audit trail.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: `redeem_invitation` returns jsonb and audits every path

**Files:**
- Create: `supabase/migrations/202607290002_invitation_redemption_contract.sql`
- Modify: `scripts/tests/invitation-redemption-contract-test.sh`

- [ ] **Step 1: Write the failing tests for the outcome matrix**

Add a helper next to `redeem_as` in the test script:

```python
def redeem_payload(user_id, token):
    raw = redeem_as(user_id, token)
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"status": f"<unparsable: {raw!r}>"}


def attempt_rows(user_id):
    out = run_sql(dedent(f"""
        select outcome, coalesce(invitation_id::text, ''),
               coalesce(organization_id::text, ''), length(token_sha256)
        from public.invitation_redemption_attempts
        where actor_user_id = {sql_quote(user_id)}
        order by created_at;
    """))
    rows = []
    for line in out.splitlines():
        if line.strip():
            rows.append(line.split("\t"))
    return rows
```

Then add these cases before the trailing `if failures:` block:

```python
# --- Case 4: the successful bearer redemption from case 1 was audited. -------
rows = attempt_rows(BEARER_USER)
check(
    "case 4 success audited",
    len(rows) == 1 and rows[0][0] == "redeemed" and rows[0][1] != ""
    and rows[0][2] == ORG_ID and rows[0][3] == "32",
    f"expected one audited 'redeemed' attempt with a 32-byte digest, got: {rows!r}",
)

# --- Case 5: an unknown token returns not_found and audits a null invitation. -
make_user(WRONG_USER, "wrong@lyron.local")
payload = redeem_payload(WRONG_USER, "definitely-not-a-real-token")
check(
    "case 5 not_found status",
    payload.get("status") == "not_found" and payload.get("organization_id") is None,
    f"unknown token must return not_found, got: {payload!r}",
)
rows = attempt_rows(WRONG_USER)
check(
    "case 5 not_found audited",
    len(rows) == 1 and rows[0][0] == "not_found" and rows[0][1] == ""
    and rows[0][2] == "" and rows[0][3] == "32",
    f"expected an audited not_found attempt with no invitation, got: {rows!r}",
)

# --- Case 6: a second redemption of the same token reports already_redeemed. --
SECOND_USER = "aaaaaaa1-0000-0000-0000-000000000004"
make_user(SECOND_USER, "second@lyron.local")
payload = redeem_payload(SECOND_USER, bearer_token)
check(
    "case 6 already_redeemed",
    payload.get("status") == "already_redeemed",
    f"a spent token must report already_redeemed, got: {payload!r}",
)

# --- Case 7: an expired invitation reports expired. --------------------------
EXPIRED_USER = "aaaaaaa1-0000-0000-0000-000000000005"
make_user(EXPIRED_USER, "expired@lyron.local")
expired_token = make_invitation(email=None)
run_sql(
    "update public.invitations set expires_at = now() - interval '1 day' "
    f"where token = {sql_quote(expired_token)};"
)
payload = redeem_payload(EXPIRED_USER, expired_token)
check(
    "case 7 expired",
    payload.get("status") == "expired",
    f"an expired token must report expired, got: {payload!r}",
)

# --- Case 8: an existing member reports already_member. ----------------------
member_token = make_invitation(email=None)
payload = redeem_payload(BEARER_USER, member_token)
check(
    "case 8 already_member",
    payload.get("status") == "already_member",
    f"an existing member must report already_member, got: {payload!r}",
)

# --- Case 9: no failed outcome may create a membership. ----------------------
membership_count = run_sql(dedent(f"""
    select count(*) from public.memberships
    where user_id in ({sql_quote(WRONG_USER)}, {sql_quote(SECOND_USER)},
                      {sql_quote(EXPIRED_USER)})
      and status = 'active';
"""))
check(
    "case 9 no membership from failures",
    membership_count == "0",
    f"failed redemptions must not create memberships, got {membership_count}",
)

# --- Case 10: grants survived the drop-and-recreate. -------------------------
grants = run_sql(dedent("""
    select
      has_function_privilege('authenticated', 'public.redeem_invitation(text)', 'execute'),
      has_function_privilege('anon', 'public.redeem_invitation(text)', 'execute'),
      has_function_privilege('authenticated',
        'public.record_invitation_redemption_attempt('
        'uuid, bytea, uuid, public.invitation_redemption_outcome, uuid)', 'execute');
""")).split("\t")
check(
    "case 10 execute grants",
    grants == ["t", "f", "f"],
    "expected redeem_invitation executable by authenticated only and the audit "
    f"helper executable by neither, got: {grants!r}",
)
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/db-reset.sh && ./scripts/tests/invitation-redemption-contract-test.sh`

Expected: FAIL. Case 1 still reports the wrong contract shape, and cases 4–9
report unparsable payloads because the function still returns a bare uuid and
raises.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/202607290002_invitation_redemption_contract.sql`:

```sql
-- SEC-1: redemption reports business outcomes as a returned status instead of
-- raising. Raising aborts the transaction, which would roll back the audit row
-- written alongside it; returning lets every attempt persist.

create or replace function public.record_invitation_redemption_attempt(
  p_invitation_id uuid,
  p_token_sha256 bytea,
  p_actor uuid,
  p_outcome public.invitation_redemption_outcome,
  p_organization_id uuid
)
returns jsonb
language plpgsql
set search_path = public
as $$
begin
  insert into public.invitation_redemption_attempts (
    invitation_id, token_sha256, actor_user_id, outcome, organization_id
  ) values (
    p_invitation_id, p_token_sha256, p_actor, p_outcome, p_organization_id
  );

  return jsonb_build_object(
    'status', p_outcome::text,
    'organization_id',
    case when p_outcome = 'redeemed' then p_organization_id else null end
  );
end;
$$;

-- Not granted to any client role: it writes the audit trail and is only ever
-- reached through the security-definer redemption function below.
revoke all on function public.record_invitation_redemption_attempt(
  uuid, bytea, uuid, public.invitation_redemption_outcome, uuid
) from public, anon, authenticated;

-- The return type changes from uuid to jsonb, which create or replace cannot
-- do. Dropping discards the grants set in 202605160007_auth_boundary_hardening,
-- so they are reapplied at the end of this migration.
drop function if exists public.redeem_invitation(text);

create function public.redeem_invitation(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_inv public.invitations%rowtype;
  v_token_sha256 bytea := sha256(convert_to(p_token, 'UTF8'));
begin
  -- The only remaining raise: with no caller there is nothing to audit or to
  -- key a rate-limit bucket to, and execute is granted to authenticated only.
  if v_caller is null then
    raise exception using
      errcode = '42501',
      message = 'invitation_redeem_requires_auth';
  end if;

  select * into v_inv
  from public.invitations
  where token = p_token
  for update;

  if not found then
    return public.record_invitation_redemption_attempt(
      null, v_token_sha256, v_caller, 'not_found', null
    );
  end if;

  if v_inv.redeemed_at is not null then
    return public.record_invitation_redemption_attempt(
      v_inv.id, v_token_sha256, v_caller, 'already_redeemed', v_inv.organization_id
    );
  end if;

  if v_inv.expires_at <= now() then
    return public.record_invitation_redemption_attempt(
      v_inv.id, v_token_sha256, v_caller, 'expired', v_inv.organization_id
    );
  end if;

  if exists (
    select 1
    from public.memberships m
    where m.user_id = v_caller
      and m.organization_id = v_inv.organization_id
      and m.scope_type = 'organization'
      and m.status = 'active'
  ) then
    return public.record_invitation_redemption_attempt(
      v_inv.id, v_token_sha256, v_caller, 'already_member', v_inv.organization_id
    );
  end if;

  insert into public.memberships (
    organization_id, user_id, scope_type, role_code, status
  ) values (
    v_inv.organization_id, v_caller, 'organization', v_inv.role_code, 'active'
  );

  update public.invitations
  set redeemed_at = now(),
      redeemed_by = v_caller
  where id = v_inv.id;

  return public.record_invitation_redemption_attempt(
    v_inv.id, v_token_sha256, v_caller, 'redeemed', v_inv.organization_id
  );
end;
$$;

revoke all on function public.redeem_invitation(text)
from public, anon, authenticated;
grant execute on function public.redeem_invitation(text) to authenticated;
```

- [ ] **Step 4: Run to verify it passes**

Run: `./scripts/db-reset.sh && ./scripts/tests/invitation-redemption-contract-test.sh`

Expected: PASS — `SEC-1 invitation redemption contract passed.`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290002_invitation_redemption_contract.sql scripts/tests/invitation-redemption-contract-test.sh
git commit -m "feat(db): return redemption outcomes instead of raising

A raised exception aborts the transaction and takes the audit row with it, so
business outcomes now come back as a jsonb status envelope and every attempt
is recorded. The uuid-to-jsonb return type forces a drop and recreate, which
discards grants, so the migration reapplies them and a contract test pins them.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Email binding for invitations that carry an email

**Files:**
- Modify: `supabase/migrations/202607290002_invitation_redemption_contract.sql`
- Modify: `scripts/tests/invitation-redemption-contract-test.sh`

- [ ] **Step 1: Write the failing tests**

Add before the trailing `if failures:` block:

```python
# --- Case 11: an email-bound invitation redeems for the invited address. ------
make_user(BOUND_USER, "bound@lyron.local")
bound_token = make_invitation(email="BOUND@Lyron.local  ")
payload = redeem_payload(BOUND_USER, bound_token)
check(
    "case 11 bound redemption",
    payload.get("status") == "redeemed" and payload.get("organization_id") == ORG_ID,
    f"invited address must redeem, case-and-whitespace-insensitively, got: {payload!r}",
)

# --- Case 12: a different caller cannot redeem an email-bound invitation. -----
MISMATCH_USER = "aaaaaaa1-0000-0000-0000-000000000006"
make_user(MISMATCH_USER, "someone.else@lyron.local")
mismatch_token = make_invitation(email="invited@lyron.local")
payload = redeem_payload(MISMATCH_USER, mismatch_token)
check(
    "case 12 email_mismatch",
    payload.get("status") == "email_mismatch",
    f"a non-invited caller must be refused, got: {payload!r}",
)
still_open = run_sql(
    "select redeemed_at is null from public.invitations "
    f"where token = {sql_quote(mismatch_token)};"
)
check(
    "case 12 invitation untouched",
    still_open == "t",
    "a refused redemption must leave the invitation unredeemed",
)
membership_count = run_sql(
    "select count(*) from public.memberships "
    f"where user_id = {sql_quote(MISMATCH_USER)} and status = 'active';"
)
check(
    "case 12 no membership",
    membership_count == "0",
    f"email mismatch must not create a membership, got {membership_count}",
)
rows = attempt_rows(MISMATCH_USER)
check(
    "case 12 mismatch audited",
    len(rows) == 1 and rows[0][0] == "email_mismatch" and rows[0][1] != ""
    and rows[0][2] == ORG_ID,
    f"expected one audited email_mismatch attempt against the org, got: {rows!r}",
)

# --- Case 13: unconfirmed and address-less callers are refused too. -----------
UNCONFIRMED_USER = "aaaaaaa1-0000-0000-0000-000000000007"
make_user(UNCONFIRMED_USER, "unconfirmed@lyron.local", confirmed=False)
unconfirmed_token = make_invitation(email="unconfirmed@lyron.local")
payload = redeem_payload(UNCONFIRMED_USER, unconfirmed_token)
check(
    "case 13 unconfirmed refused",
    payload.get("status") == "email_mismatch",
    f"an unconfirmed address must not satisfy the binding, got: {payload!r}",
)

NO_EMAIL_USER = "aaaaaaa1-0000-0000-0000-000000000008"
make_user(NO_EMAIL_USER, None)
no_email_token = make_invitation(email="anybody@lyron.local")
payload = redeem_payload(NO_EMAIL_USER, no_email_token)
check(
    "case 13 address-less refused",
    payload.get("status") == "email_mismatch",
    f"a caller with no address must be refused, got: {payload!r}",
)
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/db-reset.sh && ./scripts/tests/invitation-redemption-contract-test.sh`

Expected: FAIL on case 12 — without binding, the non-invited caller redeems and
the payload reports `redeemed` instead of `email_mismatch`.

- [ ] **Step 3: Add the binding check to the migration**

In `supabase/migrations/202607290002_invitation_redemption_contract.sql`, add to
the `declare` block of `redeem_invitation`:

```sql
  v_caller_email text;
```

and insert this block **between** the expiry check and the existing-membership
check:

```sql
  -- Hybrid binding: an invitation carrying an email is redeemable only by the
  -- account holding that confirmed address; a null email stays a bearer link.
  -- The account record is read rather than the JWT email claim: the function is
  -- already security definer, and the record is current where a claim can be
  -- stale after an address change.
  if v_inv.email is not null then
    select u.email into v_caller_email
    from auth.users u
    where u.id = v_caller
      and u.email_confirmed_at is not null;

    if v_caller_email is null
      or lower(btrim(v_caller_email)) is distinct from lower(btrim(v_inv.email))
    then
      return public.record_invitation_redemption_attempt(
        v_inv.id, v_token_sha256, v_caller, 'email_mismatch', v_inv.organization_id
      );
    end if;
  end if;
```

- [ ] **Step 4: Run to verify it passes**

Run: `./scripts/db-reset.sh && ./scripts/tests/invitation-redemption-contract-test.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290002_invitation_redemption_contract.sql scripts/tests/invitation-redemption-contract-test.sh
git commit -m "feat(db): bind redemption to the invited email when present

An invitation carrying an email now only redeems for the account holding that
confirmed address; a null email keeps the bearer-link behaviour, so an admin
chooses per invitation. The comparison reads auth.users rather than the JWT
claim, and requires email_confirmed_at so an unverified address cannot satisfy
the binding.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Caller-keyed rate limit on suspicious outcomes

**Files:**
- Modify: `supabase/migrations/202607290002_invitation_redemption_contract.sql`
- Modify: `scripts/tests/invitation-redemption-contract-test.sh`

- [ ] **Step 1: Write the failing tests**

Add before the trailing `if failures:` block:

```python
# --- Case 14: ten suspicious attempts trip the limit for a valid token. ------
PROBER_USER = "aaaaaaa1-0000-0000-0000-000000000009"
make_user(PROBER_USER, "prober@lyron.local")
valid_token = make_invitation(email=None)

for i in range(10):
    payload = redeem_payload(PROBER_USER, f"guess-{i}")
    check(
        f"case 14 probe {i} not_found",
        payload.get("status") == "not_found",
        f"probe {i} should report not_found, got: {payload!r}",
    )

payload = redeem_payload(PROBER_USER, valid_token)
check(
    "case 14 rate limited",
    payload.get("status") == "rate_limited",
    f"the 11th attempt must be rate limited even with a valid token, got: {payload!r}",
)
membership_count = run_sql(
    "select count(*) from public.memberships "
    f"where user_id = {sql_quote(PROBER_USER)} and status = 'active';"
)
check(
    "case 14 no membership while limited",
    membership_count == "0",
    f"a rate-limited call must not create a membership, got {membership_count}",
)
check(
    "case 14 token still redeemable",
    run_sql("select redeemed_at is null from public.invitations "
            f"where token = {sql_quote(valid_token)};") == "t",
    "a rate-limited call must leave the invitation unredeemed",
)

# --- Case 15: benign outcomes do not accumulate toward the limit. ------------
PATIENT_USER = "aaaaaaa1-0000-0000-0000-00000000000a"
make_user(PATIENT_USER, "patient@lyron.local")
spent_token = make_invitation(email=None)
run_sql(dedent(f"""
    update public.invitations
    set redeemed_at = now(), redeemed_by = {sql_quote(BEARER_USER)}
    where token = {sql_quote(spent_token)};
"""))
for i in range(12):
    payload = redeem_payload(PATIENT_USER, spent_token)
    check(
        f"case 15 benign attempt {i}",
        payload.get("status") == "already_redeemed",
        f"benign retry {i} must stay already_redeemed, got: {payload!r}",
    )

patient_token = make_invitation(email=None)
payload = redeem_payload(PATIENT_USER, patient_token)
check(
    "case 15 not locked out",
    payload.get("status") == "redeemed",
    f"benign retries must not lock a real user out, got: {payload!r}",
)
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/db-reset.sh && ./scripts/tests/invitation-redemption-contract-test.sh`

Expected: FAIL on `case 14 rate limited` — the 11th call still reports
`redeemed`.

- [ ] **Step 3: Add the rate limit to the migration**

Add to the `declare` block of `redeem_invitation`:

```sql
  v_suspicious_attempts integer;
```

and insert this block immediately **after** the `v_caller is null` guard, before
the invitation lookup:

```sql
  -- Only outcomes that look like token probing count. Benign retries (expired,
  -- already redeemed, already a member) are excluded so a real user retrying a
  -- stale link cannot lock themselves out. The window expires on its own.
  select count(*) into v_suspicious_attempts
  from public.invitation_redemption_attempts a
  where a.actor_user_id = v_caller
    and a.outcome in ('not_found', 'email_mismatch')
    and a.created_at > now() - interval '15 minutes';

  if v_suspicious_attempts >= 10 then
    return public.record_invitation_redemption_attempt(
      null, v_token_sha256, v_caller, 'rate_limited', null
    );
  end if;
```

- [ ] **Step 4: Run to verify it passes**

Run: `./scripts/db-reset.sh && ./scripts/tests/invitation-redemption-contract-test.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290002_invitation_redemption_contract.sql scripts/tests/invitation-redemption-contract-test.sh
git commit -m "feat(db): rate limit invitation redemption per caller

Ten not_found or email_mismatch outcomes within fifteen minutes suspend
redemption for that caller, including for a valid token. Benign outcomes are
excluded so a user retrying a stale link cannot lock themselves out.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Audit retention job

**Files:**
- Modify: `supabase/migrations/202607290001_invitation_redemption_audit.sql`
- Modify: `scripts/tests/invitation-redemption-contract-test.sh`

- [ ] **Step 1: Write the failing test**

Add before the trailing `if failures:` block:

```python
# --- Case 16: audit rows have a scheduled retention job. ---------------------
retention = run_sql(dedent("""
    select coalesce(string_agg(jobname || '|' || schedule, ','), '')
    from cron.job
    where jobname = 'cleanup-invitation-redemption-attempts';
"""))
check(
    "case 16 retention job",
    retention.startswith("cleanup-invitation-redemption-attempts|"),
    f"expected a scheduled retention job for the audit table, got: {retention!r}",
)
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/db-reset.sh && ./scripts/tests/invitation-redemption-contract-test.sh`

Expected: FAIL with `expected a scheduled retention job for the audit table, got: ''`

- [ ] **Step 3: Add the job to the audit migration**

Append to `supabase/migrations/202607290001_invitation_redemption_audit.sql`:

```sql
-- pg_cron is created by 202605160006_pg_cron_orphan_cleanup.sql, which runs
-- earlier; this only adds the retention job alongside the existing cleanup.
select cron.schedule(
  'cleanup-invitation-redemption-attempts',
  '30 3 * * *',
  $cron$
    delete from public.invitation_redemption_attempts
    where created_at < now() - interval '90 days'
  $cron$
);
```

- [ ] **Step 4: Run to verify it passes**

Run: `./scripts/db-reset.sh && ./scripts/tests/invitation-redemption-contract-test.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290001_invitation_redemption_audit.sql scripts/tests/invitation-redemption-contract-test.sh
git commit -m "feat(db): expire invitation audit rows after 90 days

Keeps the audit table bounded, scheduled next to the existing hourly orphan
cleanup.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Dart status mapping replaces message mapping

**Files:**
- Modify: `apps/lyron_app/lib/src/domain/auth/invitation_error.dart`
- Create: `apps/lyron_app/test/domain/auth/invitation_error_test.dart`

- [ ] **Step 1: Write the failing test**

Create `apps/lyron_app/test/domain/auth/invitation_error_test.dart`:

```dart
// apps/lyron_app/test/domain/auth/invitation_error_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';

void main() {
  test('maps every redemption status to an InvitationError', () {
    expect(invitationErrorFromStatus('not_found'), InvitationError.notFound);
    expect(invitationErrorFromStatus('expired'), InvitationError.expired);
    expect(
      invitationErrorFromStatus('already_redeemed'),
      InvitationError.alreadyRedeemed,
    );
    expect(
      invitationErrorFromStatus('already_member'),
      InvitationError.alreadyMember,
    );
    expect(
      invitationErrorFromStatus('email_mismatch'),
      InvitationError.emailMismatch,
    );
    expect(
      invitationErrorFromStatus('rate_limited'),
      InvitationError.rateLimited,
    );
  });

  test('maps an unknown or missing status to unknown', () {
    expect(invitationErrorFromStatus('something_else'), InvitationError.unknown);
    expect(invitationErrorFromStatus(null), InvitationError.unknown);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/lyron_app && flutter test test/domain/auth/invitation_error_test.dart`

Expected: FAIL — `invitationErrorFromStatus` is not defined.

- [ ] **Step 3: Rewrite the mapping**

Replace the whole of `apps/lyron_app/lib/src/domain/auth/invitation_error.dart`:

```dart
enum InvitationError {
  notFound,
  expired,
  alreadyRedeemed,
  alreadyMember,
  emailMismatch,
  rateLimited,
  network,
  unknown,
}

/// Maps the `status` field of the `redeem_invitation` RPC response.
///
/// The backend reports business outcomes as returned statuses rather than
/// raised errors so that each attempt can be audited; see ADR-025.
InvitationError invitationErrorFromStatus(String? status) {
  switch (status) {
    case 'not_found':
      return InvitationError.notFound;
    case 'expired':
      return InvitationError.expired;
    case 'already_redeemed':
      return InvitationError.alreadyRedeemed;
    case 'already_member':
      return InvitationError.alreadyMember;
    case 'email_mismatch':
      return InvitationError.emailMismatch;
    case 'rate_limited':
      return InvitationError.rateLimited;
    default:
      return InvitationError.unknown;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd apps/lyron_app && flutter test test/domain/auth/invitation_error_test.dart`

Expected: PASS. Note that `flutter analyze` will now report errors in
`supabase_invitation_repository.dart` and `redeem_progress_screen.dart` — Task 8
and Task 9 resolve them.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/domain/auth/invitation_error.dart apps/lyron_app/test/domain/auth/invitation_error_test.dart
git commit -m "feat(auth): map redemption status codes to InvitationError

Replaces the raised-message mapping with a status mapping and adds the two
new outcomes the backend can now report.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Repository reads the jsonb envelope

**Files:**
- Modify: `apps/lyron_app/lib/src/infrastructure/auth/supabase_invitation_repository.dart`
- Modify: `apps/lyron_app/test/infrastructure/auth/supabase_invitation_repository_test.dart`

- [ ] **Step 1: Rewrite the repository test**

Replace the whole of
`apps/lyron_app/test/infrastructure/auth/supabase_invitation_repository_test.dart`:

```dart
// apps/lyron_app/test/infrastructure/auth/supabase_invitation_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_invitation_repository.dart';

void main() {
  test('redeem returns success for a redeemed status', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => <String, dynamic>{
        'status': 'redeemed',
        'organization_id': '00000000-0000-0000-0000-0000000000aa',
      },
    );
    final result = await repo.redeem('tok');
    expect(result, isA<RedeemSuccess>());
    expect(
      (result as RedeemSuccess).organizationId,
      '00000000-0000-0000-0000-0000000000aa',
    );
  });

  test('redeem maps a failure status to InvitationError', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => <String, dynamic>{
        'status': 'email_mismatch',
        'organization_id': null,
      },
    );
    final result = await repo.redeem('tok');
    expect((result as RedeemFailure).error, InvitationError.emailMismatch);
  });

  test('redeem maps rate limiting to its own error', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => <String, dynamic>{
        'status': 'rate_limited',
        'organization_id': null,
      },
    );
    final result = await repo.redeem('tok');
    expect((result as RedeemFailure).error, InvitationError.rateLimited);
  });

  test('redeem fails safely when the payload is malformed', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => <String, dynamic>{'status': 'redeemed'},
    );
    final result = await repo.redeem('tok');
    expect((result as RedeemFailure).error, InvitationError.unknown);
  });

  test('redeem maps a connectivity failure to network', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => throw const SocketExceptionStub(),
    );
    final result = await repo.redeem('tok');
    expect((result as RedeemFailure).error, InvitationError.network);
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketException: Failed host lookup';
}
```

Before running, confirm that `isConnectivityFailure`
(`apps/lyron_app/lib/src/shared/connectivity_failure.dart`) classifies this stub
as a connectivity failure. If it inspects the runtime type rather than the
message, replace `SocketExceptionStub` with whatever that helper actually
recognises, and keep the assertion.

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/lyron_app && flutter test test/infrastructure/auth/supabase_invitation_repository_test.dart`

Expected: FAIL — `RedeemFn` still returns `Future<String>`, so the map literals
do not type-check.

- [ ] **Step 3: Rewrite the repository**

Replace the whole of
`apps/lyron_app/lib/src/infrastructure/auth/supabase_invitation_repository.dart`:

```dart
// apps/lyron_app/lib/src/infrastructure/auth/supabase_invitation_repository.dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';
import 'package:lyron_app/src/shared/connectivity_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef RedeemFn = Future<Map<String, dynamic>> Function(String token);

class SupabaseInvitationRepository implements InvitationRepository {
  SupabaseInvitationRepository(SupabaseClient client)
    : this.testing(
        redeem: (token) async {
          final result = await client.rpc(
            'redeem_invitation',
            params: {'p_token': token},
          );
          return (result as Map).cast<String, dynamic>();
        },
      );

  @visibleForTesting
  SupabaseInvitationRepository.testing({required RedeemFn redeem})
    : _redeem = redeem;

  final RedeemFn _redeem;

  @override
  Future<RedeemResult> redeem(String token) async {
    try {
      final payload = await _redeem(token);
      final status = payload['status'];
      if (status == 'redeemed') {
        final organizationId = payload['organization_id'];
        if (organizationId is String && organizationId.isNotEmpty) {
          return RedeemSuccess(organizationId);
        }
        // A redeemed status without an organization id is not actionable.
        return const RedeemFailure(InvitationError.unknown);
      }
      return RedeemFailure(
        invitationErrorFromStatus(status is String ? status : null),
      );
    } on PostgrestException {
      // Only the unauthenticated guard still raises, and the client never
      // reaches redemption without a session.
      return const RedeemFailure(InvitationError.unknown);
    } catch (e) {
      return RedeemFailure(
        isConnectivityFailure(e)
            ? InvitationError.network
            : InvitationError.unknown,
      );
    }
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd apps/lyron_app && flutter test test/infrastructure/auth/supabase_invitation_repository_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/infrastructure/auth/supabase_invitation_repository.dart apps/lyron_app/test/infrastructure/auth/supabase_invitation_repository_test.dart
git commit -m "feat(auth): read the redemption status envelope

The RPC now returns {status, organization_id}; a malformed payload degrades to
an unknown failure rather than throwing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Surface the new outcomes in the redeem UI

**Files:**
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart:280`
- Modify: `apps/lyron_app/lib/src/presentation/auth/redeem_progress_screen.dart:61-73`
- Modify: `apps/lyron_app/test/integration/invite_redeem_flow_test.dart` (only if it stubs `RedeemFn`)

- [ ] **Step 1: Add the copy**

In `apps/lyron_app/lib/src/shared/app_strings.dart`, directly after
`inviteErrorAlreadyMember`:

```dart
  static const inviteErrorEmailMismatch =
      'This invite was issued to a different email address.';
  static const inviteErrorRateLimited =
      'Too many attempts. Wait a few minutes and try again.';
```

- [ ] **Step 2: Confirm the compile failure**

There is no `redeem_progress_screen_test.dart`; the failing check here is the
analyzer. `_messageFor` is an exhaustive `switch` over `InvitationError`, so
Task 7's two new enum cases make it non-exhaustive.

Run: `cd apps/lyron_app && flutter analyze`

Expected: an error on `_messageFor` in `redeem_progress_screen.dart` reporting
that the switch does not handle `emailMismatch` and `rateLimited`.

- [ ] **Step 3: Handle the new cases**

In `apps/lyron_app/lib/src/presentation/auth/redeem_progress_screen.dart`,
replace `_messageFor` and `_isRetryableError`:

```dart
  String _messageFor(InvitationError error) => switch (error) {
    InvitationError.notFound => AppStrings.inviteErrorNotFound,
    InvitationError.expired => AppStrings.inviteErrorExpired,
    InvitationError.alreadyRedeemed => AppStrings.inviteErrorAlreadyRedeemed,
    InvitationError.alreadyMember => AppStrings.inviteErrorAlreadyMember,
    InvitationError.emailMismatch => AppStrings.inviteErrorEmailMismatch,
    InvitationError.rateLimited => AppStrings.inviteErrorRateLimited,
    InvitationError.network ||
    InvitationError.unknown => AppStrings.inviteErrorNetwork,
  };

  bool _isRetryableError(InvitationError error) => switch (error) {
    InvitationError.network || InvitationError.unknown => true,
    // Rate limiting clears on its own, so retrying is the correct affordance.
    InvitationError.rateLimited => true,
    _ => false,
  };
```

- [ ] **Step 4: Run the full Flutter suite and the analyzer**

```bash
cd apps/lyron_app && flutter analyze && flutter test
```

Expected: analyzer clean, all tests pass.
`test/integration/invite_redeem_flow_test.dart` stubs `InvitationRepository` at
the application layer (`_SuccessRepo`), not the RPC, so it needs no change — if
it fails, that is a real regression, not a stub mismatch.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(auth): show email-mismatch and rate-limit outcomes

Rate limiting is presented as retryable because the window clears on its own.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Documentation

**Files:**
- Create: `docs/architecture/decisions/ADR-025-invitation-redemption-model.md`
- Modify: `docs/architecture/repository-review-2026-06-22.md:228-235`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/testing/testing-strategy.md`

- [ ] **Step 1: Write the ADR**

Create `docs/architecture/decisions/ADR-025-invitation-redemption-model.md`.
Match the heading structure of `ADR-022-active-organization-resolver.md`. It must
record:

- **Context**: SEC-1 — redemption was a pure bearer credential with no rate
  limiting and no audit of attempts.
- **Decision**: hybrid binding (email-bound when `invitations.email` is set,
  bearer otherwise); caller-keyed rate limit of 10 `not_found`/`email_mismatch`
  outcomes per 15 minutes; an audit row for every attempt; business outcomes
  returned as a `jsonb` status envelope rather than raised.
- **Why outcomes are returned, not raised**: a raised exception aborts the
  transaction and discards the audit row written with it, so neither a real audit
  trail nor a count-based rate limit is possible while the function raises.
- **Rejected — strict email binding always**: the admin types the address, but an
  SSO sign-in can arrive with a different verified address, leaving legitimate
  invitees locked out with no recovery short of reissuing.
- **Rejected — documented bearer model**: simplest, but leaves a leaked link
  equal to organization membership, which is the finding itself.
- **Rejected — `dblink` autonomous logging**: preserves the RPC signature but
  adds an extension, loopback credentials, and a fragile CI path.
- **Email source**: `auth.users.email` with `email_confirmed_at is not null`,
  not the JWT claim; the claim can be stale after an address change and
  `auth.email()` is deprecated upstream.
- **Standing constraint**: the binding is only as strong as email-ownership
  verification. The hosted project must keep signup email confirmation enabled;
  `supabase/config.toml` disables it for local development only.
- **Consequences**: the RPC contract is breaking for clients built before this
  migration; the audit table is bounded by a 90-day retention job; token digests,
  never raw tokens, are stored.

- [ ] **Step 2: Mark SEC-1 fixed in the review document**

In `docs/architecture/repository-review-2026-06-22.md`, follow the existing SEC-5
convention (`~~struck~~` heading plus a `**Status (...)**` paragraph). Strike the
SEC-1 recommendation sentence and append:

```markdown
**Status (2026-07-29, security read-boundary phase 3, SEC-1): fixed.** Redemption
is email-bound when the invitation carries an address
(`supabase/migrations/202607290002_invitation_redemption_contract.sql`), rate
limited per caller, and audited in
`public.invitation_redemption_attempts`
(`supabase/migrations/202607290001_invitation_redemption_audit.sql`). Model and
rejected alternatives recorded in ADR-025; pinned by
`scripts/tests/invitation-redemption-contract-test.sh`.
```

Also update the row for SEC-1 in the findings table (line 62) and the "Still
open" list (line 156) so SEC-1 no longer appears as open.

- [ ] **Step 3: Update the architecture document**

In `docs/architecture/architecture.md`, find the section describing the auth
boundary (identity vs. membership) and extend it: redemption is backend-enforced,
returns a status envelope, is email-bound when the invitation carries an address,
is rate limited per caller, and writes an audit row for every attempt. Link
ADR-025.

- [ ] **Step 4: Register the contract test**

In `docs/testing/testing-strategy.md`, add
`scripts/tests/invitation-redemption-contract-test.sh` to the list of backend
write-contract scripts, described as the SEC-1 redemption outcome matrix.

- [ ] **Step 5: Commit**

```bash
git add docs/
git commit -m "docs(security): record the invitation redemption model

ADR-025 captures the hybrid binding, the rate-limit policy, the returned-status
contract and why the two rejected models were rejected. SEC-1 marked fixed in
the repository review.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Slice verification

**Files:** none modified unless verification finds a defect.

- [ ] **Step 1: Run the backend contract suite end to end**

```bash
./scripts/backend-write-contracts.sh
```

Expected: every chained script passes, ending with
`SEC-1 invitation redemption contract passed.`

- [ ] **Step 2: Run the migration check and the full local verify**

```bash
./scripts/verify.sh
```

Expected: PASS.

- [ ] **Step 3: Confirm the audit table holds no raw tokens**

```bash
docker exec -i "$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1)" \
  psql -U postgres -d postgres -X -qAt -c \
  "select column_name, data_type from information_schema.columns
   where table_schema = 'public'
     and table_name = 'invitation_redemption_attempts' order by ordinal_position;"
```

Expected: a `token_sha256` column of type `bytea` and **no** column holding the
token in plain text.

- [ ] **Step 4: Request code review**

Use `superpowers:requesting-code-review` on the slice diff
(`git diff main...HEAD`) before moving on to S7. Review this slice now rather
than at PR time.

- [ ] **Step 5: Handle findings**

Use `superpowers:receiving-code-review`. Verify each finding technically before
implementing it — in particular, push back on any claim about authorization
semantics that contradicts the contract tests, rather than performing the change.

---

## Verification checklist for the whole slice

- [ ] `./scripts/backend-write-contracts.sh` passes, including the new script.
- [ ] `./scripts/verify.sh` passes.
- [ ] `cd apps/lyron_app && flutter analyze && flutter test` passes.
- [ ] SEC-1 is struck through in `docs/architecture/repository-review-2026-06-22.md`
      and removed from the "Still open" list.
- [ ] ADR-025 exists and records both rejected alternatives.
- [ ] No raw invitation token is persisted anywhere new.
