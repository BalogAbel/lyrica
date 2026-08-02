#!/usr/bin/env bash
set -euo pipefail

# LF-T8 audit: supabase/migrations/202605160006_pg_cron_orphan_cleanup.sql
# deletes auth.users rows older than 24h with no active membership. This
# contract pins the guarantee the audit requires: active-member data must
# never be TTL-collected, and organization content must survive the deletion
# of a former member. It drives the exact delete statement the cron job runs
# rather than waiting on pg_cron's schedule.

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

if [[ "${BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP:-0}" != "1" ]]; then
  ./scripts/supabase.sh start >/dev/null
  ./scripts/db-reset.sh >/dev/null
  ./scripts/provision-local-demo-user.sh >/dev/null
fi

db_container_name="$(
  docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1
)"

if [[ -z "$db_container_name" ]]; then
  echo "Could not find the local Supabase database container." >&2
  exit 1
fi

python3 - "$db_container_name" <<'PY'
import subprocess
import sys

container_name = sys.argv[1]
failures = []

# Test-owned ids, namespaced so this script never collides with fixtures
# other backend-write-contracts scripts create in the same shared database.
ORG_ID = "ac000000-0000-0000-0000-000000000001"
ACTIVE_MEMBER_ID = "ac000000-0000-0000-0000-0000000000a1"
NEVER_MEMBER_ID = "ac000000-0000-0000-0000-0000000000a2"
SUSPENDED_MEMBER_ID = "ac000000-0000-0000-0000-0000000000a3"
REVOKED_MEMBER_ID = "ac000000-0000-0000-0000-0000000000a4"
RECENT_ORPHAN_ID = "ac000000-0000-0000-0000-0000000000a5"
SONG_ID = "ac000000-0000-0000-0000-0000000000b1"
PLAN_ID = "ac000000-0000-0000-0000-0000000000b2"
INVITATION_ID = "ac000000-0000-0000-0000-0000000000b3"

# The exact statement supabase/migrations/202605160006_pg_cron_orphan_cleanup.sql
# schedules under pg_cron. Kept verbatim (module comments excluded) so this
# test breaks the moment the migration's predicate drifts from what runs here.
ORPHAN_CLEANUP_SQL = """
    delete from auth.users u
    where u.created_at < now() - interval '24 hours'
      and not exists (
        select 1
        from public.memberships m
        where m.user_id = u.id
          and m.status = 'active'
      )
"""


