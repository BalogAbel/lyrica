# Mobile And Tablet Reader Navigation Spec

> Status: Implemented

## Goal

Tegyük a Lyrica song reader navigációját platformhelyessé Androidon és iOS-en úgy, hogy a jelenlegi full-screen reader modell megmaradjon telefonon és tableten is.

## Scope

- A song list maradjon a signed-in olvasási flow gyökérképernyője.
- A song reader maradjon külön részletnézet.
- A song listből a song readerbe történő navigáció valódi előrelépés legyen, ne puszta route-csere.
- A song readerből a felhasználó egyértelműen vissza tudjon térni a song listára.
- A song reader UI tartalmazzon látható vissza affordance-ot.
- Androidon a rendszer back a song readerből a song listára vigyen vissza.
- Ha a felhasználó közvetlenül a song reader route-ra érkezik, és nincs visszalépési verem, a readerből történő visszalépés a song listára vigyen.
- A tablet használat elsődleges maradjon full-screen reader modellben.

## Non-Goals

- Nincs master-detail vagy split view bevezetés ebben a slice-ban.
- Nincs becsúszó vagy overlay song list.
- Nincs új tablet-specifikus többpaneles layout.
- Nincs reader workflow vagy információs architektúra áttervezése.
- Nincs új dalválasztási mechanika a readeren belül.
- Nincs változás az auth, offline cache, vagy backend authorization boundary működésében.

## Product Slice Summary

A jelenlegi app flow funkcionálisan a song list és a song reader köré épül, de a navigáció nem viselkedik platformhelyesen. Androidon a system back a readerből kilép az alkalmazásból ahelyett, hogy visszatérne a listára. iOS-en nincs hardveres back, ezért a reader képernyőn jelenleg nem adott egyértelmű visszaút.

Ez a slice nem új layout-rendszert vezet be tabletre. A cél a meglévő signed-in olvasási flow navigációs korrekciója úgy, hogy a reader továbbra is teljes képernyős maradjon, és a későbbi side sheet vagy split view fejlesztés lehetősége nyitva maradjon.

## User Flows

### Signed-In Song Browsing

1. A felhasználó sikeresen bejelentkezik vagy visszaállított sessionnel indul.
2. Az app a song list képernyőt mutatja.
3. A song list a signed-in olvasási flow gyökérképernyője.

### Open Song Reader

1. A felhasználó kiválaszt egy dalt a listából.
2. Az app megnyitja a song reader részletnézetet.
3. A reader külön navigációs szintként viselkedik a song list fölött.

### Return From Song Reader

1. A felhasználó a readerben a látható vissza affordance-ot használja, vagy Androidon megnyomja a rendszer back gombot.
2. Ha van előzmény a navigációs veremben, az app visszalép a song listára.
3. Ha nincs előzmény a navigációs veremben, az app history-replace jelleggel a song list route-ra tér vissza, nem pedig újabb song list bejegyzést push-ol a reader fölé.

### Root-Level Exit Behavior

1. A felhasználó a song list képernyőn van.
2. Innen nincs külön vissza affordance.
3. Androidon a rendszer back a platform szokásos root-szintű viselkedését követi.

## UX Requirements

### Song List

- A song list maradjon egyszerű gyökérképernyő.
- A song list UI ne mutasson vissza affordance-ot.
- A song listből a readerbe való átmenet továbbra is közvetlen és gyors maradjon.

### Song Reader

- A song reader mindig egyértelműen elhagyható legyen.
- A readeren legyen látható vissza affordance.
- A vissza affordance jelentése egyértelműen a song listára való visszatérés legyen.
- A reader teljes képernyős maradjon tableten is.
- A visszanavigáció ne kényszerítse a felhasználót rejtett gesztusokra vagy platformismeretre.
- A reader full-screen navigációs modellje nem távolíthatja el a korábban specifikált tartós online, offline, refreshing, vagy refresh-failed állapotjelzéseket a reader élményből.

### Tablet Behavior

- A tablet primary olvasási modell ebben a slice-ban teljes képernyős reader marad.
- A spec nem követel meg állandóan látható listát a reader mellett.
- A mostani megoldás ne zárja ki, hogy később side sheet, overlay lista vagy split view készüljön.

## Routing And Navigation Requirements

### Navigation Model

- A song list -> song reader átmenet a felhasználó számára valódi előrelépésként viselkedjen.
- A song reader route nem cserélheti le úgy a song list route-ot, hogy közben megszűnjön a természetes visszalépés lehetősége.
- A readerből történő visszalépés elsősorban `pop` alapú legyen, amikor van mit visszalépni.

### Fallback Return Behavior

- Ha a song reader közvetlen route-belépéssel nyílik meg, és nincs visszalépési verem, a readerből való visszalépés a song list route-ra vigyen.
- Ez a fallback visszatérés history-replace vagy azzal egyenértékű viselkedés legyen, ne új push a reader route fölé.
- A fallback viselkedés nem eredményezhet üres képernyőt, kilépést, vagy hatástalan back akciót.
- A fallback viselkedés nem hozhat létre back loopot, ahol a felhasználó a song list és a közvetlenül nyitott reader között reked.

### Auth Boundary

- A signed-in route policy változatlan marad.
- A signed-out felhasználó továbbra sem érheti el a song list vagy song reader route-okat.
- A navigációs korrekció nem gyengítheti a központosított auth redirect szabályokat.

## Platform Expectations

### Android

- A rendszer back a song readerből visszavigyen a song listára.
- A rendszer back a song list gyökérszintjén a platform szokásos viselkedését kövesse.
- A readerből történő back ne zárja be az appot, ha a song listára való visszatérés értelmesen lehetséges.

### iOS

- A song reader képernyőn legyen látható, natívnak érződő vissza affordance.
- A felhasználó ne maradjon a readerben egyértelmű kilépési út nélkül.
- A navigációs minta illeszkedjen az iOS elvárásához, ahol a részletnézetből látható UI-n keresztül kell tudni visszatérni.

## Deep Linking Expectations

- A song reader route továbbra is maradhat közvetlenül címezhető.
- Közvetlen belépés esetén is biztosított legyen az értelmes visszatérés a song listára.
- A deep link nem teheti a readert zsákutcává.

## Testing Requirements

TDD kötelező az implementációhoz.

### Widget Tests

Fedjék le:

- a song listből a readerbe történő navigációt
- a reader vissza affordance meglétét
- a readerből a listára való visszatérést
- azt az esetet, amikor a reader fallback módon a listára tér vissza, mert nincs pop-olható előzmény

### Integration Tests

Fedjék le:

- signed-in flow: song list -> reader -> vissza a listára
- session-restore flow mellett is helyes reader navigáció
- közvetlen reader route belépésből történő visszatérés a listára

### Regression Coverage

- A változás nem törheti meg a jelenlegi auth redirect viselkedést.
- A változás nem törheti meg a local-first authenticated reader flow-t.
- A változás nem változtathatja meg a song list root státuszát.

## Success Criteria

- Androidon a song readerből a back akció visszavisz a song listára, nem lépteti ki az appot.
- iOS-en a song readerből látható UI affordance-szal vissza lehet térni a song listára.
- A song list marad a signed-in olvasási flow gyökérképernyője.
- A reader továbbra is teljes képernyős marad telefonon és tableten.
- Közvetlen reader route belépés esetén sincs navigációs zsákutca.
- A megoldás nem kényszerít most master-detail bevezetésére, de nem is zárja ki annak későbbi bevezetését.
