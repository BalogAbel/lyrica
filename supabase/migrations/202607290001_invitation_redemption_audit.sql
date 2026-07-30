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

-- Shaped for the "has this caller already been marked rate limited in the
-- window?" probe. The index above cannot serve it: its predicate excludes
-- rate_limited rows entirely.
create index invitation_redemption_attempts_rate_limited_marker_idx
  on public.invitation_redemption_attempts (actor_user_id, created_at desc)
  where outcome = 'rate_limited';

-- Shaped for the terminal-outcome audit deduplication, which is keyed on the
-- token digest as well as the caller so a genuinely different invitation is
-- still recorded.
--
-- Deliberately NOT a partial index, unlike the two above. PostgreSQL can only
-- use a partial index when it can prove at plan time that the query predicate
-- implies the index predicate. The two above are provable because the function
-- compares outcome against literals; this dedup check compares it against the
-- p_outcome parameter, which a generic plan cannot resolve, so a partial index
-- here is silently unusable and degrades to a sequential scan.
--
-- Its leading actor_user_id column also serves the outcome-agnostic lookup that
-- the auth.users foreign key performs on delete: that scan has no outcome
-- filter at all, so none of the partial indexes can serve it, including for
-- 'redeemed' rows which no partial index covers.
create index invitation_redemption_attempts_actor_token_outcome_idx
  on public.invitation_redemption_attempts
    (actor_user_id, token_sha256, outcome, created_at desc);

-- Shaped for the daily retention delete, which filters on age alone. Every
-- other index here leads with actor_user_id and cannot serve it.
create index invitation_redemption_attempts_created_at_idx
  on public.invitation_redemption_attempts (created_at);

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