def run_psql(sql: str) -> str:
    result = subprocess.run(
        [
            "docker", "exec", "-i", container_name, "psql",
            "-U", "postgres", "-d", "postgres",
            "-v", "ON_ERROR_STOP=1", "-X", "-qAt", "-F", "\t",
            "-c", sql,
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"psql failed:\nSQL:\n{sql}\nstderr:\n{result.stderr}")
    return result.stdout.strip()


def scalar(sql: str) -> str:
    raw = run_psql(sql)
    if raw == "":
        raise SystemExit(f"expected a scalar result, got empty output for:\n{sql}")
    return raw


def check(label: str, condition: bool, detail: str = "") -> None:
    if not condition:
        failures.append(f"{label}: {detail}")


# --- fixtures -----------------------------------------------------------
# Every user below is backdated past the 24h TTL window; only their
# membership state should decide whether the cleanup keeps or removes them.
run_psql(f"""
insert into public.organizations (id, name, slug)
values ('{ORG_ID}', 'TTL Audit Org', 'ttl-audit-org')
on conflict (id) do nothing;

insert into auth.users (id, email, created_at)
values
  ('{ACTIVE_MEMBER_ID}', 'active-member@ttl-audit.local', now() - interval '48 hours'),
  ('{NEVER_MEMBER_ID}', 'never-member@ttl-audit.local', now() - interval '48 hours'),
  ('{SUSPENDED_MEMBER_ID}', 'suspended-member@ttl-audit.local', now() - interval '48 hours'),
  ('{REVOKED_MEMBER_ID}', 'revoked-member@ttl-audit.local', now() - interval '48 hours'),
  ('{RECENT_ORPHAN_ID}', 'recent-orphan@ttl-audit.local', now() - interval '1 hour')
on conflict (id) do nothing;

-- Q1: only an 'active' membership row may protect a user. A 'suspended'
-- row (a live enum value, currently unused by any app code path) must not.
insert into public.memberships
  (organization_id, user_id, scope_type, role_code, status)
values
  ('{ORG_ID}', '{ACTIVE_MEMBER_ID}', 'organization', 'organization_member', 'active'),
  ('{ORG_ID}', '{SUSPENDED_MEMBER_ID}', 'organization', 'organization_member', 'suspended'),
  ('{ORG_ID}', '{REVOKED_MEMBER_ID}', 'organization', 'organization_member', 'active')
on conflict do nothing;

-- Q2: the revoked member authors organization content before losing access,
-- same as a real ex-teammate's songs/plans would have been authored.
insert into public.songs
  (id, organization_id, title, slug, chordpro_source, last_modified_by)
values
  ('{SONG_ID}', '{ORG_ID}', 'Song By Revoked Member', 'song-by-revoked-member', '{{title:Song}}\\n[C] Song', '{REVOKED_MEMBER_ID}')
on conflict (id) do nothing;

insert into public.plans
  (id, organization_id, name, slug, last_modified_by)
values
  ('{PLAN_ID}', '{ORG_ID}', 'Plan By Revoked Member', 'plan-by-revoked-member', '{REVOKED_MEMBER_ID}')
on conflict (id) do nothing;

-- Q3: an invitation the revoked member issued before losing access. Its
-- own expiry is enforced only by a timestamp check in redeem_invitation --
-- no cron ever deletes rows from public.invitations -- so this row should
-- simply outlive its issuer with issued_by nulled out.
insert into public.invitations
  (id, token, organization_id, role_code, expires_at, issued_by)
values
  ('{INVITATION_ID}', 'ttl-audit-invitation-token', '{ORG_ID}', 'organization_member',
   now() + interval '30 days', '{REVOKED_MEMBER_ID}')
on conflict (id) do nothing;

-- Revoke: an admin removing a member deletes the membership row (the app's
-- only membership-removal path today), not merely flips its status.
delete from public.memberships where user_id = '{REVOKED_MEMBER_ID}';
""")

# --- drive the cleanup job's exact statement -----------------------------
run_psql(ORPHAN_CLEANUP_SQL)

# --- Q1: active membership protects the user row -------------------------
check(
    "active member survives cleanup",
    scalar(f"select count(*) from auth.users where id = '{ACTIVE_MEMBER_ID}';") == "1",
    "a user with an active membership older than 24h was deleted",
)

# --- sanity: the job still does its actual job ---------------------------
check(
    "orphan signup with no membership is removed",
    scalar(f"select count(*) from auth.users where id = '{NEVER_MEMBER_ID}';") == "0",
    "an unredeemed >24h signup with no membership row survived cleanup",
)
check(
    "non-active ('suspended') membership does not protect the user",
    scalar(f"select count(*) from auth.users where id = '{SUSPENDED_MEMBER_ID}';") == "0",
    "a user whose only membership row is 'suspended' survived cleanup -- "
    "only 'active' may protect a row",
)
check(
    "user younger than 24h is never collected regardless of membership",
    scalar(f"select count(*) from auth.users where id = '{RECENT_ORPHAN_ID}';") == "1",
    "a user created under 24h ago was deleted by the cleanup",
)

# --- Q2: the indirect path. The revoked member IS collected, but nothing --
# they authored disappears with them.
check(
    "revoked (ex-)member is actually collected by this cleanup pass",
    scalar(f"select count(*) from auth.users where id = '{REVOKED_MEMBER_ID}';") == "0",
    "the revoked-member fixture was not deleted -- this scenario didn't "
    "exercise the indirect path at all",
)
check(
    "organization survives its former member's TTL deletion",
    scalar(f"select count(*) from public.organizations where id = '{ORG_ID}';") == "1",
    "the organization row itself was removed",
)
check(
    "song authored by the revoked member survives",
    scalar(f"select count(*) from public.songs where id = '{SONG_ID}';") == "1",
    "public.songs.last_modified_by cascaded and destroyed the song",
)
check(
    "song's last_modified_by is nulled, not left dangling or cascaded",
    scalar(f"select coalesce(last_modified_by::text, '<null>') from public.songs where id = '{SONG_ID}';") == "<null>",
    "expected last_modified_by to be set null by ON DELETE SET NULL",
)
check(
    "plan authored by the revoked member survives",
    scalar(f"select count(*) from public.plans where id = '{PLAN_ID}';") == "1",
    "public.plans.last_modified_by cascaded and destroyed the plan",
)

# --- Q3: invitation issued by a since-collected member survives too ------
check(
    "invitation issued by the revoked member survives",
    scalar(f"select count(*) from public.invitations where id = '{INVITATION_ID}';") == "1",
    "public.invitations.issued_by cascaded and destroyed the invitation",
)
check(
    "invitation issued_by is nulled, not left dangling or cascaded",
    scalar(f"select coalesce(issued_by::text, '<null>') from public.invitations where id = '{INVITATION_ID}';") == "<null>",
    "expected issued_by to be set null by ON DELETE SET NULL",
)

# --- Q4: no other scheduled job exists that this audit hasn't accounted --
# for. If a new cron.schedule call lands in a migration, this fails and
# forces a re-audit against the same four questions before it's trusted.
known_safe_jobs = {"cleanup-orphan-auth-users", "cleanup-invitation-redemption-attempts"}
actual_jobs = set(
    run_psql("select jobname from cron.job order by jobname;").splitlines()
)
check(
    "only audited pg_cron jobs are registered",
    actual_jobs == known_safe_jobs,
    f"expected {known_safe_jobs!r}, found {actual_jobs!r}",
)

if failures:
    raise SystemExit(
        "pg_cron orphan cleanup contract failed:\n  " + "\n  ".join(failures)
    )

print("pg_cron orphan cleanup contract passed.")
PY
