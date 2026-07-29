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
