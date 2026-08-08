-- SEC-2 (defense-in-depth, not a live vulnerability): create_invitation's
-- null-caller branch previously trusted `auth.uid() is null` alone as proof
-- the caller was service_role. That happens to be true today only because
-- the function's execute grant is scoped to `authenticated, service_role`
-- (see 202605160007_auth_boundary_hardening.sql) and real PostgREST always
-- sets request.jwt.claim.sub whenever it sets an authenticated role -- so in
-- production, authenticated never has a null auth.uid(). But that's an
-- implicit assumption resting on grant scope and PostgREST's calling
-- convention, not something the function itself checks.
--
-- This migration makes the assumption an explicit runtime check: the
-- null-caller branch now asserts current_setting('role', true) really is
-- 'service_role' before skipping the admin-membership check. Verified
-- empirically against local Postgres that current_setting('role', true)
-- reflects the session's SET ROLE value (i.e. the role PostgREST actually
-- authenticated as) even inside a SECURITY DEFINER function body, where
-- current_user/session_user are not useful for this check -- current_user
-- is remapped to the function owner for the duration of the call, and
-- session_user reflects the original connection role (PostgREST's
-- `authenticator`), not the per-request SET ROLE.
--
-- Real-world caller semantics are unchanged: authenticated callers still
-- need org-admin membership, and service_role still bypasses that check.
-- No ADR: this only tightens an implicit assumption into an explicit check,
-- it does not change who is authorized to do what.
create or replace function public.create_invitation(
  p_organization_id uuid,
  p_role public.role_code,
  p_email text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_token text;
  v_is_admin boolean;
begin
  if v_caller is not null then
    select exists (
      select 1
      from public.memberships m
      where m.user_id = v_caller
        and m.organization_id = p_organization_id
        and m.scope_type = 'organization'
        and m.role_code = 'organization_admin'
        and m.status = 'active'
    ) into v_is_admin;

    if not v_is_admin then
      raise exception using
        errcode = '42501',
        message = 'invitation_create_not_authorized';
    end if;
  else
    if current_setting('role', true) is distinct from 'service_role' then
      raise exception using
        errcode = '42501',
        message = 'invitation_create_not_authorized';
    end if;
  end if;

  v_token := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');

  insert into public.invitations (
    token, email, organization_id, role_code,
    expires_at, issued_by
  ) values (
    v_token, p_email, p_organization_id, p_role,
    now() + interval '30 days', v_caller
  );

  return v_token;
end;
$$;
