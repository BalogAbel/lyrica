create extension if not exists unaccent;

create or replace function public.slugify(input_value text)
returns text
language sql
immutable
as $$
  select nullif(
    regexp_replace(
      regexp_replace(
        regexp_replace(lower(unaccent(coalesce(input_value, ''))), '[^a-z0-9]+', '-', 'g'),
        '(^-|-$)',
        '',
        'g'
      ),
      '-{2,}',
      '-',
      'g'
    ),
    ''
  );
$$;

alter table public.songs add column slug text;
alter table public.plans add column slug text;
alter table public.sessions add column slug text;

with numbered_songs as (
  select
    song.id,
    song.organization_id,
    coalesce(public.slugify(song.title), song.id::text) as base_slug,
    row_number() over (
      partition by song.organization_id, coalesce(public.slugify(song.title), song.id::text)
      order by song.title, song.id
    ) as slug_index
  from public.songs as song
),
slugged_songs as (
  select
    id,
    organization_id,
    case
      when slug_index = 1 then base_slug
      else base_slug || '-' || slug_index::text
    end as slug
  from numbered_songs
)
update public.songs as song
set slug = slugged_songs.slug
from slugged_songs
where song.id = slugged_songs.id
  and song.organization_id = slugged_songs.organization_id;

with numbered_plans as (
  select
    plan.id,
    plan.organization_id,
    coalesce(public.slugify(plan.name), plan.id::text) as base_slug,
    row_number() over (
      partition by plan.organization_id, coalesce(public.slugify(plan.name), plan.id::text)
      order by plan.name, plan.id
    ) as slug_index
  from public.plans as plan
),
slugged_plans as (
  select
    id,
    organization_id,
    case
      when slug_index = 1 then base_slug
      else base_slug || '-' || slug_index::text
    end as slug
  from numbered_plans
)
update public.plans as plan
set slug = slugged_plans.slug
from slugged_plans
where plan.id = slugged_plans.id
  and plan.organization_id = slugged_plans.organization_id;

with numbered_sessions as (
  select
    session.id,
    session.plan_id,
    coalesce(public.slugify(session.name), session.id::text) as base_slug,
    row_number() over (
      partition by session.plan_id, coalesce(public.slugify(session.name), session.id::text)
      order by session.name, session.id
    ) as slug_index
  from public.sessions as session
),
slugged_sessions as (
  select
    id,
    plan_id,
    case
      when slug_index = 1 then base_slug
      else base_slug || '-' || slug_index::text
    end as slug
  from numbered_sessions
)
update public.sessions as session
set slug = slugged_sessions.slug
from slugged_sessions
where session.id = slugged_sessions.id
  and session.plan_id = slugged_sessions.plan_id;

alter table public.songs alter column slug set not null;
alter table public.plans alter column slug set not null;
alter table public.sessions alter column slug set not null;

alter table public.songs
  add constraint songs_organization_slug_unique unique (organization_id, slug);

alter table public.plans
  add constraint plans_organization_slug_unique unique (organization_id, slug);

alter table public.sessions
  add constraint sessions_plan_slug_unique unique (plan_id, slug);
