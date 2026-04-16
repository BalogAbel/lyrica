# Song Reader Tablet Immersive Shell Plan

> Status: Implemented

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a compact/tablet immersive reader shell with minimal fixed chrome, menu-based edit/delete actions, and scoped-only bottom navigation context.

**Architecture:** Keep reader core state and controller behavior shared. Implement all behavior differences in `presentation/song_reader/` shell composition and widget visibility rules. Preserve scoped/unscoped parity for runtime state while narrowing where scoped navigation chrome is rendered.

**Tech Stack:** Flutter, Material 3, Riverpod, flutter_test

---

### Task 1: Lock Header Behavior To Immersive Compact/Tablet Shell

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_header.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`

- [x] **Step 1: Add failing tests for compact/tablet header contract**

Cover these expectations:

- header renders back affordance and current song title
- header renders overflow menu trigger (`...`) in compact/tablet shell
- generic "Song reader" title is not shown in loaded compact/tablet reader state

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: FAIL before implementation.

- [x] **Step 2: Implement compact/tablet header chrome**

Update header composition so compact/tablet reader shell always uses:

- back
- song title
- overflow menu trigger

Keep expanded-shell behavior unchanged unless tests require explicit shared behavior.

- [x] **Step 3: Re-run screen tests**

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: PASS for this scope.

### Task 2: Move Edit/Delete Into Overflow Menu

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`

- [x] **Step 1: Add failing tests for action placement**

Cover:

- compact/tablet shell does not show standalone edit/delete buttons
- overflow menu contains `Edit song` and `Delete song`
- selecting menu actions triggers existing edit/delete flows

- [x] **Step 2: Implement overflow-only action affordance for compact/tablet**

Remove standalone compact/tablet action buttons from content chrome and surface them through overflow menu only.

- [x] **Step 3: Re-run tests**

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: PASS.

### Task 3: Scope Bottom Context Bar Visibility And Navigation Placement

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_bottom_context_bar.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_bottom_context_bar_test.dart`

- [x] **Step 1: Add failing tests for visibility rules**

Cover:

- top previous/next row does not render in compact/tablet shell
- bottom context bar renders only in scoped sequence context
- bottom context bar hidden in unscoped and no-song states
- bottom previous/next taps still perform existing scoped navigation
- bottom previous/next segment containers are fully tappable hit targets, not text-only actions

- [x] **Step 2: Implement scoped-only bottom context policy**

Use existing scoped navigation availability logic as source-of-truth and apply it to bottom bar visibility.

- [x] **Step 3: Re-run affected tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_bottom_context_bar_test.dart
```

Expected: PASS.

### Task 4: Remove Reader-Level Catalog Connectivity Surface

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`

- [x] **Step 1: Add failing test for catalog-status absence**

Cover:

- reader screen no longer renders online/offline catalog status surface in compact/tablet and expanded success states

- [x] **Step 2: Remove catalog status surface from reader success shell**

Keep load/error/access-denied/not-found handling intact while excluding connectivity status chrome from normal reader display.

- [x] **Step 3: Re-run screen tests**

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: PASS.

### Task 5: Full Verification

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_header.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_bottom_context_bar.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_bottom_context_bar_test.dart`

- [x] **Step 1: Run focused reader test suite**

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_bottom_context_bar_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_compact_overlay_test.dart
```

- [ ] **Step 2: Run repository verification script**

```bash
./scripts/verify.sh --skip-migrations
```

- [x] **Step 3: Confirm no architectural regressions**

Manual review checklist:

- shared reader core untouched for domain behavior
- compact/expanded split remains presentation-shell only
- expanded shell does not use compact overlay
- scoped/unscoped runtime-state parity preserved
