# Spec: Header Consistency and Sync Presentation

**Date:** 2026-06-06
**Status:** Approved

## Problem

Authenticated workspace headers drifted into three inconsistent patterns and a
few visual breakages on phone-width viewports:

- **Song library** (`song_list_screen.dart`) used a Material `AppBar` whose
  `actions:` row does not wrap. With five text-button actions (sync status,
  Import, Add song, Plans, Sign out) plus the title, the row overflowed and
  `Sign out` clipped off-screen.
- **Plan list / plan detail** (`PlanningWorkspaceShell`) used a custom header
  whose `< 640px` branch stacked the actions onto their own right-aligned row,
  far below the title, leaving a large empty gap that read as "fallen apart".
- The header sync control rendered as a `dot + "Synced" label + secondary
  text`, styled like the surrounding text buttons, so the ambient status read
  as a tappable action and mixed with navigation.
- Three different concept classes (sync status, screen actions, global
  navigation) shared one undifferentiated row of green text buttons.
- The **song create/edit workspace** also showed the header sync control
  (`UnifiedSyncHeaderControl`) beside `Cancel`/`Save`, where it floated to an
  odd position and duplicated the persistence signal that `Save` and the dirty
  state already provide.

## Decision

Converge every authenticated non-reader header on one compact, consistent
pattern, and separate the three concept classes visually.

1. **Sync status is presentation-only as a dot.** The control renders a single
   colored status dot; the status word (`Synced` / `Unsynced` / `Conflict`) and
   secondary connectivity/freshness detail move to the tooltip and the existing
   status popup. Tap still opens the popup. Color stays the primary signal.
2. **Screen actions become icon buttons with tooltips**, never text buttons in
   the header. Rare/secondary actions collapse into a `⋮` overflow menu so the
   row never overflows.
3. **Song library header layout:**
   - sync dot
   - `Plans` is a primary, always-visible icon action (`event_note_outlined`) —
     planning is part of the default workspace, not buried in a menu
   - `Add song` icon (capability-gated via `IfCapability` on `editSongs`)
   - overflow `⋮` menu: `Import` (capability-gated on `editSongs`) and
     `Sign out`
4. **Planning header layout** (`PlanningWorkspaceShell`) collapses to a single
   row always: back button + title (+ subtitle) in an `Expanded`, then the
   compact actions (sync dot + icon buttons) right-aligned on the same line. The
   `< 640px` stacking branch is removed because the actions are now compact
   icons that fit on one line even on phones.
5. **The song create/edit workspace no longer shows the header sync control.**
   Its explicit `Cancel`/`Save` affordances and dirty state already communicate
   local persistence intent.

Authorization behavior is unchanged: visible icons and the overflow `Import`
item stay gated by `IfCapability` / the capability resolver as a UX affordance
only; the backend remains the enforcement boundary.

## Supersedes

- The header sync control's `dot + label + secondary text` presentation from
  [2026-05-29-sync-ui-consolidation.md](2026-05-29-sync-ui-consolidation.md)
  (now dot + tooltip).
- The inclusion of the song editor in the header-sync-control surface list from
  [2026-05-02-song-editing-ui.md](2026-05-02-song-editing-ui.md) and
  [2026-05-29-sync-ui-consolidation.md](2026-05-29-sync-ui-consolidation.md)
  (editor no longer shows the control).

The canonical living contract is updated in
[sync-ux-contract.md](../product/sync-ux-contract.md). Older dated specs are not
rewritten; they keep their historical decisions and a forward pointer to this
spec.

## Out of Scope

- Bottom navigation or an account menu as a separate global-navigation layer
  (considered, deferred — `Plans` as a primary header icon satisfies the
  current need).
- Iconifying or restructuring the reader header.
- Any change to sync semantics, the status popup contents, or recovery actions.

## Verification

- `flutter analyze` clean.
- `flutter test` green, including updated widget tests that locate header
  actions by tooltip / overflow menu instead of inline text.
