delete from public.memberships as membership
using (
  select id
  from (
    select
      id,
      row_number() over (
        partition by organization_id, user_id, role_code
        order by created_at, id
      ) as duplicate_rank
    from public.memberships
    where group_id is null
      and scope_type = 'organization'
  ) as ranked_memberships
  where duplicate_rank > 1
) as duplicates
where membership.id = duplicates.id;

drop index if exists public.memberships_organization_scope_unique_idx;

create unique index memberships_organization_scope_unique_idx
on public.memberships (organization_id, user_id, role_code)
where group_id is null and scope_type = 'organization';
