create or replace function public.require_song_write_access(
  target_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_capability(target_organization_id, 'canEditSongs') then
    raise exception using
      errcode = '42501',
      message = 'song_write_not_authorized',
      detail = 'canEditSongs is required for song writes';
  end if;
end;
$$;

create or replace function public.song_next_slug(
  target_organization_id uuid,
  base_slug text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_base_slug text := coalesce(nullif(public.slugify(base_slug), ''), 'song');
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
    from public.songs as song
    where song.organization_id = target_organization_id
      and song.slug = candidate_slug
  ) loop
    slug_number := slug_number + 1;
    candidate_slug := slug_root || '-' || slug_number::text;
  end loop;

  return candidate_slug;
end;
$$;

create or replace function public.create_song(
  p_organization_id uuid,
  p_title text,
  p_artist text default null,
  p_key_signature text default null,
  p_tempo_bpm integer default null,
  p_tags text[] default '{}'::text[],
  p_chordpro_source text default null,
  p_metadata_json jsonb default '{}'::jsonb,
  p_requested_slug text default null,
  p_song_id uuid default null
)
returns public.songs
language plpgsql
security definer
set search_path = public
as $$
declare
  created_song public.songs%rowtype;
  candidate_slug text;
  v_constraint_name text;
begin
  perform public.require_song_write_access(p_organization_id);

  candidate_slug := public.song_next_slug(
    p_organization_id,
    coalesce(
      nullif(p_requested_slug, ''),
      nullif(p_title, ''),
      gen_random_uuid()::text
    )
  );

  loop
    begin
      insert into public.songs (
        id,
        organization_id,
        title,
        artist,
        key_signature,
        tempo_bpm,
        tags,
        chordpro_source,
        metadata_json,
        slug,
        version,
        base_version,
        sync_status,
        last_modified_by
      )
      values (
        coalesce(p_song_id, gen_random_uuid()),
        p_organization_id,
        p_title,
        p_artist,
        p_key_signature,
        p_tempo_bpm,
        coalesce(p_tags, '{}'::text[]),
        coalesce(p_chordpro_source, ''),
        coalesce(p_metadata_json, '{}'::jsonb),
        candidate_slug,
        1,
        null,
        'synced',
        auth.uid()
      )
      returning * into created_song;

      return created_song;
    exception
      when unique_violation then
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name <> 'songs_organization_slug_unique' then
          raise;
        end if;

        candidate_slug := public.song_next_slug(p_organization_id, candidate_slug);
    end;
  end loop;

  raise exception using
    errcode = 'P0001',
    message = 'song_slug_generation_failed',
    detail = 'create_song loop terminated unexpectedly without returning a row';
end;
$$;

create or replace function public.song_write_update_common(
  p_organization_id uuid,
  p_song_id uuid,
  p_base_version bigint,
  p_title text,
  p_artist text default null,
  p_key_signature text default null,
  p_tempo_bpm integer default null,
  p_tags text[] default null,
  p_chordpro_source text default null,
  p_metadata_json jsonb default null,
  p_enforce_version boolean default true
)
returns public.songs
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_song public.songs%rowtype;
  updated_song public.songs%rowtype;
begin
  perform public.require_song_write_access(p_organization_id);

  if p_enforce_version and p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'song_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        coalesce(p_base_version::text, 'null'),
        'unknown'
      );
  end if;

  update public.songs as song
  set
    title = p_title,
    artist = coalesce(p_artist, song.artist),
    key_signature = coalesce(p_key_signature, song.key_signature),
    tempo_bpm = coalesce(p_tempo_bpm, song.tempo_bpm),
    tags = coalesce(p_tags, song.tags),
    chordpro_source = coalesce(p_chordpro_source, song.chordpro_source),
    metadata_json = coalesce(p_metadata_json, song.metadata_json),
    version = song.version + 1,
    base_version = coalesce(p_base_version, song.version),
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where song.organization_id = p_organization_id
    and song.id = p_song_id
    and (not p_enforce_version or song.version = p_base_version)
  returning * into updated_song;

  if found then
    return updated_song;
  end if;

  select *
  into existing_song
  from public.songs as song
  where song.organization_id = p_organization_id
    and song.id = p_song_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'song_not_found',
      detail = 'The target song does not exist in the requested organization';
  end if;

  raise exception using
    errcode = 'P0001',
    message = 'song_version_conflict',
    detail = format(
      'expected base_version %s but found current version %s',
      coalesce(p_base_version::text, 'null'),
      existing_song.version::text
    );
