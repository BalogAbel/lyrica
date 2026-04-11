create or replace function public.require_plan_write_access(
  target_organization_id uuid,
  target_group_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_capability(target_organization_id, 'canManagePlans', target_group_id) then
    raise exception using
      errcode = '42501',
      message = 'plan_write_not_authorized',
      detail = 'canManagePlans is required for plan writes';
  end if;
end;
$$;

create or replace function public.require_session_write_access(
  target_organization_id uuid,
  target_group_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_capability(target_organization_id, 'canEditSessions', target_group_id) then
    raise exception using
      errcode = '42501',
      message = 'session_write_not_authorized',
      detail = 'canEditSessions is required for session writes';
  end if;
end;
$$;

create or replace function public.plan_next_slug(
  target_organization_id uuid,
  base_slug text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_base_slug text := coalesce(nullif(public.slugify(base_slug), ''), 'plan');
  slug_root text := normalized_base_slug;
  slug_number integer := 1;
  candidate_slug text := normalized_base_slug;
begin
  if normalized_base_slug ~ '^(.*)-([0-9]+)$' then
    slug_root := regexp_replace(normalized_base_slug, '-[0-9]+$', '');
    slug_number := substring(normalized_base_slug from '([0-9]+)$')::integer;
  end if;

  while exists (
    select 1
    from public.plans as plan
    where plan.organization_id = target_organization_id
      and plan.slug = candidate_slug
  ) loop
    slug_number := slug_number + 1;
    candidate_slug := slug_root || '-' || slug_number::text;
  end loop;

  return candidate_slug;
end;
$$;

create or replace function public.session_next_slug(
  target_plan_id uuid,
  base_slug text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_base_slug text := coalesce(nullif(public.slugify(base_slug), ''), 'session');
  slug_root text := normalized_base_slug;
  slug_number integer := 1;
  candidate_slug text := normalized_base_slug;
begin
  if normalized_base_slug ~ '^(.*)-([0-9]+)$' then
    slug_root := regexp_replace(normalized_base_slug, '-[0-9]+$', '');
    slug_number := substring(normalized_base_slug from '([0-9]+)$')::integer;
  end if;

  while exists (
    select 1
    from public.sessions as session
    where session.plan_id = target_plan_id
      and session.slug = candidate_slug
  ) loop
    slug_number := slug_number + 1;
    candidate_slug := slug_root || '-' || slug_number::text;
  end loop;

  return candidate_slug;
end;
$$;

create or replace function public.create_plan(
  p_organization_id uuid,
  p_plan_id uuid,
  p_slug text,
  p_name text,
  p_description text default null,
  p_scheduled_for timestamptz default null
)
returns public.plans
language plpgsql
security definer
set search_path = public
as $$
declare
  created_plan public.plans%rowtype;
  candidate_slug text;
  v_constraint_name text;
begin
  perform public.require_plan_write_access(p_organization_id, null);

  candidate_slug := public.plan_next_slug(
    p_organization_id,
    coalesce(nullif(p_slug, ''), nullif(p_name, ''), p_plan_id::text)
  );

  loop
    begin
      insert into public.plans (
        id,
        organization_id,
        group_id,
        slug,
        name,
        description,
        scheduled_for,
        version,
        base_version,
        sync_status,
        last_modified_by
      )
      values (
        p_plan_id,
        p_organization_id,
        null,
        candidate_slug,
        p_name,
        p_description,
        p_scheduled_for,
        1,
        null,
        'synced',
        auth.uid()
      )
      returning * into created_plan;

      return created_plan;
    exception
      when unique_violation then
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name <> 'plans_organization_slug_unique' then
          raise;
        end if;

        candidate_slug := public.plan_next_slug(p_organization_id, candidate_slug);
    end;
  end loop;

  raise exception using
    errcode = 'P0001',
    message = 'plan_create_exhausted',
    detail = 'create_plan exited without inserting a plan';
end;
$$;

create or replace function public.update_plan_fields(
  p_organization_id uuid,
  p_plan_id uuid,
  p_base_version bigint,
  p_name text,
  p_description text default null,
  p_scheduled_for timestamptz default null
)
returns public.plans
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_plan public.plans%rowtype;
  updated_plan public.plans%rowtype;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'plan_version_conflict',
      detail = 'base_version is required for plan updates';
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
    name = p_name,
    description = p_description,
    scheduled_for = p_scheduled_for,
    version = plan.version + 1,
    base_version = plan.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
    and plan.version = p_base_version
  returning * into updated_plan;

  if found then
    return updated_plan;
  end if;

  raise exception using
    errcode = 'P0001',
    message = 'plan_version_conflict',
    detail = format(
      'expected base_version %s but found current version %s',
      p_base_version::text,
      existing_plan.version::text
    );
end;
$$;

create or replace function public.create_session(
  p_organization_id uuid,
  p_plan_id uuid,
  p_session_id uuid,
  p_slug text,
  p_name text
)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_plan public.plans%rowtype;
  created_session public.sessions%rowtype;
  candidate_slug text;
  next_position integer;
  v_constraint_name text;
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

      return created_session;
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

create or replace function public.rename_session(
  p_organization_id uuid,
  p_session_id uuid,
  p_base_version bigint,
  p_name text
)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_session public.sessions%rowtype;
  updated_session public.sessions%rowtype;
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
    return updated_session;
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
