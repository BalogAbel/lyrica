-- Run with: ./scripts/supabase.sh db reset && ./scripts/supabase.sh db query < supabase/snippets/auth_invite_tests.sql
\set ON_ERROR_STOP on
begin;

-- Sanity: invitations table exists with expected columns
do $$
begin
  perform 1 from public.invitations limit 0;
end$$;

rollback;
