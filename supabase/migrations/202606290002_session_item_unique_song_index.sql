-- SEC-5: enforce "a song appears at most once per session" at the database
-- level, not only via the application-level pre-check in
-- create_song_session_item. The pre-check can be bypassed by a truly
-- concurrent double-insert sharing one stale base_version; the partial unique
-- index is the backstop. create_song_session_item catches the index violation
-- and re-raises the existing P0001 duplicate_song_in_session_blocked so the
-- client-facing error contract (mapped to dependencyBlocked) stays stable.
create unique index session_items_unique_song_per_session
  on public.session_items (session_id, song_id)
  where item_type = 'song';

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
  v_constraint_name text;
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
