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
