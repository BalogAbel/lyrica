# Song Key Reader Residuals

**Slice:** feat/song-key-reader (S3 PR 3; found by the final adversarial
review on 2026-10-21)
**Related:** `docs/specs/2026-10-13-personal-song-settings.md` (PS5, PS9,
PS25, PS26), ADR-042, `docs/deferred/2026-10-14-key-edit-residuals.md`
**Files:**
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- `apps/lyron_app/lib/src/router/slug_route_resolvers.dart`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/`
- `apps/lyron_app/test/support/tolerant_golden_comparator.dart`

The review found one regression (the plan reader remounted on a catalog
refresh and dropped the temporary key) and one cross-item bug (the plan-key
write guard); both are fixed in the PR. These are the residuals it rated
non-blocking. None loses or writes a wrong value: each ends in a no-op, a
benign duplicate, or a cosmetic gap.

**Triage (2026-10-21):** none is scheduled. Revisit each at its trigger.

## R1. Save re-enables for a few frames before the plan detail reloads

**What.** After `setSessionItemKey` returns, the in-flight marker clears and
Save to plan can enable again for 1-3 frames, until the invalidated plan
detail reloads and the temporary value, now equal to the plan value, is
pruned. A double tap in that window sends an identical edit; the PS14 fold
merges it (one extra no-op send).

**Why deferred.** Benign: the edit is idempotent and folds.

**Where.** `_runPlanKeyWrite` in `song_reader_screen.dart`: await the next
`planningPlanDetailProvider(planId).future` before clearing the item's
marker.

**Trigger.** A report of a doubled sync row, or a change to the fold.

## R2. The `±` and Save closures capture build-time layers

**What.** `_keyStep` (the `±` buttons) and the Save closure capture the layers
of the build that created them. A tap in the roughly one frame between a
prune or a plan change and the rebuild computes from stale layers. It can
store a temporary value equal to the new plan value, which a later plan
change would revive.

**Why deferred.** A one-frame window, and the result is a visible, resettable
temporary value, not a wrong write.

**Where.** `_keyStep` and `_keyActionsFor` in `song_reader_screen.dart`:
re-read the current reader state and plan item inside the callbacks.

**Trigger.** A field report of a value that "came back", or any change that
lengthens the frame between a plan change and the rebuild.

## R3. The piano view enables Reset and Save for the hidden capo

**What.** In the piano view the capo controls are hidden, but Reset (and Save
to plan) enable when only the capo is temporary. This is what PS26 specifies
(Save and Reset act on both fields whatever the instrument view), yet every
visible label reads `Song` or `Plan`.

**Why deferred.** Spec-mandated; a design question, not a bug.

**Where.** `_keyActionsFor` in `song_reader_screen.dart`; the PS26 "Save
sequence" bullet.

**Trigger.** UX feedback from a musician using the piano view.

## R4. The library reader remounts on a catalog refresh

**What.** `SongSlugRouteResolver` (the library route) uses `songsAsync.when`
without keeping data on a reload. A catalog refresh swaps the reader for a
loading scaffold and remounts it, which drops the library reader's temporary
key. The plan reader no longer does this (fixed in the PR).

**Why deferred.** Pre-existing, not a regression of this PR; the library
reader was not changed here.

**Where.** `SongSlugRouteResolver.build` in `slug_route_resolvers.dart`: show
the scaffold only while there is no previous value (`skipLoadingOnReload`,
`skipError`), as `PlanSessionSongSlugRouteResolver` does.

**Trigger.** The next change to the library route, or a report of a lost
temporary key in the library reader.

## R5. The expanded tools panel at large text scale

**What.** At about 2.5x text scale or in a very short window, the expanded
tools panel's label row overflows (a `Row`), and its `Card` has no scroll. The
compact rail's caption height holder also grows with the text scale.

**Why deferred.** Extreme settings; the panel is unchanged below them.

**Where.** `widgets/song_reader_expanded_tools_panel.dart` (label row, card
scroll) and `widgets/song_reader_control_rail.dart` (caption holder).

**Trigger.** Accessibility feedback, or a text-scale pass over the reader.

## R6. Golden coverage limits

**What.** The goldens run on the Ahem test font, whose geometry differs from
production. The tolerant comparator allows 0.5% of pixels, so a single
compact icon state flip falls below it and is pinned by widget tests instead.
The comparator itself has no unit test.

**Why deferred.** The widget tests cover the state; the goldens cover layout.

**Where.** `test/support/tolerant_golden_comparator.dart`,
`test/presentation/song_reader/widgets/song_reader_key_controls_golden_test.dart`
and `docs/testing/testing-strategy.md` (under `apps/lyron_app`).

**Trigger.** A golden that passes a visible regression, or a change to the
comparator.

## R7. The manual device check of the reader was not run

**What.** Step 3 of Task 8 in `docs/plans/2026-10-20-song-key-reader.md`
(running the reader on a device or browser and exercising the key controls)
was not run in the implementing sessions: the browser pane refused the local
app URL.

**Why deferred.** The widget tests and goldens cover the behavior; the check
is a final confidence pass.

**Where.** The plan's Task 8 Step 3.

**Trigger.** Before the PR merges, or at the next manual reader pass.
