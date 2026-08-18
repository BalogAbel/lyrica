# ADR-034: Reader Chrome Model

- Status: Accepted
- Date: 2026-08-18
- Spec: `docs/specs/2026-08-09-song-presentation.md` (sections 6 and 7)
- Scope: the song reader's **compact** shell — `song_reader_compact_surface.dart`, `song_reader_shell.dart`, `song_reader_screen.dart`, and the chrome widgets `song_reader_top_bar.dart`, `song_reader_bottom_bar.dart`, `song_reader_control_rail.dart`, `song_reader_chrome_metrics.dart`. The expanded shell (>= 1600 logical px, `song_reader_expanded_*.dart`) is explicitly OUT of scope and keeps its current chrome.

## Context

The reader is used on stage, on a tablet in portrait, by someone whose hands are on an instrument. The thing that matters is how much of the song is on screen and how predictable the controls are.

Before this change the compact shell spent 195 logical pixels of an 1194px-tall tablet viewport on chrome: a 52px `Scaffold.appBar`, plus a control bar and a bottom context bar with their gaps totalling 143px, all of them siblings of the content inside one `Column`. That left 999px for the song.

Being siblings had a second, worse consequence. The fit calculation's available height is measured by a `LayoutBuilder` inside the `Expanded` that held the content, so revealing the control bar *shrank the measured area*, and hiding it grew it back. `resolveFitFontScale` picks the largest font scale whose **estimated** height fits that measurement (see ADR-033 and the estimator's one-sided `estimated >= rendered` contract). A measurement taken in one chrome state and used in another is a measurement that is too large, and a too-large available height is exactly how fit-to-screen overflows — the failure the feature exists to prevent. Nothing looks broken when it happens; the song simply starts running off the bottom at some font scales and not others.

## Decision

Three surfaces, with three different persistences.

**The bottom bar is always visible and occupies layout space.** 64px on tablet, 58px on phone, plus the home-indicator safe-area inset. It carries what a musician needs mid-song without thinking: the current title, key, capo and — when plan-scoped — the set position (`3 / 7`) and the previous/next items. On a phone the neighbour titles are dropped and only the chevrons remain; there is no width for both. In catalogue mode there are no neighbours at all, so no neighbour slot is rendered. Capo appears only when `isCapoDirectiveVisible`.

**The top bar and the control rail are hidden by default, revealed by tapping the content, and float over it.** The top bar carries back, the title, the recoverable-warnings indicator and the overflow menu. The rail carries transpose, capo and font size as vertical groups at the right edge. One tap reveals both; a second tap dismisses both.

**Both floating surfaces are excluded from the fit calculation's available height.** This is the load-bearing part of the decision. The compact surface is

```
Column[ Expanded(Stack[content, top bar, rail]), bottom bar ]
```

and the content is the **only non-positioned child of that `Stack`**. A `Stack` sizes itself to its non-positioned children, so the two `Positioned` overlays cannot influence the constraints the content's `LayoutBuilder` sees. Revealing the chrome is provably free of geometric consequence, and `song_reader_chrome_geometry_test.dart` asserts it by exact equality on both the fit input and the rendered content rect. On the old tree that test measured 1054.0 hidden against 982.0 revealed; it now measures 1070.0 in both states.

The `Scaffold.appBar` is gone for the compact shell, which is where most of the recovered space comes from.

**There is no idle auto-hide.** On stage, predictability beats tidiness: a control must not vanish while someone is reaching for it. The chrome changes state only when the user asks it to.

**Each surface consumes the safe-area inset it sits against**, replacing the blanket `SafeArea` that used to wrap the whole reader body. A bar that must be `58 + home-indicator inset` cannot sit inside an ancestor that has already spent the inset. The bottom bar reads `MediaQuery.viewPaddingOf(...).bottom` and grows downwards, so the inset is space under the bar rather than labels pushed off-centre; the top bar takes the top inset; the rail's offset adds the right inset so a landscape notch cannot land on it. Content runs edge to edge underneath the overlays.

### Platform conformance

Checked against Apple's current Human Interface Guidelines rather than assumed:

- *Toolbars* places navigation at the top with the element that returns to the previous view at the leading edge, and requires the standard back symbol rather than a "Back" text label. A back control in the bottom bar was therefore rejected, and the top bar uses `BackButtonIcon`. This is an HIG convention rather than an App Review criterion; the practical risk it avoids is the conflict with the system's left-edge back gesture and with user expectation.
- *Going full screen* (updated June 2025) endorses temporarily hiding toolbars when content is the focus, provided they restore by a familiar action such as tapping and provided controls **essential to navigation** stay visible. Previous/next are essential during a service and stay in the fixed bottom bar. Back is not needed mid-song and may hide; iOS's left-edge back gesture keeps it reachable while the top bar is down.

### The title is duplicated on purpose

The song title appears in both the top bar and the bottom bar. An empty title area was rejected by the product owner. This is recorded here, and in a comment on the widget, because it reads as an oversight and will otherwise be "fixed".

### Two consequences worth naming

**Double-tap-to-fit is disabled while the chrome is revealed.** The reveal overlays share a `GestureDetector` with the surface's own double-tap recognizer, and an ambient `DoubleTapGestureRecognizer` paired a tap meant to reopen the overflow menu with the tap that had opened it, so the menu silently failed to reopen. Double-tap-to-fit only means anything over content, and one tap dismisses the chrome, so gating it on the chrome being hidden is the correct rule rather than a workaround. The cost is real but small: a user who wants to re-fit while the chrome is up taps once to dismiss first.

**The non-data states get a plain chrome frame, not the overlay model.** Moving the top bar into the reveal initially left the loading view and every ADR-023/024 error state — unavailable song, access denied, retryable backend failure, preserved-title tombstone, unresolved remote-delete conflict, unavailable planning context — with no back control at all, because the overlay only exists inside the surface that renders song content. Those states now render as `Column[top bar, Expanded(status view), bottom bar]` with the top bar **permanently visible**: tap-to-reveal exists so song content can have the screen, and these states have no song content to give it to.

## Consequences

- The compact shell's chrome is a flat 64px instead of 195px. Revealing the chrome no longer changes the content geometry at all, which is what makes the fit estimator's available height trustworthy across chrome states.
- Reader chrome now reads its colours from `ReaderTheme` (`floatingChromeBackground`, taken from the "floating rail surface" values the spec's section 5 already defines) instead of the ambient `ColorScheme`, closing the deferral ADR-033 recorded against PR4.
- The chrome model applies to the compact shell only. The expanded shell has the width to show its panels permanently, and the stage problem this slice exists to solve is a tablet-portrait problem. Converging the two shells is its own slice.
- The rail assumes a right-handed grip. A mirroring setting is deliberately deferred until the layout has been used rather than guessed at now.
- `SongReaderChromeMetrics` carries bar heights only, never the safe-area inset, so the bars stay testable without faking a `MediaQuery` per case. The bars add the inset themselves and size themselves accordingly; callers must not wrap them in a `SizedBox`.
- The 600px phone/tablet breakpoint is `readerRegularTypeScaleMinWidth` (`reader_theme.dart`), the same constant the type scale resolves through. It was not re-declared for the chrome: one definition per value, and the chrome and the type scale cannot disagree about what a phone is.
