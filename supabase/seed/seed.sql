insert into public.organizations (id, name, slug)
values ('11111111-1111-1111-1111-111111111111', 'Demo Organization', 'demo-organization')
on conflict (slug) do update
set name = excluded.name;

insert into public.groups (id, organization_id, name, description)
values (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'Worship Team',
  'Seed group for local development'
)
on conflict (id) do update
set
  name = excluded.name,
  description = excluded.description;

insert into public.songs (
  id,
  organization_id,
  title,
  artist,
  chordpro_source,
  metadata_json
)
values (
  '33333333-3333-3333-3333-333333333333',
  '11111111-1111-1111-1111-111111111111',
  'Build The Foundation',
  'Lyrica Seed',
  '{title: Build The Foundation}
{artist: Lyrica Seed}
[C]Build the foun[Am]dation
[F]Keep the source of [G]truth in git',
  '{"source":"seed"}'::jsonb
)
on conflict (id) do update
set
  title = excluded.title,
  artist = excluded.artist,
  chordpro_source = excluded.chordpro_source,
  metadata_json = excluded.metadata_json;
