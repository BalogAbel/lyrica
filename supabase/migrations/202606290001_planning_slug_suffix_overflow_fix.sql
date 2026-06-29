-- Make slug-suffix numbering overflow-safe.
--
-- plan_next_slug / session_next_slug parse a trailing digit run of the
-- slugified name to continue a numbering sequence. The original cast to
-- integer (int4) raised an unhandled 22003 for any suffix >= 2^31, turning a
-- user-controlled name into a denial-of-write. We wrap the cast so an
-- out-of-range (or otherwise unparseable) suffix falls back to numbering from
-- 1. The full text slug is still used for the first insert; the fallback only
-- affects collision numbering ("<root>-2", "<root>-3", ...).
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
    begin
      slug_number := substring(normalized_base_slug from '([0-9]+)$')::integer;
    exception
      when numeric_value_out_of_range then
        slug_number := 1;
    end;
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
    begin
      slug_number := substring(normalized_base_slug from '([0-9]+)$')::integer;
    exception
      when numeric_value_out_of_range then
        slug_number := 1;
    end;
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
