alter extension unaccent set schema extensions;

-- Redefine slugify to call the relocated extension by its new schema. The
-- `set search_path = public` is inlined here (not a follow-up `alter
-- function`) because `create or replace function` does not carry forward a
-- previously-set function config parameter -- the 202605160007 migration's
-- `alter function public.slugify(text) set search_path = public` would be
-- silently discarded if this replacement omitted it.
create or replace function public.slugify(input_value text)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          lower(extensions.unaccent(coalesce(input_value, ''))),
          '[^a-z0-9]+', '-', 'g'
        ),
        '(^-|-$)', '', 'g'
      ),
      '-{2,}', '-', 'g'
    ),
    ''
  );
$$;
