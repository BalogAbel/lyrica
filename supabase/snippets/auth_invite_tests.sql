-- Auth invite integration tests
-- Run via: docker exec -i supabase_db_lyron psql -U postgres -d postgres -f /dev/stdin < supabase/snippets/auth_invite_tests.sql
begin;

-- Task 1: Sanity — invitations table exists
do $$
begin
  perform 1 from public.invitations limit 0;
end$$;

-- Task 2: create_invitation + redeem_invitation

-- Seed users and org
-- email_confirmed_at matters: an email-bound invitation is redeemable only by an
-- account whose address is confirmed (ADR-025), so an unconfirmed seed user would
-- now get email_mismatch rather than redeemed.
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-000000000001', 'admin@test.local', now()),
  ('00000000-0000-0000-0000-000000000002', 'invitee@test.local', now());

insert into public.organizations (id, name, slug)
values ('00000000-0000-0000-0000-0000000000aa', 'Test Org', 'test-org');

insert into public.memberships (
  organization_id, user_id, scope_type, role_code, status
) values (
  '00000000-0000-0000-0000-0000000000aa',
  '00000000-0000-0000-0000-000000000001',
  'organization', 'organization_admin', 'active'
);

-- Service-role caller (auth.uid() = null) can create an invite.
-- SEC-2 (create-invitation-service-role-gate) requires the session role to
-- actually be service_role when auth.uid() is null; this raw psql session
-- otherwise runs as plain `postgres`, which the gate now rejects.
set local role service_role;

do $$
declare
  v_token text;
begin
  v_token := public.create_invitation(
    '00000000-0000-0000-0000-0000000000aa',
    'organization_member',
    'invitee@test.local'
  );
  if v_token is null or length(v_token) < 16 then
    raise exception 'expected token, got %', v_token;
  end if;
end$$;

-- Extra invitations for the expired and email-bound cases are issued HERE, while
-- auth.uid() is still null (service-role path). Once request.jwt.claims below
-- names the invitee, create_invitation would reject them as a non-admin.
create temp table snippet_tokens (label text primary key, token text not null);

do $$
declare
  v_token text;
begin
  v_token := public.create_invitation(
    '00000000-0000-0000-0000-0000000000aa',
    'organization_member'::public.role_code,
    null
  );
  update public.invitations set expires_at = now() - interval '1 day'
  where token = v_token;
  insert into snippet_tokens values ('expired', v_token);

  v_token := public.create_invitation(
    '00000000-0000-0000-0000-0000000000aa',
    'organization_member'::public.role_code,
    'someone.else@example.test'
  );
  insert into snippet_tokens values ('email_mismatch', v_token);
end$$;

-- Redeem path: simulate auth.uid via local config
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000002"}';

-- redeem_invitation returns a jsonb status envelope, {"status", "organization_id"},
-- and no longer raises for business outcomes. See ADR-025: a raised exception
-- aborts the transaction and would roll back the audit row written with it.
do $$
declare
  v_token text;
  v_result jsonb;
begin
  -- Selected by its invited address rather than `limit 1`: several
  -- invitations exist by now, and an unordered limit picked an arbitrary one.
  select token into v_token
  from public.invitations
  where email = 'invitee@test.local'
    and organization_id = '00000000-0000-0000-0000-0000000000aa';
  v_result := public.redeem_invitation(v_token);
  if v_result ->> 'status' <> 'redeemed' then
    raise exception 'expected status redeemed, got %', v_result;
  end if;
  if v_result ->> 'organization_id' is null then
    raise exception 'redeemed status must carry an organization id, got %', v_result;
  end if;
end$$;

-- Second redeem returns already_redeemed as a status rather than raising.
do $$
declare
  v_token text;
  v_result jsonb;
begin
  -- Selected by its invited address rather than `limit 1`: several
  -- invitations exist by now, and an unordered limit picked an arbitrary one.
  select token into v_token
  from public.invitations
  where email = 'invitee@test.local'
    and organization_id = '00000000-0000-0000-0000-0000000000aa';
  v_result := public.redeem_invitation(v_token);
  if v_result ->> 'status' <> 'already_redeemed' then
    raise exception 'expected status already_redeemed, got %', v_result;
  end if;
  if v_result ->> 'organization_id' is not null then
    raise exception 'a non-redeemed status must not carry an organization id, got %', v_result;
  end if;
end$$;

-- An unknown token is not_found, again as a status.
do $$
declare
  v_result jsonb;
begin
  v_result := public.redeem_invitation('definitely-not-a-real-token');
  if v_result ->> 'status' <> 'not_found' then
    raise exception 'expected status not_found, got %', v_result;
  end if;
end$$;

-- An expired invitation reports expired.
do $$
declare
  v_result jsonb;
begin
  select public.redeem_invitation(token) into v_result
  from snippet_tokens where label = 'expired';
  if v_result ->> 'status' <> 'expired' then
    raise exception 'expected status expired, got %', v_result;
  end if;
