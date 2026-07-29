-- ChordPro directive scanner. Reproduces chordpro_line_scanner.dart:66-84
-- exactly for the grammar (brace-delimited body, first-colon name/value
-- split, name lowercased, empty body ignored), plus the two structural
-- gates from chordpro_parser.dart that apply before any field rule:
--
--   * tab-block inertness (:52-54) -- while inside a
--     {start_of_tab}...{end_of_tab} block, a directive whose name does not
--     start with end_of_ is swallowed as tab content and is not emitted as
--     a directive row at all.
--   * the key window -- a has_seen_song_content flag, false at the start,
--     set true by the first lyric line (:36), any start_of_* directive
--     (:150), or any end_of_* directive (:201). Exposed per emitted row as
--     key_window_open (the negation of that flag as it stood BEFORE this
--     line's own effect), consumed only by chordpro_derive_key_signature.
--     Deliberately NOT set by a {comment}/{c} directive recognised as a
--     section start (:138, via _parseCommentSection) -- reproducing that
--     would duplicate a second small parser inside this one. This is the
--     one accepted, named divergence; see ADR-027 and Task 6's tests.
--
-- Written in plpgsql with an explicit ordered walk, not a stateless SQL
-- sweep, because in_tab and has_seen_song_content are sequential state
-- carried across lines -- a recursive CTE could express the same state
-- machine, but a `for` loop with two booleans is far easier to verify
-- line-by-line against the Dart source above.
--
-- Uses btrim(x, E' \t\n\r\v\f') rather than bare trim(), because SQL's
-- trim() strips only the ASCII space by default, while Dart's String.trim()
-- strips all whitespace -- a ChordPro line indented with a tab, vertical
-- tab, or form feed would otherwise fail to match what Dart parses.
create or replace function public.chordpro_scan_directives(source text)
returns table(
  line_number integer,
  directive_name text,
  directive_value text,
  key_window_open boolean
)
language plpgsql
immutable
as $$
declare
  v_normalized_source text := replace(coalesce(source, ''), chr(13) || chr(10), chr(10));
  v_line text;
  v_line_number integer := 0;
  v_trimmed_line text;
  v_body text;
  v_colon_pos integer;
  v_name text;
  v_value text;
  v_in_tab boolean := false;
  v_has_seen_song_content boolean := false;
begin
  foreach v_line in array string_to_array(v_normalized_source, chr(10))
  loop
    v_line_number := v_line_number + 1;
    v_trimmed_line := btrim(v_line, E' \t\n\r\v\f');

    if v_trimmed_line = '' then
      -- Empty line: no effect on any state, matching ChordproLineKind.empty.
      continue;
    end if;

    if v_trimmed_line like '{%}' and length(v_trimmed_line) >= 2 then
      v_body := btrim(
        substring(v_trimmed_line from 2 for length(v_trimmed_line) - 2),
        E' \t\n\r\v\f'
      );

      if v_body = '' then
        -- An empty-body brace pair ("{}") is not a directive to the
        -- scanner, so chordpro_line_scanner.dart classifies the whole line
        -- as lyric-kind instead -- which the parser then uses to set
        -- has_seen_song_content, same as any other lyric line.
        v_has_seen_song_content := true;
        continue;
      end if;

      v_colon_pos := position(':' in v_body);
      if v_colon_pos = 0 then
        v_name := lower(v_body);
        v_value := null;
      else
        v_name := lower(btrim(substring(v_body from 1 for v_colon_pos - 1), E' \t\n\r\v\f'));
        v_value := btrim(substring(v_body from v_colon_pos + 1), E' \t\n\r\v\f');
      end if;

      if v_in_tab and v_name not like 'end_of_%' then
        -- Tab-block inertness: swallowed as tab content, not emitted, and
        -- no state change at all -- matching that this whole branch in the
        -- Dart parser bypasses the field-rule chain entirely.
        continue;
      end if;

      -- Emit with the key-window state as it stood BEFORE this line's own
      -- effect (below) is applied.
      line_number := v_line_number;
      directive_name := v_name;
      directive_value := v_value;
      key_window_open := not v_has_seen_song_content;
      return next;

      if v_name = 'start_of_tab' then
        v_in_tab := true;
        v_has_seen_song_content := true;
      elsif v_name like 'start_of_%' then
        v_has_seen_song_content := true;
      elsif v_name like 'end_of_%' then
        v_in_tab := false;
        v_has_seen_song_content := true;
      end if;
    else
      -- A non-empty, non-directive line is a lyric line. The scanner
      -- classifies purely on brace matching, irrespective of tab-section
      -- state; chordpro_parser.dart:36 sets has_seen_song_content on every
      -- lyric-kind line, including ones inside a tab block.
      v_has_seen_song_content := true;
    end if;
  end loop;

  return;
end;
$$;

revoke all on function public.chordpro_scan_directives(text)
from public, anon, authenticated;

-- title | title, t | last occurrence wins | value or ''
create or replace function public.chordpro_derive_title(source text)
returns text
language sql
immutable
as $$
  select coalesce(
    (
      select directive_value
      from public.chordpro_scan_directives(source)
      where directive_name in ('title', 't')
      order by line_number desc
      limit 1
    ),
    ''
  );
$$;

revoke all on function public.chordpro_derive_title(text)
from public, anon, authenticated;

-- artist | artist | last occurrence wins | trimmed (assigned every
-- occurrence, so a later bare {artist} can null out an earlier value)
create or replace function public.chordpro_derive_artist(source text)
returns text
language sql
immutable
as $$
  select trim(directive_value)
  from public.chordpro_scan_directives(source)
  where directive_name = 'artist'
  order by line_number desc
  limit 1;
$$;

revoke all on function public.chordpro_derive_artist(text)
from public, anon, authenticated;

-- key_signature | key | honoured only while the key window is open
-- (chordpro_scan_directives' key_window_open, tracking has_seen_song_content
-- the way chordpro_parser.dart:62 does -- closed by a lyric line or any
-- start_of_*/end_of_* directive); last valid occurrence among those wins;
-- invalid (empty-after-trim) occurrences are skipped, not assigned, so
-- they do not overwrite a previously valid value. Does NOT close the
-- window on a comment recognised as a section start
-- (chordpro_parser.dart:138) -- the one accepted, documented divergence;
-- see ADR-027.
create or replace function public.chordpro_derive_key_signature(source text)
returns text
language sql
immutable
as $$
  select nullif(trim(directive_value), '')
  from public.chordpro_scan_directives(source)
  where directive_name = 'key'
    and key_window_open
    and nullif(trim(directive_value), '') is not null
  order by line_number desc
  limit 1;
$$;

revoke all on function public.chordpro_derive_key_signature(text)
from public, anon, authenticated;

-- tempo_bpm | tempo | last occurrence wins (unconditionally -- a later
-- non-integer occurrence nulls an earlier valid one); integer parse,
-- non-integer (including out-of-int4-range) ignored rather than raising.
create or replace function public.chordpro_derive_tempo_bpm(source text)
returns integer
language plpgsql
immutable
as $$
declare
  v_directive_value text;
  v_result integer;
begin
  select directive_value
  into v_directive_value
  from public.chordpro_scan_directives(source)
  where directive_name = 'tempo'
  order by line_number desc
  limit 1;

  if not found then
    return null;
  end if;

  begin
    v_result := trim(v_directive_value)::integer;
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      return null;
  end;

  return v_result;
end;
$$;

revoke all on function public.chordpro_derive_tempo_bpm(text)
from public, anon, authenticated;

-- tags | tags, tag | last occurrence wins | split on ',', trim each, drop
-- empties; no matching directive (or a bare one) yields '{}', never null,
-- since songs.tags is not null default '{}'.
create or replace function public.chordpro_derive_tags(source text)
returns text[]
language sql
immutable
as $$
  select coalesce(
    (
      select array_agg(trim(tag_value))
      from (
        select directive_value
        from public.chordpro_scan_directives(source)
        where directive_name in ('tags', 'tag')
        order by line_number desc
        limit 1
      ) as last_tags,
      unnest(string_to_array(last_tags.directive_value, ',')) as tag_value
      where trim(tag_value) <> ''
    ),
    '{}'::text[]
  );
$$;

revoke all on function public.chordpro_derive_tags(text)
from public, anon, authenticated;

drop function if exists public.create_song(
  uuid, text, text, text, integer, text[], text, jsonb, text, uuid
);

create or replace function public.create_song(
  p_organization_id uuid,
  p_title text,
  p_chordpro_source text default null,
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
  v_effective_source text := coalesce(p_chordpro_source, '');
  v_title text;
begin
  -- Authorize before parsing: a DECLARE-block initializer would run first, so
  -- an unauthorized caller could still make the server parse their source.
  perform public.require_song_write_access(p_organization_id);

  v_title := coalesce(
    nullif(trim(public.chordpro_derive_title(v_effective_source)), ''),
    nullif(p_title, ''),
    gen_random_uuid()::text
  );

  -- p_requested_slug still wins: the sync payload carries the slug an offline
  -- client already routed by, and reassigning it here would break slug-based
  -- routing for rows created offline. v_title is never empty by construction,
  -- so it is the effective fallback.
  candidate_slug := public.song_next_slug(
    p_organization_id,
    coalesce(nullif(p_requested_slug, ''), v_title)
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
        v_title,
        public.chordpro_derive_artist(v_effective_source),
        public.chordpro_derive_key_signature(v_effective_source),
        public.chordpro_derive_tempo_bpm(v_effective_source),
        public.chordpro_derive_tags(v_effective_source),
        v_effective_source,
        '{}'::jsonb,
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

revoke all on function public.create_song(uuid, text, text, text, uuid)
from public, anon, authenticated;
grant execute on function public.create_song(uuid, text, text, text, uuid)
to authenticated;

drop function if exists public.song_write_update_common(
  uuid, uuid, bigint, text, text, text, integer, text[], text, jsonb, boolean
);
drop function if exists public.update_song(
  uuid, uuid, bigint, text, text, text, integer, text[], text, jsonb
);
drop function if exists public.overwrite_song_update(
  uuid, uuid, bigint, text, text, text, text, integer, text[], text, jsonb
);

create or replace function public.song_write_update_common(
  p_organization_id uuid,
  p_song_id uuid,
  p_base_version bigint,
  p_title text,
  p_chordpro_source text default null,
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
    title = coalesce(
      nullif(
        trim(public.chordpro_derive_title(coalesce(p_chordpro_source, song.chordpro_source))),
        ''
      ),
      nullif(p_title, ''),
      song.title
    ),
    artist = public.chordpro_derive_artist(coalesce(p_chordpro_source, song.chordpro_source)),
    key_signature = public.chordpro_derive_key_signature(coalesce(p_chordpro_source, song.chordpro_source)),
    tempo_bpm = public.chordpro_derive_tempo_bpm(coalesce(p_chordpro_source, song.chordpro_source)),
    tags = public.chordpro_derive_tags(coalesce(p_chordpro_source, song.chordpro_source)),
    chordpro_source = coalesce(p_chordpro_source, song.chordpro_source),
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
  p_chordpro_source text default null
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
    p_chordpro_source,
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
  p_chordpro_source text default null
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
      p_chordpro_source => p_chordpro_source,
      p_requested_slug => p_requested_slug,
      p_song_id => p_song_id
    );
  end if;

  return public.song_write_update_common(
    p_organization_id,
    p_song_id,
    p_base_version,
    p_title,
    p_chordpro_source,
    false
  );
end;
$$;

revoke all on function public.song_write_update_common(uuid, uuid, bigint, text, text, boolean)
from public, anon, authenticated;

revoke all on function public.update_song(uuid, uuid, bigint, text, text)
from public, anon, authenticated;
grant execute on function public.update_song(uuid, uuid, bigint, text, text)
to authenticated;

revoke all on function public.overwrite_song_update(uuid, uuid, bigint, text, text, text)
from public, anon, authenticated;
grant execute on function public.overwrite_song_update(uuid, uuid, bigint, text, text, text)
to authenticated;
