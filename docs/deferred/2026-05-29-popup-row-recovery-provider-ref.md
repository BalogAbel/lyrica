# Deferred: Popup row recovery actions — WidgetRef lifetime

**Date:** 2026-05-29  
**Relates to:** `feat/sync-ui-consolidation` (PR #44)

## Problem

`_SongRowTile._keepMine`, `_SongRowTile._discardMine`, and `_PlanRowTile._applyToGroup`
in `unified_sync_status_popup.dart` run async operations using the popup widget's
`WidgetRef`. If the user closes the popup while an operation is in-flight:

- `context.mounted` becomes false after the for-loop in `_applyToGroup`.
- The early return skips `planningDataRevisionProvider` bump and list invalidations.
- The mutations ARE committed to the local store, but the plan screens remain showing
  stale sync state until the next navigation/rebuild.

The same risk exists for song row actions: if the popup closes mid-keepMine/discardMine,
the `finally` block guards invalidations behind `context.mounted`, so they may be skipped.

## Root cause

Recovery actions are wired to the popup widget's transient `WidgetRef`. Invalidations
that keep non-popup screens fresh are tied to this short-lived ref.

## Desired fix

Move row recovery actions to a long-lived provider (similar to `UnifiedDiscardController`
/ `unifiedDiscardControllerProvider`). The provider's `ProviderRef` outlives the popup
widget, so invalidations always fire regardless of popup mount state.

## Scope

Medium — requires extracting `_keepMine`/`_discardMine` and `_applyToGroup` logic into
new controller(s) with `ProviderRef`-based invalidation, and wiring those providers into
the popup rows (similar to how `unifiedDiscardControllerProvider` is wired today).

## Workaround

Current behaviour: mutations persist to local DB. Stale UI resolves on next
navigation or when the affected provider is rebuilt for another reason.
