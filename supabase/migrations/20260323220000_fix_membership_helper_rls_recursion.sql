create or replace function public.current_organization_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select distinct membership.organization_id
  from public.memberships as membership
  where membership.user_id = auth.uid()
    and membership.status = 'active';
$$;

create or replace function public.has_capability(
  target_organization_id uuid,
  capability text,
  target_group_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
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
    else 5
  end
  limit 1;

  if matched_role is null then
    return false;
  end if;

  return case capability
    when 'canViewSongs' then matched_role in ('organization_admin', 'organization_member', 'group_admin', 'group_member', 'group_read_only')
    when 'canEditSongs' then matched_role in ('organization_admin', 'organization_member', 'group_admin', 'group_member')
    when 'canManageOrganizationMembers' then matched_role = 'organization_admin'
    when 'canManageGroupMembers' then matched_role in ('organization_admin', 'group_admin')
    when 'canEditSessions' then matched_role in ('organization_admin', 'organization_member', 'group_admin', 'group_member')
    when 'canManagePlans' then matched_role in ('organization_admin', 'organization_member', 'group_admin', 'group_member')
    else false
  end;
end;
$$;
