# Song Editing UI Spec

> Status: Draft

## Goal

Rendezze a song editing feluletet ugy, hogy a title, metadata, chord source, transpose, es capo szerkesztes egy koherens, preview-kepes workspace legyen. A slice celja a vizualis es workflow irany tisztazasa egy repository-owned mockon keresztul, nem a vegleges Flutter implementacio.

## Problem

A jelenlegi song domain mar kezeli a canonical ChordPro forrast, a strukturalis metadata mezoket, es a reader oldali transpose/capo viselkedest, de a szerkesztesi felulet nincs ugyanilyen tiszta modon megszervezve.

Ez tobb problemat okoz:

- a title es metadata szerkesztes nincs egyertelmuen elvalasztva a chord source szerkesztestol
- a song-owned transpose es capo ertekek es a reader runtime transpose/capo nem latszanak egymas mellett
- a felulet kontextusa nem mutatja tisztan, mi canonical song data es mi csak preview vagy runtime viselkedes
- a jelenlegi mock-vocabularyhoz illeszkedo editing surface hianyzik, ezert a design beszede ad hoc marad

## Scope

- Definialja a song edit workspace vizualis szerkezetet.
- Lefedi a title szerkesztest.
- Lefedi az egyeb song metadata szerkeszteset.
- Lefedi a canonical chord source szerkesztest.
- Lefedi a songhoz kotott, ket-szintu transpose es capo modellt.
- Lefedi a live preview / reader-feedback reszt, ahol latszik az effektive transpose es capo.
- Letrehoz egy repository-owned mockot a meglovo `docs/prototypes/` mintajara.
- Megorzi a jelenlegi backend-enforced authorization hatarat.

## Non-Goals

- No new authorization model.
- No new backend policy slice.
- No real-time collaborative editing.
- No rich visual chord editor in this slice.
- No reader redesign beyond the preview needed to validate song settings.
- No final component decomposition for Flutter implementation until the mock es spec elfogadott.

## Product Direction

A song editing felulet legyen workspace, ne egymasra pakolt form mezohalmaz.

A usernek ezt kell gyorsan ertenie:

1. mit szerkeszt most
2. melyik adat canonical
3. melyik ertek csak preview vagy runtime
4. hogyan hat a song szintu transpose/capo a readerre

A feluletnek a meglovo mockok nyelvet kell kovetnie:

- topbar + reviewer controls
- surface-based layout
- badge / pill alapu metadata
- state switcher a fobb szemelyes latvany- es workflow-szcenariokhoz

## Editing Model

### Canonical Song Data

A szerkesztes a song-owned adatokat kezeli:

- title
- artist
- key signature
- tempo
- tags
- chordpro source
- egyeb, mar letezo strukturalt metadata mezok

### Two-Level Transpose And Capo

Ez a slice ket szintet kulonit el:

- song-owned base values
- reader runtime values

Az editor csak a song-owned base values szerkeszteset vegzi.
A runtime transpose/capo nem valtozik itt direktben, csak preview-ban latszik, hogy a song mentett ertekei milyen reader viselkedest eredmenyeznek.

UI szabalyok:

- a song-level transpose es capo lathato, szerkesztheto, es canonical song settingkent jelenik meg
- a reader preview az effective ertekeket mutatja, nem a belso delta-t
- a feluletnek el kell valasztania a "stored setting" es a "resulting reader state" fogalmat

### Source And Metadata Relationship

A feluletnek tisztanak kell maradnia abban, hogy:

- a title / metadata mezok strukturalt song data
- a chordpro source a canonical szoveges forras
- a transpose / capo beallitasok a songhoz kotottek, de a preview az olvaso oldali ertekekre utal

Ha a forras es a strukturalt mezok kozott szinkron kell, azt a kesobbi implementacios tervnek kell pontositania. Ez a spec csak a vizualis es szerkesztesi modellt rogzi.

## Layout Direction

### Recommended Shape

A javasolt elrendezes egy haromreszes workspace:

- bal oldalt song summary es metadata
- kozepen canonical edit form / source editor
- jobb oldalt live reader preview vagy transpose/capo feedback panel

Ez a felosztas azert jo, mert egyszerre mutatja a szerkesztett adatot es a hatasat.

### Responsive Behavior

Wide es tablet layoutnak ugyanazt a mental modellt kell tartani:

- wide: teljes harom oszlopos workspace
- tablet: a kulso panelek osszecsukhatok vagy alacsonyabb prioritasuak, de a canonical edit + preview kapcsolat maradjon lathato
- compact: a workspace egy oszlopban, szekvencialis panelokkal menjen tovabb

## State Model

A mocknak es kesobbi UI-nak ezekre a states-re kell tudnia reagalni:

- default
- loading
- empty song
- read-only
- unauthorized
- pending mutation
- conflict
- validation error
- parse warning
- offline cached

### State Meanings

- `read-only`: a song megnyithato, de edit disabled
- `unauthorized`: backend-enforced write deny
- `pending mutation`: local-first valtozas var syncre
- `conflict`: canonical backend state eltert a local edit baseline-tol
- `validation error`: form vagy source hibas
- `parse warning`: a source valid, de reader preview figyelmeztet

## Mock Requirements

Kell egy repository-owned prototype a `docs/prototypes/` mappaban, ugyanazzal a mintaival, mint a tobbi mock:

- `song-editing-mockup.html`
- `song-editing-mockup.css`
- `song-editing-mockup.js`

A mock tartalmazza:

- reviewer controls
- screen switch a detail/edit/preview szemlelethez
- layout switch wide/tablet/compact
- theme switch standard/high-contrast/black
- state switch a fenti state modelhez
- edit form title, metadata, source, transpose, capo mezokkel
- live preview panel, ami mutatja az effective transpose/capo eredmenyet
- clear save/cancel/save-error visszajelzes

## Implementation Boundaries

- A slice nem vezet be uj auth szabalyokat.
- A slice nem valtoztat backend ownership modelt.
- A slice nem oldja meg a teljes chord source editor engine-t.
- A slice nem keveri ossze a runtime reader controlokat a song-level edit mezokkel.

## Acceptance Criteria

1. A spec tisztan kulon kezeli a song-level base transpose/capo es a reader runtime transpose/capo szerepet.
2. A title, metadata, chord source, transpose, es capo egy workspace-ben latszik.
3. A felulet canonical edit es preview kapcsolatot mutat, nem csak mezoket.
4. A mock illeszkedik a meglovo `docs/prototypes/` vizualis nyelvhez.
5. A mock tud state es layout valtasokat.
6. A song edit UI nem allit fel uj backend auth vagy write szabalyokat.
7. A kesobbi implementacios plan a spec alapjan meg tudja kulonboztetni a presentation-only es a durable domain valtozasokat.

## Documentation Impact

Ez a slice frissiti:

- `docs/prototypes/song-editing-mockup.html`
- `docs/prototypes/song-editing-mockup.css`
- `docs/prototypes/song-editing-mockup.js`
- `docs/plans/` az implementacios tervvel
- `docs/domain/domain-model.md` csak akkor, ha a vegleges implementacios terv uj, tartos song-mezot vagy uj transzpose/capo tarolasi szabalyat vezet be
