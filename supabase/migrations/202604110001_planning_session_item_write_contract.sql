create or replace function public.reorder_plan_sessions(
  p_organization_id uuid,
  p_plan_id uuid,
  p_base_version bigint,
  p_session_ids uuid[]
)
returns table (
  plan_id uuid,
  organization_id uuid,
  version bigint,
  ordered_session_ids uuid[],
  ordered_session_positions integer[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_plan public.plans%rowtype;
  current_session_ids uuid[];
  temp_position_offset integer;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'plan_version_conflict',
      detail = 'base_version is required for session reorder';
  end if;

  select *
  into existing_plan
  from public.plans as plan
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
    and public.has_capability(
      plan.organization_id,
      'canManagePlans',
      plan.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'plan_not_found',
      detail = 'The target plan does not exist in the requested organization';
  end if;

  if existing_plan.version <> p_base_version then
    raise exception using
      errcode = 'P0001',
      message = 'plan_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        existing_plan.version::text
      );
  end if;

  select array_agg(session.id order by session.position, session.id)
  into current_session_ids
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.plan_id = p_plan_id;

  if coalesce(array_length(current_session_ids, 1), 0) <>
      coalesce(array_length(p_session_ids, 1), 0)
      or coalesce(
        array_length(
          array(
            select distinct requested.session_id
            from unnest(coalesce(p_session_ids, array[]::uuid[])) as requested(session_id)
          ),
          1
        ),
        0
      ) <> coalesce(array_length(p_session_ids, 1), 0)
      or exists (
        select 1
        from unnest(coalesce(p_session_ids, array[]::uuid[])) as requested(session_id)
        where not requested.session_id = any(coalesce(current_session_ids, array[]::uuid[]))
      ) then
    raise exception using
      errcode = 'P0001',
      message = 'session_reorder_blocked_invalid_permutation',
      detail = 'session reorder must include each visible session exactly once';
  end if;

  select coalesce(max(session.position), 0) + coalesce(array_length(p_session_ids, 1), 0) + 1
  into temp_position_offset
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.plan_id = p_plan_id;

  update public.sessions as session
  set position = temp_position_offset + reordered.ordinality
  from unnest(p_session_ids) with ordinality as reordered(session_id, ordinality)
  where session.organization_id = p_organization_id
    and session.plan_id = p_plan_id
    and session.id = reordered.session_id;

  update public.sessions as session
  set position = session.position - temp_position_offset
  where session.organization_id = p_organization_id
    and session.plan_id = p_plan_id;

  update public.plans as plan
  set
    version = plan.version + 1,
    base_version = plan.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id;

  return query
  select
    existing_plan.id,
    p_organization_id,
    existing_plan.version + 1,
    (
      select coalesce(array_agg(session.id order by session.position, session.id), array[]::uuid[])
      from public.sessions as session
      where session.organization_id = p_organization_id
        and session.plan_id = p_plan_id
    ),
    (
      select coalesce(
        array_agg(session.position order by session.position, session.id),
        array[]::integer[]
      )
      from public.sessions as session
      where session.organization_id = p_organization_id
        and session.plan_id = p_plan_id
    );
end;
$$;

create or replace function public.create_song_session_item(
  p_organization_id uuid,
  p_session_id uuid,
  p_session_item_id uuid,
  p_song_id uuid,
  p_base_version bigint,
  p_position integer default null
)
returns table (
  id uuid,
  plan_id uuid,
  session_id uuid,
  organization_id uuid,
  song_id uuid,
  song_title text,
  "position" integer,
  version bigint,
  ordered_session_item_ids uuid[],
  ordered_session_item_positions integer[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_session public.sessions%rowtype;
  visible_song public.songs%rowtype;
  next_position integer;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = 'base_version is required for session-item create';
  end if;

  select *
  into existing_session
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and public.has_capability(
      session.organization_id,
      'canEditSessions',
      session.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_not_found',
      detail = 'The target session does not exist in the requested organization';
  end if;

  if existing_session.version <> p_base_version then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        existing_session.version::text
      );
  end if;

  select *
  into visible_song
  from public.songs as song
  where song.organization_id = p_organization_id
    and song.id = p_song_id
    and public.has_capability(song.organization_id, 'canViewSongs');

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'song_not_visible_blocked',
      detail = 'The requested song is not visible in the active organization';
  end if;

  if exists (
    select 1
    from public.session_items as item
    where item.organization_id = p_organization_id
      and item.session_id = p_session_id
      and item.item_type = 'song'
      and item.song_id = p_song_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'duplicate_song_in_session_blocked',
      detail = 'The same song may appear at most once within one session';
  end if;

  select coalesce(max(item.position), 0) + 1
  into next_position
  from public.session_items as item
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id;

  insert into public.session_items (
    id,
    organization_id,
    session_id,
    song_id,
    item_type,
    position,
    version,
    base_version,
    sync_status,
    last_modified_by
  )
  values (
    p_session_item_id,
    p_organization_id,
    p_session_id,
    p_song_id,
    'song',
    coalesce(p_position, next_position),
    1,
    null,
    'synced',
    auth.uid()
  );

  update public.sessions as session
  set
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id;

  return query
  select
    p_session_item_id,
    existing_session.plan_id,
    p_session_id,
    p_organization_id,
    p_song_id,
    visible_song.title,
    (
      select item.position
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.id = p_session_item_id
    ),
    existing_session.version + 1,
    (
      select coalesce(array_agg(item.id order by item.position, item.id), array[]::uuid[])
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    ),
    (
      select coalesce(
        array_agg(item.position order by item.position, item.id),
        array[]::integer[]
      )
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    );
end;
$$;

create or replace function public.delete_session_item(
  p_organization_id uuid,
  p_session_id uuid,
  p_session_item_id uuid,
  p_base_version bigint
)
returns table (
  id uuid,
  plan_id uuid,
  session_id uuid,
  organization_id uuid,
  version bigint,
  ordered_session_item_ids uuid[],
  ordered_session_item_positions integer[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_session public.sessions%rowtype;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = 'base_version is required for session-item delete';
  end if;

  select *
  into existing_session
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and public.has_capability(
      session.organization_id,
      'canEditSessions',
      session.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_not_found',
      detail = 'The target session does not exist in the requested organization';
  end if;

  if existing_session.version <> p_base_version then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        existing_session.version::text
      );
  end if;

  delete from public.session_items as item
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id
    and item.id = p_session_item_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_item_not_found',
      detail = 'The target session item does not exist in the requested session';
  end if;

  update public.sessions as session
  set
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id;

  return query
  select
    p_session_item_id,
    existing_session.plan_id,
    p_session_id,
    p_organization_id,
    existing_session.version + 1,
    (
      select coalesce(array_agg(item.id order by item.position, item.id), array[]::uuid[])
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    ),
    (
      select coalesce(
        array_agg(item.position order by item.position, item.id),
        array[]::integer[]
      )
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    );
end;
$$;

create or replace function public.reorder_session_items(
  p_organization_id uuid,
  p_session_id uuid,
  p_base_version bigint,
  p_session_item_ids uuid[]
)
returns table (
  plan_id uuid,
  session_id uuid,
  organization_id uuid,
  version bigint,
  ordered_session_item_ids uuid[],
  ordered_session_item_positions integer[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_session public.sessions%rowtype;
  current_item_ids uuid[];
  temp_position_offset integer;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = 'base_version is required for session-item reorder';
  end if;

  select *
  into existing_session
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and public.has_capability(
      session.organization_id,
      'canEditSessions',
      session.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_not_found',
      detail = 'The target session does not exist in the requested organization';
  end if;

  if existing_session.version <> p_base_version then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        existing_session.version::text
      );
  end if;

  select array_agg(item.id order by item.position, item.id)
  into current_item_ids
  from public.session_items as item
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id;

  if coalesce(array_length(current_item_ids, 1), 0) <>
      coalesce(array_length(p_session_item_ids, 1), 0)
      or coalesce(
        array_length(
          array(
            select distinct requested.item_id
            from unnest(coalesce(p_session_item_ids, array[]::uuid[])) as requested(item_id)
          ),
          1
        ),
        0
      ) <> coalesce(array_length(p_session_item_ids, 1), 0)
      or exists (
        select 1
        from unnest(coalesce(p_session_item_ids, array[]::uuid[])) as requested(item_id)
        where not requested.item_id = any(coalesce(current_item_ids, array[]::uuid[]))
      ) then
    raise exception using
      errcode = 'P0001',
      message = 'session_item_reorder_blocked_invalid_permutation',
      detail = 'session-item reorder must include each visible item exactly once';
  end if;

  select coalesce(max(item.position), 0) + coalesce(array_length(p_session_item_ids, 1), 0) + 1
  into temp_position_offset
  from public.session_items as item
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id;

  update public.session_items as item
  set position = temp_position_offset + reordered.ordinality
  from unnest(p_session_item_ids) with ordinality as reordered(item_id, ordinality)
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id
    and item.id = reordered.item_id;

  update public.session_items as item
  set position = item.position - temp_position_offset
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id;

  update public.sessions as session
  set
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id;

  return query
  select
    existing_session.plan_id,
    p_session_id,
    p_organization_id,
    existing_session.version + 1,
    (
      select coalesce(array_agg(item.id order by item.position, item.id), array[]::uuid[])
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    ),
    (
      select coalesce(
        array_agg(item.position order by item.position, item.id),
        array[]::integer[]
      )
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    );
end;
$$;
