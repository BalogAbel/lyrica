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
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'admin@test.local'),
  ('00000000-0000-0000-0000-000000000002', 'invitee@test.local');

insert into public.organizations (id, name, slug)
values ('00000000-0000-0000-0000-0000000000aa', 'Test Org', 'test-org');

insert into public.memberships (
  organization_id, user_id, scope_type, role_code, status
) values (
  '00000000-0000-0000-0000-0000000000aa',
  '00000000-0000-0000-0000-000000000001',
  'organization', 'organization_admin', 'active'
);

-- Service-role caller (auth.uid() = null) can create an invite
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

-- Redeem path: simulate auth.uid via local config
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000002"}';

do $$
declare
  v_token text;
  v_org uuid;
begin
  select token into v_token from public.invitations limit 1;
  v_org := public.redeem_invitation(v_token);
  if v_org is null then
    raise exception 'redeem returned null';
  end if;
end$$;

-- Second redeem must fail with invitation_already_redeemed
do $$
declare
  v_token text;
begin
  select token into v_token from public.invitations limit 1;
  begin
    perform public.redeem_invitation(v_token);
    raise exception 'expected already_redeemed';
  exception when others then
    if sqlerrm not like '%invitation_already_redeemed%' then
      raise;
    end if;
  end;
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
  id, organization_id, title, chordpro_source, last_modified_by
) values (
  '00000000-0000-0000-0000-0000000000bb',
  '00000000-0000-0000-0000-0000000000aa',
  'Sample Song',
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

rollback;
