# Song Reader Landscape Shell Alignment Plan

> Status: Implemented

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the landscape/expanded reader shell with the immersive compact direction by moving title ownership and management actions into the app bar, and by making scoped set-context navigation interactive and scoped-only.

**Architecture:** Keep reader core state and controller behavior shared. Constrain all changes to `presentation/song_reader/` shell widgets and visibility rules. Preserve the existing expanded tools/content layout while changing only header chrome and scoped-context interaction behavior.

**Tech Stack:** Flutter, Material 3, Riverpod, flutter_test

---

### Task 1: Move Expanded Header Title To Current Song

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Test: `apps/lyron_app/test/router/app_router_test.dart`

- [x] **Step 1: Add failing tests for expanded app-bar title**

Cover:

- expanded success state app bar shows current song title
- expanded success state no longer shows generic `Song reader`
- expanded success state no longer duplicates the title inside content chrome
- expanded success state does not render subtitle metadata separately
- loading and error states still allow safe fallback title behavior where required

- [x] **Step 2: Implement expanded title ownership**

Use the same current-title resolution path already used for compact shell and apply it to expanded success state app-bar title behavior. Remove the duplicate expanded title bar and do not render subtitle metadata as separate expanded chrome.

- [x] **Step 3: Re-run affected tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart \
  apps/lyron_app/test/router/app_router_test.dart
```

Expected: PASS.

### Task 2: Move Expanded Edit/Delete Into Overflow

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`

- [x] **Step 1: Add failing tests for expanded action placement**

Cover:

- expanded success shell no longer shows standalone `Edit song` / `Delete song` buttons
- overflow menu contains `Edit song` and `Delete song`
- overflow selection still triggers existing edit/delete flows

- [x] **Step 2: Implement overflow-only expanded actions**

Remove standalone expanded action row and reuse the shared app-bar overflow action model for expanded success state.

- [x] **Step 3: Re-run focused tests**

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: PASS.

### Task 3: Make Expanded Set Context Interactive And Scoped-Only

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Test: `apps/lyron_app/test/router/app_router_test.dart`

- [x] **Step 1: Add failing tests for expanded scoped context behavior**

Cover:

- expanded `Set context` panel hidden for unscoped reader
- expanded `Set context` panel visible for scoped reader
- expanded left rail spacing stays stable even when the panel is hidden
- previous/next context areas are full tappable segments
- expanded previous/next interaction performs existing scoped navigation

- [x] **Step 2: Implement interactive expanded set-context panel**

Use existing scoped navigation availability and route replacement behavior as source-of-truth. Keep layout differences presentation-only:

- compact: bottom context bar
- expanded: left set-context panel

Keep the expanded left rail width reserved even when the panel content is hidden so scoped and unscoped layouts stay horizontally aligned.

- [x] **Step 3: Re-run focused tests**

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: PASS.

### Task 4: Documentation Alignment

**Files:**
- Modify: `apps/lyron_app/README.md`
- Modify: `docs/specs/2026-04-16-song-reader-tablet-immersive-shell.md`
- Modify: `docs/plans/2026-04-16-song-reader-tablet-immersive-shell.md`
- Modify: `docs/specs/2026-04-17-song-reader-landscape-shell-alignment.md`
- Modify: `docs/plans/2026-04-17-song-reader-landscape-shell-alignment.md`

- [x] **Step 1: Update repository-owned documentation**

Document that:

- compact and landscape now share title-in-app-bar behavior
- expanded title is no longer duplicated inside content chrome
- compact and landscape both use overflow-based edit/delete actions
- scoped navigation chrome is shell-specific but scoped-only in both shells

- [x] **Step 2: Mark supersession clearly**

Keep the 2026-04-16 slice as implemented history while marking the new landscape refinement as the follow-up planned slice.

### Task 5: Verification

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Modify: `apps/lyron_app/test/router/app_router_test.dart`

- [x] **Step 1: Run focused reader and router tests**

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart \
  apps/lyron_app/test/router/app_router_test.dart
```

- [x] **Step 2: Run repository verification script**

```bash
./scripts/verify.sh --skip-migrations
```

- [x] **Step 3: Confirm no architectural regressions**

Checklist:

- shared reader core untouched for domain behavior
- compact/expanded split remains presentation-shell only
- expanded shell still does not use compact overlay
- scoped/unscoped runtime-state parity preserved