end;
$$;

create or replace function public.update_song(
  p_organization_id uuid,
  p_song_id uuid,
  p_base_version bigint,
  p_title text,
  p_artist text default null,
  p_key_signature text default null,
  p_tempo_bpm integer default null,
  p_tags text[] default null,
  p_chordpro_source text default null,
  p_metadata_json jsonb default null
)
returns public.songs
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.song_write_update_common(
    p_organization_id,
    p_song_id,
    p_base_version,
    p_title,
    p_artist,
    p_key_signature,
    p_tempo_bpm,
    p_tags,
    p_chordpro_source,
    p_metadata_json,
    true
  );
end;
$$;

create or replace function public.overwrite_song_update(
  p_organization_id uuid,
  p_song_id uuid,
  p_base_version bigint,
  p_title text,
  p_requested_slug text default null,
  p_artist text default null,
  p_key_signature text default null,
  p_tempo_bpm integer default null,
  p_tags text[] default null,
  p_chordpro_source text default null,
  p_metadata_json jsonb default null
)
returns public.songs
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.songs as song
    where song.organization_id = p_organization_id
      and song.id = p_song_id
  ) then
    return public.create_song(
      p_organization_id => p_organization_id,
      p_title => p_title,
      p_artist => p_artist,
      p_key_signature => p_key_signature,
      p_tempo_bpm => p_tempo_bpm,
      p_tags => p_tags,
      p_chordpro_source => p_chordpro_source,
      p_metadata_json => p_metadata_json,
      p_requested_slug => p_requested_slug,
      p_song_id => p_song_id
    );
  end if;

  return public.song_write_update_common(
    p_organization_id,
    p_song_id,
    p_base_version,
    p_title,
    p_artist,
    p_key_signature,
    p_tempo_bpm,
    p_tags,
    p_chordpro_source,
    p_metadata_json,
    false
  );
end;
$$;

create or replace function public.song_write_delete_common(
  p_organization_id uuid,
  p_song_id uuid,
  p_base_version bigint,
  p_enforce_version boolean default true
)
returns public.songs
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_song public.songs%rowtype;
  deleted_song public.songs%rowtype;
begin
  perform public.require_song_write_access(p_organization_id);

  if p_enforce_version and p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'song_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        coalesce(p_base_version::text, 'null'),
        'unknown'
      );
  end if;

  delete from public.songs as song
  where song.organization_id = p_organization_id
    and song.id = p_song_id
    and (not p_enforce_version or song.version = p_base_version)
    and not exists (
      select 1
      from public.session_items as session_item
      where session_item.organization_id = p_organization_id
        and session_item.song_id = p_song_id
    )
  returning * into deleted_song;

  if found then
    return deleted_song;
  end if;

  select *
  into existing_song
  from public.songs as song
  where song.organization_id = p_organization_id
    and song.id = p_song_id;

  if not found then
    deleted_song.id := p_song_id;
    deleted_song.organization_id := p_organization_id;
    deleted_song.slug := p_song_id::text;
    deleted_song.title := '';
    deleted_song.chordpro_source := '';
    deleted_song.version := coalesce(p_base_version, 0);
    deleted_song.base_version := p_base_version;
    deleted_song.sync_status := 'synced';
    return deleted_song;
  end if;

  if exists (
    select 1
    from public.session_items as session_item
    where session_item.organization_id = p_organization_id
      and session_item.song_id = p_song_id
  ) then
    raise exception using
      errcode = '23503',
      message = 'song_delete_blocked_by_session_items',
      detail = 'A session item still references this song';
  end if;

  raise exception using
    errcode = 'P0001',
    message = 'song_version_conflict',
    detail = format(
      'expected base_version %s but found current version %s',
      coalesce(p_base_version::text, 'null'),
      existing_song.version::text
    );
end;
$$;

create or replace function public.delete_song(
  p_organization_id uuid,
  p_song_id uuid,
  p_base_version bigint
)
returns public.songs
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.song_write_delete_common(
    p_organization_id,
    p_song_id,
    p_base_version,
    true
  );
end;
$$;

create or replace function public.overwrite_song_delete(
  p_organization_id uuid,
  p_song_id uuid,
  p_base_version bigint
)
returns public.songs
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.song_write_delete_common(
    p_organization_id,
    p_song_id,
    p_base_version,
    false
  );
end;
$$;
