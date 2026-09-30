-- Plan content version and cascading plan/session delete.
--
-- Spec: docs/specs/2026-09-29-plan-delete-and-session-cascade.md (D1-D3,
-- invariants I1, I2, I4, I5). ADR: ADR-038.
--
-- plans.content_version counts every accepted write to a plan's sessions
-- and session items (I4). delete_plan checks it together with plans.version,
-- so a cascade delete can never remove content the deleting client did not
-- see (I2). Every child write locks the owning plan row first, through the
-- content_version bump, before its version check and its session or item
-- writes (I5). The session version checks therefore run as conditional
-- updates after that lock.

alter table public.plans
  add column content_version bigint not null default 1;

alter table public.plans
  add constraint plans_content_version_check check (content_version > 0);

-- Internal helper. Not callable by clients; every caller is a security
-- definer planning RPC that has already authorized the write.
create function public.bump_plan_content_version(
  p_organization_id uuid,
  p_plan_id uuid
)
returns bigint
language plpgsql
set search_path = public
as $$
declare
  v_content_version bigint;
begin
  update public.plans as plan
  set content_version = plan.content_version + 1
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
  returning plan.content_version into v_content_version;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'plan_not_found',
      detail = 'The owning plan does not exist in the requested organization';
  end if;

  return v_content_version;
end;
$$;

-- create_session: returns the session row plus plan_content_version.
drop function public.create_session(uuid, uuid, uuid, text, text);

