-- Single-call alternative to calling has_capability once per capability.
-- Returns the array of capability codes granted to the caller for the given
-- organization (and optional group scope), resolved in one round-trip.
create or replace function public.get_my_capabilities(
  target_organization_id uuid,
  target_group_id         uuid default null
)
returns text[]
language plpgsql
stable
as $$
declare
  matched_role public.role_code;
begin
  select membership.role_code
  into matched_role
  from public.memberships as membership
  where membership.user_id          = auth.uid()
    and membership.organization_id  = target_organization_id
    and membership.status           = 'active'
    and (
      membership.scope_type = 'organization'
      or (target_group_id is not null and membership.group_id = target_group_id)
    )
  order by case membership.role_code
    when 'organization_admin'    then 1
    when 'group_admin'           then 2
    when 'organization_member'   then 3
    when 'group_member'          then 4
    when 'organization_read_only' then 5
    when 'group_read_only'       then 6
    else 7
  end
  limit 1;

  if matched_role is null then
    return '{}';
  end if;

  return array(
    select capability
    from (values
      ('canViewSongs',
        matched_role in (
          'organization_admin', 'organization_member', 'organization_read_only',
          'group_admin', 'group_member', 'group_read_only'
        )),
      ('canEditSongs',
        matched_role in (
          'organization_admin', 'organization_member',
          'group_admin', 'group_member'
        )),
      ('canManageOrganizationMembers',
        matched_role = 'organization_admin'),
      ('canManageGroupMembers',
        matched_role in ('organization_admin', 'group_admin')),
      ('canEditSessions',
        matched_role in (
          'organization_admin', 'organization_member',
          'group_admin', 'group_member'
        )),
      ('canManagePlans',
        matched_role in (
          'organization_admin', 'organization_member',
          'group_admin', 'group_member'
        ))
    ) as t(capability, granted)
    where granted
  );
end;
$$;
