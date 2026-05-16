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

create or replace function public.redeem_invitation(
  p_token text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_inv public.invitations%rowtype;
begin
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
    raise exception using errcode = 'P0001', message = 'invitation_not_found';
  end if;

  if v_inv.redeemed_at is not null then
    raise exception using errcode = 'P0001', message = 'invitation_already_redeemed';
  end if;

  if v_inv.expires_at <= now() then
    raise exception using errcode = 'P0001', message = 'invitation_expired';
  end if;

  if exists (
    select 1
    from public.memberships m
    where m.user_id = v_caller
      and m.organization_id = v_inv.organization_id
      and m.scope_type = 'organization'
      and m.status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'already_member';
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

  return v_inv.organization_id;
end;
$$;