create function public.create_session(
  p_organization_id uuid,
  p_plan_id uuid,
  p_session_id uuid,
  p_slug text,
  p_name text
)
returns table (
  id uuid,
  organization_id uuid,
  group_id uuid,
  plan_id uuid,
  "position" integer,
  name text,
  notes text,
  version bigint,
  base_version bigint,
  sync_status public.sync_status,
  updated_at timestamptz,
  last_modified_by uuid,
  slug text,
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  parent_plan public.plans%rowtype;
  created_session public.sessions%rowtype;
  candidate_slug text;
  next_position integer;
  v_constraint_name text;
  v_plan_content_version bigint;
begin
  select *
  into parent_plan
  from public.plans as plan
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
    and public.has_capability(
      plan.organization_id,
      'canEditSessions',
      plan.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'plan_not_found',
      detail = 'The target plan does not exist in the requested organization';
  end if;

  -- I5: lock the owning plan before touching sessions (and count, I4).
  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    p_plan_id
  );

  candidate_slug := public.session_next_slug(
    p_plan_id,
    coalesce(nullif(p_slug, ''), nullif(p_name, ''), p_session_id::text)
  );

  select coalesce(max(session.position), 0) + 1
  into next_position
  from public.sessions as session
  where session.plan_id = p_plan_id;

  loop
    begin
      insert into public.sessions (
        id,
        organization_id,
        group_id,
        plan_id,
        slug,
        position,
        name,
        version,
        base_version,
        sync_status,
        last_modified_by
      )
      values (
        p_session_id,
        p_organization_id,
        parent_plan.group_id,
        p_plan_id,
        candidate_slug,
        next_position,
        p_name,
        1,
        null,
        'synced',
        auth.uid()
      )
      returning * into created_session;

      return query
      select
        created_session.id,
        created_session.organization_id,
        created_session.group_id,
        created_session.plan_id,
        created_session.position,
        created_session.name,
        created_session.notes,
        created_session.version,
        created_session.base_version,
        created_session.sync_status,
        created_session.updated_at,
        created_session.last_modified_by,
        created_session.slug,
        v_plan_content_version;
      return;
    exception
      when unique_violation then
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'sessions_plan_slug_unique' then
          candidate_slug := public.session_next_slug(p_plan_id, candidate_slug);
        elsif v_constraint_name = 'sessions_plan_id_position_key' then
          select coalesce(max(session.position), 0) + 1
          into next_position
          from public.sessions as session
          where session.plan_id = p_plan_id;
        else
          raise;
        end if;
    end;
  end loop;

  raise exception using
    errcode = 'P0001',
    message = 'session_create_exhausted',
    detail = 'create_session exited without inserting a session';
end;
$$;

-- rename_session: returns the session row plus plan_content_version.
drop function public.rename_session(uuid, uuid, bigint, text);

create function public.rename_session(
  p_organization_id uuid,
  p_session_id uuid,
  p_base_version bigint,
  p_name text
)
returns table (
  id uuid,
  organization_id uuid,
  group_id uuid,
  plan_id uuid,
  "position" integer,
  name text,
  notes text,
  version bigint,
  base_version bigint,
  sync_status public.sync_status,
  updated_at timestamptz,
  last_modified_by uuid,
  slug text,
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  updated_session public.sessions%rowtype;
  v_plan_content_version bigint;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = 'base_version is required for session updates';
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

  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  update public.sessions as session
  set
    name = p_name,
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning * into updated_session;

  if found then
    return query
    select
      updated_session.id,
      updated_session.organization_id,
      updated_session.group_id,
      updated_session.plan_id,
      updated_session.position,
      updated_session.name,
      updated_session.notes,
      updated_session.version,
      updated_session.base_version,
      updated_session.sync_status,
      updated_session.updated_at,
      updated_session.last_modified_by,
      updated_session.slug,
      v_plan_content_version;
    return;
  end if;

  raise exception using
    errcode = 'P0001',
    message = 'session_version_conflict',
    detail = format(
      'expected base_version %s but found current version %s',
      p_base_version::text,
      existing_session.version::text
    );
end;
$$;

-- reorder_plan_sessions: the conditional plan update is the lock, the
-- version check, and the content_version bump in one statement.
drop function public.reorder_plan_sessions(uuid, uuid, bigint, uuid[]);

create function public.reorder_plan_sessions(
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
  ordered_session_positions integer[],
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_plan public.plans%rowtype;
  current_session_ids uuid[];
  temp_position_offset integer;
  v_version bigint;
  v_plan_content_version bigint;
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

  update public.plans as plan
  set
    version = plan.version + 1,
    base_version = plan.version,
    content_version = plan.content_version + 1,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
    and plan.version = p_base_version
  returning plan.version, plan.content_version
  into v_version, v_plan_content_version;

  if not found then
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

  return query
  select
    existing_plan.id,
    p_organization_id,
    v_version,
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
    ),
    v_plan_content_version;
end;
$$;

-- create_song_session_item: plan lock + bump, then conditional session bump.
drop function public.create_song_session_item(uuid, uuid, uuid, uuid, bigint, integer);

create function public.create_song_session_item(
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
  ordered_session_item_positions integer[],
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  visible_song public.songs%rowtype;
  next_position integer;
  v_constraint_name text;
  v_session_version bigint;
  v_plan_content_version bigint;
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

  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  update public.sessions as session
  set
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning session.version into v_session_version;

  if not found then
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

  begin
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
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'session_items_unique_song_per_session' then
        raise exception using
          errcode = 'P0001',
          message = 'duplicate_song_in_session_blocked',
          detail = 'The same song may appear at most once within one session';
      end if;
      raise;
  end;

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
    v_session_version,
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
    ),
    v_plan_content_version;
end;
$$;

-- delete_session_item: plan lock + bump, then conditional session bump.
drop function public.delete_session_item(uuid, uuid, uuid, bigint);

create function public.delete_session_item(
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
  ordered_session_item_positions integer[],
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  v_session_version bigint;
  v_plan_content_version bigint;
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

  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  update public.sessions as session
  set
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning session.version into v_session_version;

  if not found then
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

  return query
  select
    p_session_item_id,
    existing_session.plan_id,
    p_session_id,
    p_organization_id,
    v_session_version,
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
    ),
    v_plan_content_version;
end;
$$;

-- reorder_session_items: plan lock + bump, then conditional session bump.
drop function public.reorder_session_items(uuid, uuid, bigint, uuid[]);

create function public.reorder_session_items(
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
  ordered_session_item_positions integer[],
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  current_item_ids uuid[];
  temp_position_offset integer;
  v_session_version bigint;
  v_plan_content_version bigint;
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

  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  update public.sessions as session
  set
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning session.version into v_session_version;

  if not found then
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

  return query
  select
    existing_session.plan_id,
    p_session_id,
    p_organization_id,
    v_session_version,
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
    ),
    v_plan_content_version;
end;
$$;

-- delete_empty_session (legacy, D3): same signature, return shape and
-- emptiness rule; gains the bump. `create or replace` keeps its grants.
create or replace function public.delete_empty_session(
  p_organization_id uuid,
  p_session_id uuid,
  p_base_version bigint
)
returns table (
  id uuid,
  plan_id uuid,
  organization_id uuid,
  deleted boolean,
  deleted_version bigint
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
      detail = 'base_version is required for session deletes';
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

  perform public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

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

  if exists (
    select 1
    from public.session_items as session_item
    where session_item.organization_id = p_organization_id
      and session_item.session_id = p_session_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'session_delete_blocked_not_empty',
      detail = 'Session delete is allowed only when the session has no session_items';
  end if;

  return query
  delete from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning
    session.id,
    session.plan_id,
    session.organization_id,
    true,
    session.version;

  if found then
    return;
  end if;

  raise exception using
    errcode = 'P0002',
    message = 'session_not_found',
    detail = 'The target session no longer exists in the requested organization';
end;
$$;

comment on function public.delete_empty_session(uuid, uuid, bigint) is
  'Deprecated: kept for installed clients. New clients call delete_session '
  '(cascade). docs/specs/2026-09-29-plan-delete-and-session-cascade.md D3.';

-- delete_session (D3): cascade delete of one session and its items.
create function public.delete_session(
  p_organization_id uuid,
  p_session_id uuid,
  p_base_version bigint
)
returns table (
  id uuid,
  plan_id uuid,
  organization_id uuid,
  deleted boolean,
  deleted_version bigint,
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  v_plan_content_version bigint;
  v_current_version bigint;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = 'base_version is required for session deletes';
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

  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  -- Items follow through session_items_session_scope_fk (on delete cascade).
  -- Songs and attachments are only referenced, never deleted (I1).
  return query
  delete from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning
    session.id,
    session.plan_id,
    session.organization_id,
    true,
    session.version,
    v_plan_content_version;

  if found then
    return;
  end if;

  select session.version
  into v_current_version
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id;

  if found then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        v_current_version::text
      );
  end if;

  raise exception using
    errcode = 'P0002',
    message = 'session_not_found',
    detail = 'The target session no longer exists in the requested organization';
end;
$$;

-- delete_plan (D2): cascade delete of a plan, its sessions and their items.
create function public.delete_plan(
  p_organization_id uuid,
  p_plan_id uuid,
  p_base_version bigint,
  p_base_content_version bigint
)
returns table (
  id uuid,
  organization_id uuid,
  deleted boolean,
  deleted_version bigint,
  deleted_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_plan public.plans%rowtype;
  current_plan public.plans%rowtype;
begin
  if p_base_version is null or p_base_content_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'plan_version_conflict',
      detail = 'base_version and base_content_version are required for plan deletes';
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
    )
    and public.has_capability(
      plan.organization_id,
      'canEditSessions',
      plan.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'plan_not_found',
      detail = 'The target plan does not exist in the requested organization';
  end if;

  -- The delete itself takes the plan-row lock (I5). Sessions and items
  -- follow through sessions_plan_scope_fk and
  -- session_items_session_scope_fk (on delete cascade); songs and
  -- attachments are only referenced, never deleted (I1).
  return query
  delete from public.plans as plan
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
    and plan.version = p_base_version
    and plan.content_version = p_base_content_version
  returning
    plan.id,
    plan.organization_id,
    true,
    plan.version,
    plan.content_version;

  if found then
    return;
  end if;

  select *
  into current_plan
  from public.plans as plan
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id;

  if found then
    raise exception using
      errcode = 'P0001',
      message = 'plan_version_conflict',
      detail = format(
        'expected version %s / content_version %s but found %s / %s',
        p_base_version::text,
        p_base_content_version::text,
        current_plan.version::text,
        current_plan.content_version::text
      );
  end if;

  raise exception using
    errcode = 'P0002',
    message = 'plan_not_found',
    detail = 'The target plan no longer exists in the requested organization';
end;
$$;

revoke all on function public.bump_plan_content_version(uuid, uuid)
from public, anon, authenticated;

revoke all on function public.create_session(uuid, uuid, uuid, text, text)
from public, anon, authenticated;
revoke all on function public.rename_session(uuid, uuid, bigint, text)
from public, anon, authenticated;
revoke all on function public.reorder_plan_sessions(uuid, uuid, bigint, uuid[])
from public, anon, authenticated;
revoke all on function public.create_song_session_item(uuid, uuid, uuid, uuid, bigint, integer)
from public, anon, authenticated;
revoke all on function public.delete_session_item(uuid, uuid, uuid, bigint)
from public, anon, authenticated;
revoke all on function public.reorder_session_items(uuid, uuid, bigint, uuid[])
from public, anon, authenticated;
revoke all on function public.delete_session(uuid, uuid, bigint)
from public, anon, authenticated;
revoke all on function public.delete_plan(uuid, uuid, bigint, bigint)
from public, anon, authenticated;

grant execute on function public.create_session(uuid, uuid, uuid, text, text)
to authenticated;
grant execute on function public.rename_session(uuid, uuid, bigint, text)
to authenticated;
grant execute on function public.reorder_plan_sessions(uuid, uuid, bigint, uuid[])
to authenticated;
grant execute on function public.create_song_session_item(uuid, uuid, uuid, uuid, bigint, integer)
to authenticated;
grant execute on function public.delete_session_item(uuid, uuid, uuid, bigint)
to authenticated;
grant execute on function public.reorder_session_items(uuid, uuid, bigint, uuid[])
to authenticated;
grant execute on function public.delete_session(uuid, uuid, bigint)
to authenticated;
grant execute on function public.delete_plan(uuid, uuid, bigint, bigint)
to authenticated;
