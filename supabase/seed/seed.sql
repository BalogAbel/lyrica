insert into public.organizations (id, name, slug)
values ('11111111-1111-1111-1111-111111111111', 'Demo Organization', 'demo-organization')
on conflict (slug) do update
set name = excluded.name;

insert into public.organizations (id, name, slug)
values ('11111111-1111-1111-1111-111111111112', 'Hidden Organization', 'hidden-organization')
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
  slug,
  artist,
  chordpro_source,
  metadata_json,
  key_signature
)
values (
  '33333333-3333-3333-3333-333333333333',
  '11111111-1111-1111-1111-111111111111',
  'A forrásnál',
  'a-forrasnal',
  null,
  $song$
{title:A forrásnál}
{subtitle:Ha szólsz megdobban a szív}
{key:A}
{comment:<Intro>}
[A] [C#m/G#] [F#m] [C#m/G#]

{comment:<Verse>}
Ha [A]szólsz, megdobban a [C#m/G#]szív, kiszárad a [F#m]száj
Téged akar [A/E]minden porciká[D]m, egész lényem [E]vágyik [A]Rád! [(E)]
[A]Úgy, mint egy kisfi[C#m/G#]ú ki várja apja [F#m]mit hozott
Egy [A/E]hosszú út utá[D]n, odaroha[E]nok hoz[A]zád

{comment:<Chorus>}
{start_of_chorus}
A forrás[A]nál szívem [E]inni kér, élő [Bm]víz fakad[D] s ömlik rá[E]m
A forrás[A]nál lelkünk [E]összeér, újra [Bm]az vagyok,[D] akinek álmod[E]tál!
{end_of_chorus}

{comment:<Bridge>}
[A]Élő Kútfő, [F#m]áldott Jézus, [D]forrá[E]sunk Te va[A]gy!
[A]Minden élet, [F#m]minden áldás [D]belőle[E]d faka[A]d

[A]
$song$,
  '{"source":"seed","catalog":"reader-slice"}'::jsonb,
  'A'
), (
  '33333333-3333-3333-3333-333333333334',
  '11111111-1111-1111-1111-111111111111',
  'A mi Istenünk (Leborulok előtted)',
  'a-mi-istenunk-leborulok-elotted',
  null,
  $song$
{title:A mi Istenünk (Leborulok előtted)}
{subtitle:Kegyelmed elég több mint elég}
{key:E}
[E]

{comment:<Verse 1>}
[E] Kegyelmed elé[G#m]g, több, mint elé[C#m]g, Igé[A]dben bízok é[E]n
Így várok Rá[G#m]d, Vonj közel megi[C#m]nt, Szelleme[A]d újítson me[B]g!

{comment:<Chorus 1>}
{start_of_chorus}
[(B)] Leborul[E/G#]ok előtt[A]ed, leborul[F#m]ok előtt[B/D#]ed, és imádl[E/G#]ak tég[A]ed
{end_of_chorus}

{comment:<Verse 2>}
[E] Jelenlétedbe[G#m]n világíts neke[C#m]m, szava[A]d hatalmáva[E]l
Helyreállta[G#m]m, szabaddá lette[C#m]m, Szelleme[A]d segít enge[B]m

{comment:<Chorus 2>}
{start_of_chorus}
[(B)] Leborul[E/G#]ok lábadh[A]oz, leborul[F#m]ok lábadh[B/D#]oz, és imádl[E/G#]ak Jéz[A]us
{end_of_chorus}

{comment:<Bridge>}
Önként adtá[E]l oda mindent, életede[B]t a kereszten
Mily' nagy szerete[F#m]t, mit adott nekü[C#m]nk a mi [A]Istenü[E]nk!
A halálból fö[E]lemeltettél, életed le[B]tt nekünk a fény
Szolga- Kirá[F#m]ly, szabadító[C#m], a mi [A]Istenü[E]nk!
$song$,
  '{"source":"seed","catalog":"reader-slice"}'::jsonb,
  'E'
), (
  '33333333-3333-3333-3333-333333333335',
  '11111111-1111-1111-1111-111111111111',
  'Egy út',
  'egy-ut',
  null,
  $song$
{title:Egy út}
{subtitle:One Way}
{key:B}
{comment:<Verse 1>}
[B] Leteszem az életem
[G#m] Te legyél az egyetlen
[F#] Futok hozzád, hisz Te mindig vársz[E]
[B] Ha próbák jönnek a szívem szól
[G#m] Te vagy az első, Tiéd a trón
[F#] Leborulok Eléd égi Úr![E]

{comment:<Verse 2>}
[B] Legyek bárhol, bármiben
[G#m] Őrzöl engem nem hagysz el
[F#] Kegyelmed megérint, Hozzád vonz[E]
[B] Tegnap ma és mindenkor
[G#m] Te soha meg nem változol
[F#] Örökkévaló fenséges Úr![E]

{comment:<Chorus>}
{start_of_chorus}
[B] Egy út,[F#] Jézus
[G#m] Te vagy az, Akiért [E]érdemes élnem!
[B] Nincs más,[F#] (csak) Jézus
[G#m] egyetlen, Akiért [E]érdemes élnem! [(B)]
{end_of_chorus}

{comment:<Bridge>}
[B]Te vagy az út és [F#]Te vagy a cél
Az [G#m]igazság az [E]élet, hit, remény[G#m]
Csak [F#m]érted élek én![E]
[B]
$song$,
  '{"source":"seed","catalog":"reader-slice"}'::jsonb,
  'B'
), (
  '33333333-3333-3333-3333-333333333336',
  '11111111-1111-1111-1111-111111111112',
  'Hidden Seed Song',
  'hidden-seed-song',
  null,
  $song$
{title:Hidden Seed Song}
{subtitle:Authorization isolation fixture}
{key:C}
{comment:<Verse 1>}
[C] This song should stay outside the demo membership scope.
$song$,
  '{"source":"seed","catalog":"authorization-isolation"}'::jsonb,
  'C'
)
on conflict (id) do update
set
  title = excluded.title,
  slug = excluded.slug,
  artist = excluded.artist,
  chordpro_source = excluded.chordpro_source,
  metadata_json = excluded.metadata_json,
  key_signature = excluded.key_signature;

insert into public.plans (
  id,
  organization_id,
  group_id,
  name,
  slug,
  description,
  scheduled_for,
  updated_at
)
values (
  '44444444-4444-4444-4444-444444444441',
  '11111111-1111-1111-1111-111111111111',
  null,
  'Sunday Morning',
  'sunday-morning',
  'Single-session fixture for the first planning read slice.',
  '2026-04-05T08:30:00Z',
  '2026-03-31T08:00:00Z'
), (
  '44444444-4444-4444-4444-444444444442',
  '11111111-1111-1111-1111-111111111111',
  null,
  'Team Rehearsal',
  'team-rehearsal',
  'Multi-session fixture proving the direct plan-to-session hierarchy.',
  null,
  '2026-03-31T09:00:00Z'
), (
  '44444444-4444-4444-4444-444444444443',
  '11111111-1111-1111-1111-111111111111',
  null,
  'Evening Gathering',
  'evening-gathering',
  'Later scheduled fixture for deterministic ordering checks.',
  '2026-04-12T17:00:00Z',
  '2026-03-31T07:30:00Z'
), (
  '44444444-4444-4444-4444-444444444444',
  '11111111-1111-1111-1111-111111111112',
  null,
  'Hidden Organization Plan',
  'hidden-organization-plan',
  'Authorization isolation fixture that must not be visible to the demo user.',
  '2026-04-06T09:00:00Z',
  '2026-03-31T10:00:00Z'
)
on conflict (id) do update
set
  name = excluded.name,
  slug = excluded.slug,
  description = excluded.description,
  scheduled_for = excluded.scheduled_for,
  updated_at = excluded.updated_at;

insert into public.sessions (
  id,
  organization_id,
  group_id,
  plan_id,
  slug,
  position,
  name,
  notes,
  updated_at
)
values (
  '55555555-5555-5555-5555-555555555551',
  '11111111-1111-1111-1111-111111111111',
  null,
  '44444444-4444-4444-4444-444444444441',
  'main-set',
  10,
  'Main Set',
  'Single-session plan fixture.',
  '2026-03-31T08:10:00Z'
), (
  '55555555-5555-5555-5555-555555555552',
  '11111111-1111-1111-1111-111111111111',
  null,
  '44444444-4444-4444-4444-444444444442',
  'warm-up',
  10,
  'Warm-Up',
  'First session in the multi-session fixture.',
  '2026-03-31T09:10:00Z'
), (
  '55555555-5555-5555-5555-555555555553',
  '11111111-1111-1111-1111-111111111111',
  null,
  '44444444-4444-4444-4444-444444444442',
  'run-through',
  20,
  'Run-Through',
  'Second session in the multi-session fixture.',
  '2026-03-31T09:20:00Z'
), (
  '55555555-5555-5555-5555-555555555554',
  '11111111-1111-1111-1111-111111111111',
  null,
  '44444444-4444-4444-4444-444444444443',
  'evening-set',
  10,
  'Evening Set',
  'Later scheduled plan fixture.',
  '2026-03-31T07:40:00Z'
), (
  '55555555-5555-5555-5555-555555555555',
  '11111111-1111-1111-1111-111111111112',
  null,
  '44444444-4444-4444-4444-444444444444',
  'hidden-session',
  10,
  'Hidden Session',
  'Hidden organization fixture.',
  '2026-03-31T10:10:00Z'
)
on conflict (id) do update
set
  plan_id = excluded.plan_id,
  slug = excluded.slug,
  position = excluded.position,
  name = excluded.name,
  notes = excluded.notes,
  updated_at = excluded.updated_at;

insert into public.session_items (
  id,
  organization_id,
  session_id,
  song_id,
  item_type,
  position,
  notes,
  updated_at
)
values (
  '66666666-6666-6666-6666-666666666661',
  '11111111-1111-1111-1111-111111111111',
  '55555555-5555-5555-5555-555555555551',
  '33333333-3333-3333-3333-333333333333',
  'song',
  10,
  'Opening song.',
  '2026-03-31T08:11:00Z'
), (
  '66666666-6666-6666-6666-666666666662',
  '11111111-1111-1111-1111-111111111111',
  '55555555-5555-5555-5555-555555555551',
  '33333333-3333-3333-3333-333333333334',
  'song',
  20,
  'Second song in the single-session plan.',
  '2026-03-31T08:12:00Z'
), (
  '66666666-6666-6666-6666-666666666663',
  '11111111-1111-1111-1111-111111111111',
  '55555555-5555-5555-5555-555555555552',
  '33333333-3333-3333-3333-333333333335',
  'song',
  10,
  'Warm-up opener.',
  '2026-03-31T09:11:00Z'
), (
  '66666666-6666-6666-6666-666666666664',
  '11111111-1111-1111-1111-111111111111',
  '55555555-5555-5555-5555-555555555553',
  '33333333-3333-3333-3333-333333333333',
  'song',
  10,
  'First song in the run-through session.',
  '2026-03-31T09:21:00Z'
), (
  '66666666-6666-6666-6666-666666666665',
  '11111111-1111-1111-1111-111111111111',
  '55555555-5555-5555-5555-555555555553',
  '33333333-3333-3333-3333-333333333334',
  'song',
  20,
  'Second song in the run-through session.',
  '2026-03-31T09:22:00Z'
), (
  '66666666-6666-6666-6666-666666666666',
  '11111111-1111-1111-1111-111111111111',
  '55555555-5555-5555-5555-555555555554',
  '33333333-3333-3333-3333-333333333335',
  'song',
  10,
  'Later scheduled plan song.',
  '2026-03-31T07:41:00Z'
), (
  '66666666-6666-6666-6666-666666666667',
  '11111111-1111-1111-1111-111111111112',
  '55555555-5555-5555-5555-555555555555',
  '33333333-3333-3333-3333-333333333336',
  'song',
  10,
  'Hidden organization song.',
  '2026-03-31T10:11:00Z'
)
on conflict (id) do update
set
  session_id = excluded.session_id,
  song_id = excluded.song_id,
  item_type = excluded.item_type,
  position = excluded.position,
  notes = excluded.notes,
  updated_at = excluded.updated_at;
