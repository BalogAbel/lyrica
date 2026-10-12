# Sync Popup Is Not Usable at a 360 px Phone Width

**Found:** 2026-10-12, by CP4 of S6a
(`docs/specs/2026-10-12-sync-and-account-feedback.md`).
**Related:** `docs/product/sync-ux-contract.md` (header status popup, recovery
actions), `docs/plans/2026-10-01-delivery-roadmap.md` (hotspot "S6a ↔ S3
(PR 2): the unified sync popup").

**Files:**
- `apps/lyron_app/lib/src/presentation/sync/unified_sync_status_popup.dart`
  (the header `Row`, `_SongRowTile`, `_PlanRowTile`)
- `apps/lyron_app/test/presentation/sync/unified_sync_status_popup_test.dart`
  (CP4, the width model)

**Status:** pre-existing; S6a is copy only and left the layout unchanged. Not
implemented.

## Problem

At a 360 px wide phone the popup's fixed-width controls fill the dialog and
leave the title and the chips no width:

- the header `Row` holds the title in an `Expanded` plus **Discard all** (shown
  only while there is unsynced work) and **Sync now** (a filled button with an
  icon and a label). Together the two buttons take most of the dialog's
  content width, so the title is squeezed to nothing;
- a conflict row puts **Keep mine** and **Discard mine** in the `ListTile`'s
  `trailing`. The `trailing` takes its natural width first, so the title and
  the chips of the row get what is left, which is close to zero.

The reason chips of S6a are sentences, so they need more width than the old
code-shaped chips did. CP4 therefore models a 412 px phone with text scaled by
0.55 (the test font is about twice as wide as a real glyph) and passes. At
360 px the same model leaves no usable width. It is a width model, not a device
measurement; the manual device check of S6a looks at the popup on a real phone.

## Fix sketch

Layout work only:

- let the header wrap: title on its own line, the two buttons on a second line
  (a `Wrap`, or a column below a width threshold);
- move a conflict row's action buttons out of `trailing` into the row body,
  under the chips, so the title and the chips keep the full row width.

## Requirements for the slice that picks this up

- No change to which actions a row offers: **Keep mine** stays suppressed for
  `authorizationDenied` (ADR-035 D5.6) and **Discard mine** stays.
- Keep the `ValueKey`s of the buttons; the popup tests find them by key.
- Extend CP4 with a 360 px case under the same text-scale model.

## Trigger

S3 PR 2, which integrates the personal layer into the sync overview and so
extends the popup (the roadmap lists the popup as a hotspot between S6a and S3
PR 2), or a field report of an unreadable popup on a small phone.

Roadmap (2026-10-12): trigger-gated (S9); S3 PR 2 picks it up.
