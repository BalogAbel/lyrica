-- SEC-1: redemption reports business outcomes as a returned status instead of
-- raising. Raising aborts the transaction, which would roll back the audit row
-- written alongside it; returning lets every attempt persist.

-- Builds the jsonb envelope redeem_invitation returns. Factored out so the
-- two callers that need it -- the audit-writing path below and the
-- rate-limit cap in redeem_invitation, which must return the identical shape
-- without writing a row -- cannot drift apart.
create or replace function public.invitation_redemption_envelope(
  p_outcome public.invitation_redemption_outcome,
  p_organization_id uuid
)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_build_object(
    'status', p_outcome::text,
    'organization_id',
    case when p_outcome = 'redeemed' then p_organization_id else null end
  );
$$;

-- Not granted to any client role: it is a pure formatting helper only ever
-- reached through the security-definer redemption function below.
revoke all on function public.invitation_redemption_envelope(
  public.invitation_redemption_outcome, uuid
) from public, anon, authenticated;

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
  -- already_redeemed, expired and already_member are terminal for a given token
  -- and are deliberately excluded from the rate-limit count, so that a real user
  -- retrying a stale link cannot lock themselves out. Without deduplication that
  -- exclusion is also an unbounded write: a caller holding one spent or expired
  -- token could loop the RPC and grow this table indefinitely, with the 90-day
  -- retention bounding only the age of the rows and not their number.
  --
  -- The key includes the token digest, so a genuinely different invitation with
  -- the same outcome is still audited, and the first event in each window always
  -- is. not_found and email_mismatch are NOT deduplicated: the rate limit counts
  -- them, and collapsing them would defeat it.
  --
  -- Concurrency: redeem_invitation takes a caller-keyed advisory lock before any
  -- of this, and every key here is scoped to that same caller, so the
  -- check-then-insert cannot interleave with itself.
  if p_outcome in ('already_redeemed', 'expired', 'already_member') then
    if exists (
      select 1
      from public.invitation_redemption_attempts a
      where a.actor_user_id = p_actor
        and a.token_sha256 = p_token_sha256
        and a.outcome = p_outcome
        and a.created_at > now() - interval '15 minutes'
    ) then
      return public.invitation_redemption_envelope(p_outcome, p_organization_id);
    end if;
  end if;

  insert into public.invitation_redemption_attempts (
    invitation_id, token_sha256, actor_user_id, outcome, organization_id
  ) values (
    p_invitation_id, p_token_sha256, p_actor, p_outcome, p_organization_id
  );

  return public.invitation_redemption_envelope(p_outcome, p_organization_id);
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
  v_caller_email text;
  v_suspicious_attempts integer;
begin
  -- The only remaining raise: with no caller there is nothing to audit or to
  -- key a rate-limit bucket to, and execute is granted to authenticated only.
  if v_caller is null then
    raise exception using
      errcode = '42501',
      message = 'invitation_redeem_requires_auth';
  end if;

  -- Serialize this caller's concurrent redemptions. Two races need it:
  -- the rate-limit count below is read-then-decide, and the already_member
  -- check further down is read-then-insert while the invitation row lock only
  -- covers a single token. Without this, two different invitations to the same
  -- organization can both pass the membership check; with different role_code
  -- values they do not even collide on
  -- memberships_organization_scope_unique_idx, leaving one user holding two
  -- active organization memberships. The lock is per caller, so unrelated
  -- callers never contend, and it is released at transaction end.
  perform pg_advisory_xact_lock(hashtext(v_caller::text)::bigint);

  -- Only outcomes that look like token probing count. Benign retries (expired,
  -- already redeemed, already a member) are excluded so a real user retrying a
  -- stale link cannot lock themselves out. The window expires on its own.
  select count(*) into v_suspicious_attempts
  from public.invitation_redemption_attempts a
  where a.actor_user_id = v_caller
    and a.outcome in ('not_found', 'email_mismatch')
    and a.created_at > now() - interval '15 minutes';

  if v_suspicious_attempts >= 10 then
    -- The limit throttles redemption, not the audit write it causes. rate_limited
    -- is deliberately excluded from v_suspicious_attempts above, so without this
    -- guard an already-limited caller looping on the RPC would insert one audit
    -- row per call forever -- the rate limit would bound membership attempts but
    -- not the table growth they trigger. One marker row per caller per window is
    -- enough to preserve the audit signal ("this caller hit the limit") while
    -- capping the write; the envelope is identical either way so the client
    -- cannot tell which branch ran.
    if exists (
      select 1
      from public.invitation_redemption_attempts a
      where a.actor_user_id = v_caller
        and a.outcome = 'rate_limited'
        and a.created_at > now() - interval '15 minutes'
    ) then
      return public.invitation_redemption_envelope('rate_limited', null);
    end if;

    return public.record_invitation_redemption_attempt(
      null, v_token_sha256, v_caller, 'rate_limited', null
    );
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
