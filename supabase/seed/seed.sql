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
  metadata_json,
  key_signature
)
values (
  '33333333-3333-3333-3333-333333333333',
  '11111111-1111-1111-1111-111111111111',
  'A forrásnál',
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
)
on conflict (id) do update
set
  title = excluded.title,
  artist = excluded.artist,
  chordpro_source = excluded.chordpro_source,
  metadata_json = excluded.metadata_json,
  key_signature = excluded.key_signature;
