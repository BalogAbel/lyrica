alter table public.memberships
  drop constraint if exists memberships_role_scope_consistency;

alter table public.memberships
  add constraint memberships_role_scope_consistency check (
    (scope_type = 'organization'
      and role_code in (
        'organization_admin',
        'organization_member',
        'organization_read_only'
      ))
    or (scope_type = 'group'
      and role_code in (
        'group_admin',
        'group_member',
        'group_read_only'
      ))
  );

create or replace function public.has_capability(
  target_organization_id uuid,
  capability text,
  target_group_id uuid default null
)
returns boolean
language plpgsql
stable
as $$
declare
  matched_role public.role_code;
begin
  select membership.role_code
  into matched_role
  from public.memberships as membership
  where membership.user_id = auth.uid()
    and membership.organization_id = target_organization_id
    and membership.status = 'active'
    and (
      membership.scope_type = 'organization'
      or (target_group_id is not null and membership.group_id = target_group_id)
    )
  order by case membership.role_code
    when 'organization_admin' then 1
    when 'group_admin' then 2
    when 'organization_member' then 3
    when 'group_member' then 4
    when 'organization_read_only' then 5
    when 'group_read_only' then 6
    else 7
  end
  limit 1;

  if matched_role is null then
    return false;
  end if;

  return case capability
    when 'canViewSongs' then matched_role in (
      'organization_admin',
      'organization_member',
      'organization_read_only',
      'group_admin',
      'group_member',
      'group_read_only'
    )
    when 'canEditSongs' then matched_role in (
      'organization_admin',
      'organization_member',
      'group_admin',
      'group_member'
    )
    when 'canManageOrganizationMembers' then matched_role = 'organization_admin'
    when 'canManageGroupMembers' then matched_role in (
      'organization_admin',
      'group_admin'
    )
    when 'canEditSessions' then matched_role in (
      'organization_admin',
      'organization_member',
      'group_admin',
      'group_member'
    )
    when 'canManagePlans' then matched_role in (
      'organization_admin',
      'organization_member',
      'group_admin',
      'group_member'
    )
    else false
  end;
end;
$$;

alter table public.invitations
  drop constraint if exists invitations_role_code_check;

alter table public.invitations
  add constraint invitations_role_code_check check (
    role_code in (
      'organization_admin',
      'organization_member',
      'organization_read_only'
    )
  );