end$$;

-- An email-bound invitation refuses a caller whose account email differs.
do $$
declare
  v_result jsonb;
begin
  select public.redeem_invitation(token) into v_result
  from snippet_tokens where label = 'email_mismatch';
  if v_result ->> 'status' <> 'email_mismatch' then
    raise exception 'expected status email_mismatch, got %', v_result;
  end if;
end$$;

-- Task 3 RLS: A non-admin authenticated user cannot select an invitation they did not issue
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099"}';
set local role = 'authenticated';

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.invitations;
  if v_count <> 0 then
    raise exception 'expected 0 visible invitations, got %', v_count;
  end if;
end$$;

reset role;

-- Task 4: Deleting an author preserves their songs but nulls out last_modified_by
-- Re-seed invitee user (may have been deleted in redeem test — they're still in the txn here)
insert into public.songs (
  id, organization_id, title, slug, chordpro_source, last_modified_by
) values (
  '00000000-0000-0000-0000-0000000000bb',
  '00000000-0000-0000-0000-0000000000aa',
  'Sample Song',
  'sample-song',
  '{title: Sample}',
  '00000000-0000-0000-0000-000000000002'
);

delete from auth.users where id = '00000000-0000-0000-0000-000000000002';

do $$
declare
  v_modified_by uuid;
begin
  select last_modified_by into v_modified_by
  from public.songs
  where id = '00000000-0000-0000-0000-0000000000bb';
  if v_modified_by is not null then
    raise exception 'expected last_modified_by null after author delete, got %', v_modified_by;
  end if;
end$$;

-- Task 5: delete_account
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000077', 'deletable@test.local');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000077"}';

do $$ begin perform public.delete_account(); end$$;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from auth.users where id = '00000000-0000-0000-0000-000000000077';
  if v_count <> 0 then
    raise exception 'expected 0, got %', v_count;
  end if;
end$$;

-- ============================================================
-- Task 6: create_invitation rejects non-admins (authenticated, not admin)
-- ============================================================
-- New user with no membership in the org
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000003', 'nonadmin@test.local');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000003"}';

do $$
begin
  begin
    perform public.create_invitation(
      '00000000-0000-0000-0000-0000000000aa',
      'organization_member',
      null
    );
    raise exception 'expected invitation_create_not_authorized';
  exception when insufficient_privilege then
    -- errcode 42501 maps to insufficient_privilege — expected
    null;
  end;
end$$;

-- ============================================================
-- Task 7: create_invitation succeeds for an authenticated admin
-- ============================================================
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001"}';

do $$
declare
  v_token text;
begin
  v_token := public.create_invitation(
    '00000000-0000-0000-0000-0000000000aa',
    'organization_member',
    'newmember@test.local'
  );
  if v_token is null or length(v_token) < 16 then
    raise exception 'admin create_invitation returned bad token: %', v_token;
  end if;
end$$;

-- ============================================================
-- Task 8: redeem_invitation raises invitation_expired for expired tokens
-- ============================================================
-- Insert an already-expired invitation directly (service-role context, no uid set)
set local request.jwt.claims = '{}';

insert into public.invitations (
  token, email, organization_id, role_code, expires_at, issued_by
) values (
  'expired-test-token-0000000000000001',
  null,
  '00000000-0000-0000-0000-0000000000aa',
  'organization_member',
  now() - interval '1 day',
  null
);

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000003"}';

do $$
begin
  begin
    perform public.redeem_invitation('expired-test-token-0000000000000001');
    raise exception 'expected invitation_expired';
  exception when others then
    if sqlerrm not like '%invitation_expired%' then
      raise;
    end if;
  end;
end$$;

-- ============================================================
-- Task 9: redeem_invitation raises already_member when caller already has active membership
-- ============================================================
-- admin user (00000000-0000-0000-0000-000000000001) already has an active membership
-- Create a fresh unredeemed invitation for that org
set local request.jwt.claims = '{}';

insert into public.invitations (
  token, email, organization_id, role_code, expires_at, issued_by
) values (
  'already-member-test-token-000000001',
  null,
  '00000000-0000-0000-0000-0000000000aa',
  'organization_member',
  now() + interval '30 days',
  null
);

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001"}';

do $$
begin
  begin
    perform public.redeem_invitation('already-member-test-token-000000001');
    raise exception 'expected already_member';
  exception when others then
    if sqlerrm not like '%already_member%' then
      raise;
    end if;
  end;
end$$;

-- ============================================================
-- Task 10: delete_account cascades memberships
-- ============================================================
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000088', 'cascade@test.local');

insert into public.memberships (
  organization_id, user_id, scope_type, role_code, status
) values (
  '00000000-0000-0000-0000-0000000000aa',
  '00000000-0000-0000-0000-000000000088',
  'organization', 'organization_member', 'active'
);

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000088"}';

do $$ begin perform public.delete_account(); end$$;

do $$
declare
  v_user_count  integer;
  v_memb_count  integer;
begin
  select count(*) into v_user_count from auth.users
    where id = '00000000-0000-0000-0000-000000000088';
  select count(*) into v_memb_count from public.memberships
    where user_id = '00000000-0000-0000-0000-000000000088';

  if v_user_count <> 0 then
    raise exception 'delete_account: user row still exists';
  end if;
  if v_memb_count <> 0 then
    raise exception 'delete_account: membership not cascaded, got % rows', v_memb_count;
  end if;
end$$;

-- ============================================================
-- Task 11: pg_cron orphan-cleanup simulation
--   orphan >24h  → deleted
--   orphan <24h  → preserved
--   user with active membership (any age) → preserved
-- ============================================================
set local request.jwt.claims = '{}';

insert into auth.users (id, email, created_at) values
  -- orphan older than 24h: should be deleted
  ('00000000-0000-0000-0000-000000000091', 'orphan-old@test.local',
   now() - interval '25 hours'),
  -- orphan younger than 24h: should be preserved
  ('00000000-0000-0000-0000-000000000092', 'orphan-young@test.local',
   now() - interval '1 hour'),
  -- has active membership (old): should be preserved
  ('00000000-0000-0000-0000-000000000093', 'member-old@test.local',
   now() - interval '48 hours');

insert into public.memberships (
  organization_id, user_id, scope_type, role_code, status
) values (
  '00000000-0000-0000-0000-0000000000aa',
  '00000000-0000-0000-0000-000000000093',
  'organization', 'organization_member', 'active'
);

-- Simulate the cron body inline
delete from auth.users u
where u.created_at < now() - interval '24 hours'
  and not exists (
    select 1 from public.memberships m
    where m.user_id = u.id and m.status = 'active'
  );

do $$
declare
  v_old_exists   boolean;
  v_young_exists boolean;
  v_member_exists boolean;
begin
  select exists(select 1 from auth.users where id = '00000000-0000-0000-0000-000000000091')
    into v_old_exists;
  select exists(select 1 from auth.users where id = '00000000-0000-0000-0000-000000000092')
    into v_young_exists;
  select exists(select 1 from auth.users where id = '00000000-0000-0000-0000-000000000093')
    into v_member_exists;

  if v_old_exists then
    raise exception 'cron: orphan >24h should have been deleted (00000000-0000-0000-0000-000000000091)';
  end if;
  if not v_young_exists then
    raise exception 'cron: orphan <24h should be preserved (00000000-0000-0000-0000-000000000092)';
  end if;
  if not v_member_exists then
    raise exception 'cron: user with active membership should be preserved (00000000-0000-0000-0000-000000000093)';
  end if;
end$$;

-- ============================================================
-- Task 12: auth boundary hardening
--   anon cannot execute invite/security-definer RPC entrypoints
--   anon cannot select domain tables before sign-in
--   authenticated keeps the app-facing RPC entrypoints it needs
-- ============================================================
do $$
declare
  v_anon_can_create_invitation boolean;
  v_anon_can_redeem_invitation boolean;
  v_authenticated_can_redeem_invitation boolean;
begin
  select has_function_privilege(
    'anon',
    'public.create_invitation(uuid, public.role_code, text)',
    'execute'
  ) into v_anon_can_create_invitation;

  select has_function_privilege(
    'anon',
    'public.redeem_invitation(text)',
    'execute'
  ) into v_anon_can_redeem_invitation;

  select has_function_privilege(
    'authenticated',
    'public.redeem_invitation(text)',
    'execute'
  ) into v_authenticated_can_redeem_invitation;

  if v_anon_can_create_invitation then
    raise exception 'anon must not execute create_invitation';
  end if;
  if v_anon_can_redeem_invitation then
    raise exception 'anon must not execute redeem_invitation';
  end if;
  if not v_authenticated_can_redeem_invitation then
    raise exception 'authenticated must execute redeem_invitation';
  end if;
end$$;

do $$
declare
  v_table text;
  v_anon_can_select boolean;
begin
  foreach v_table in array array[
    'organizations',
    'groups',
    'memberships',
    'songs',
    'plans',
    'sessions',
    'session_items',
    'attachments',
    'invitations'
  ] loop
    select has_table_privilege(
      'anon',
      format('public.%I', v_table),
      'select'
    ) into v_anon_can_select;

    if v_anon_can_select then
      raise exception 'anon must not select public.%', v_table;
    end if;
  end loop;
end$$;

do $$
declare
  v_exposed_functions text[];
begin
  select coalesce(
    array_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' order by p.proname),
    array[]::text[]
  )
  into v_exposed_functions
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and has_function_privilege('anon', p.oid, 'execute');

  if array_length(v_exposed_functions, 1) is not null then
    raise exception 'anon must not execute public security-definer functions: %',
      array_to_string(v_exposed_functions, ', ');
  end if;
end$$;

rollback;
