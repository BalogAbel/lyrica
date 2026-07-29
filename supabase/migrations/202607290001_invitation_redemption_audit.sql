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
