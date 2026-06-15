# Song Reader Immersive Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the compact song reader into a single immersive tap-toggle with a slim bottom icon control bar, move the view-mode toggle into the overflow menu, and surface the effective key + warnings in the AppBar.

**Architecture:** Reuse `SongReaderState.areCompactControlsVisible` as the single "reader-active" flag. When true, hide the system bars (Android immersive) and show a new bottom `SongReaderControlBar`; when false, restore the bars and hide the bar. The big top `Card` overlay is removed; the shared AppBar gains an effective-key subtitle, a warning action, and a view-mode menu item. The expanded (tablet) surface keeps its side tools panel but loses view-mode/key/warnings (now centralised).

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_test`. Working dir: `apps/lyron_app`. Run commands from `apps/lyron_app`.

Spec: `docs/specs/2026-06-14-song-reader-immersive-controls.md`

---

## File Structure

- `lib/src/presentation/song_reader/song_reader_projection.dart` — add `effectiveKey`.
- `lib/src/presentation/song_reader/widgets/song_reader_control_bar.dart` — NEW slim bottom icon bar.
- `lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart` — host the control bar; drop top overlay + view-mode plumbing.
- `lib/src/presentation/song_reader/widgets/song_reader_compact_overlay.dart` — DELETE.
- `lib/src/presentation/song_reader/widgets/song_reader_header.dart` — reduce to transpose/capo/font sections (still used by expanded panel).
- `lib/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart` — drop view-mode/key/warnings params.
- `lib/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart` — drop view-mode/key/warnings params.
- `lib/src/presentation/song_reader/song_reader_screen.dart` — immersive toggle, dispose restore, remove auto-hide, AppBar key subtitle + warning action + view-mode menu item, wire control bar, trim expanded call site.
- `lib/src/shared/app_strings.dart` — new labels (warning dialog, font/menu semantics).
- Tests mirror each of the above.

Each task ends green (`flutter analyze` clean + the named tests pass) and is committed.

---

## Task 1: Projection — `effectiveKey`

**Files:**
- Modify: `lib/src/presentation/song_reader/song_reader_projection.dart`
- Test: `test/presentation/song_reader/song_reader_projection_test.dart`

- [ ] **Step 1: Write the failing tests**

Append these tests inside `main()` in `song_reader_projection_test.dart`:

```dart
  test('effective key follows the displayed-chord path in guitar mode', () {
    // sourceKey G, baseTranspose 2, baseCapo 2, guitar:
    // sounding = G + 2 = A, then - capo(2) = G.
    final projection = SongReaderProjection(
      song: _buildParsedSong(),
      state: SongReaderState(),
    );

    expect(projection.effectiveKey, 'G');
  });

  test('effective key omits the capo offset in piano mode', () {
    // sounding = G + 2 = A; piano keeps the sounding key.
    final projection = SongReaderProjection(
      song: _buildParsedSong(),
      state: SongReaderState(
        instrumentDisplayMode: SongReaderInstrumentDisplayMode.piano,
      ),
    );

    expect(projection.effectiveKey, 'A');
  });

  test('effective key tracks transpose offset', () {
    // sounding = G + 2 + 1 = A#/Bb, then - capo(2) = G#/Ab.
    final projection = SongReaderProjection(
      song: _buildParsedSong(),
      state: SongReaderState(transposeOffset: 1),
    );

    expect(projection.effectiveKey, isNot('G'));
    expect(projection.effectiveKey, isNotNull);
  });

  test('effective key is null when the song has no source key', () {
    final projection = SongReaderProjection(
      song: ParsedSong(
        title: 'No key',
        sections: const [],
        diagnostics: const [],
      ),
      state: SongReaderState(),
    );

    expect(projection.effectiveKey, isNull);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/presentation/song_reader/song_reader_projection_test.dart`
Expected: FAIL — `effectiveKey` is not defined on `SongReaderProjection`.

- [ ] **Step 3: Add `effectiveKey` to the projection**

In `song_reader_projection.dart`, add the field initializer in the constructor's
initializer list (place it right after the `capoDirectiveText` initializer):

```dart
       effectiveKey = SongReaderProjection._effectiveKey(
         song,
         state,
         transposeChord,
       ),
```

Add the field declaration (next to `final String? capoDirectiveText;`):

```dart
  final String? effectiveKey;
```

Add this static helper inside the `SongReaderProjection` class (next to
`_displayChord`):

```dart
  static String? _effectiveKey(
    ParsedSong song,
    SongReaderState state,
    SongChordTransposer transposeChord,
  ) {
    final source = song.sourceKey;
    if (source == null || source.isEmpty) {
      return null;
    }

    try {
      final sounding = transposeChord(
        source,
        song.baseTranspose + state.transposeOffset,
      );
      if (state.instrumentDisplayMode ==
          SongReaderInstrumentDisplayMode.piano) {
        return sounding;
      }
      return transposeChord(sounding, -effectiveCapoValue(song, state));
    } on FormatException {
      return source;
    }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/presentation/song_reader/song_reader_projection_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze lib/src/presentation/song_reader/song_reader_projection.dart
git add lib/src/presentation/song_reader/song_reader_projection.dart test/presentation/song_reader/song_reader_projection_test.dart
git commit -m "feat(reader): expose effective key on projection"
```

---

## Task 2: New `SongReaderControlBar` widget

**Files:**
- Create: `lib/src/presentation/song_reader/widgets/song_reader_control_bar.dart`
- Create: `test/presentation/song_reader/widgets/song_reader_control_bar_test.dart`
- Modify: `lib/src/shared/app_strings.dart`

- [ ] **Step 1: Add the strings**

In `app_strings.dart`, next to the existing `songReader*` constants, add:

```dart
  static const songReaderTransposeDownSemantics = 'Transpose down';
  static const songReaderTransposeUpSemantics = 'Transpose up';
  static const songReaderCapoDownSemantics = 'Capo down';
  static const songReaderCapoUpSemantics = 'Capo up';
  static const songReaderDecreaseFontSemantics = 'Decrease text size';
  static const songReaderIncreaseFontSemantics = 'Increase text size';
```

- [ ] **Step 2: Write the failing tests**

Create `test/presentation/song_reader/widgets/song_reader_control_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_control_bar.dart';

ParsedSong _song({int baseCapo = 2}) {
  return ParsedSong(
    title: 'Song',
    sourceKey: 'G',
    baseTranspose: 2,
    baseCapo: baseCapo,
    sections: const [],
    diagnostics: const [],
  );
}

Widget _host(SongReaderControlBar bar) =>
    MaterialApp(home: Scaffold(body: bar));

void main() {
  testWidgets('renders transpose, capo and font controls in guitar mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SongReaderControlBar(
          projection: SongReaderProjection(song: _song(), state: SongReaderState()),
          onTransposeDown: () {},
          onTransposeUp: () {},
          onCapoDown: () {},
          onCapoUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('song-reader-transpose-down')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-transpose-value')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-transpose-up')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-down')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-value')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-up')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-font-decrease')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-font-increase')), findsOneWidget);
  });

  testWidgets('hides the capo group in piano mode', (tester) async {
    await tester.pumpWidget(
      _host(
        SongReaderControlBar(
          projection: SongReaderProjection(
            song: _song(),
            state: SongReaderState(
              instrumentDisplayMode: SongReaderInstrumentDisplayMode.piano,
            ),
          ),
          onTransposeDown: () {},
          onTransposeUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('song-reader-capo-down')), findsNothing);
    expect(find.byKey(const Key('song-reader-transpose-up')), findsOneWidget);
  });

  testWidgets('disables capo-down when onCapoDown is null', (tester) async {
    await tester.pumpWidget(
      _host(
        SongReaderControlBar(
          projection: SongReaderProjection(
            song: _song(baseCapo: 0),
            state: SongReaderState(),
          ),
          onTransposeDown: () {},
          onTransposeUp: () {},
          onCapoDown: null,
          onCapoUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () {},
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('song-reader-capo-down')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('invokes callbacks on tap', (tester) async {
    var transposeUp = 0;
    var fontUp = 0;
    await tester.pumpWidget(
      _host(
        SongReaderControlBar(
          projection: SongReaderProjection(song: _song(), state: SongReaderState()),
          onTransposeDown: () {},
          onTransposeUp: () => transposeUp += 1,
          onCapoDown: () {},
          onCapoUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () => fontUp += 1,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('song-reader-transpose-up')));
    await tester.tap(find.byKey(const Key('song-reader-font-increase')));
    expect(transposeUp, 1);
    expect(fontUp, 1);
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/presentation/song_reader/widgets/song_reader_control_bar_test.dart`
Expected: FAIL — `song_reader_control_bar.dart` does not exist.

- [ ] **Step 4: Implement the widget**

Create `lib/src/presentation/song_reader/widgets/song_reader_control_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Slim bottom control bar shown when the reader is active. Holds transpose,
/// capo (guitar only) and font-size controls as compact icon buttons.
class SongReaderControlBar extends StatelessWidget {
  const SongReaderControlBar({
    super.key,
    required this.projection,
    required this.onTransposeDown,
    required this.onTransposeUp,
    this.onCapoDown,
    this.onCapoUp,
    required this.onDecreaseFontScale,
    required this.onIncreaseFontScale,
  });

  final SongReaderProjection projection;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback? onCapoDown;
  final VoidCallback? onCapoUp;
  final VoidCallback onDecreaseFontScale;
  final VoidCallback onIncreaseFontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showCapo = projection.isCapoDirectiveVisible;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Group(
                  children: [
                    IconButton(
                      key: const Key('song-reader-transpose-down'),
                      tooltip: AppStrings.songReaderTransposeDownSemantics,
                      onPressed: onTransposeDown,
                      icon: const Icon(Icons.remove),
                    ),
                    _ValueChip(
                      key: const Key('song-reader-transpose-value'),
                      value: _signed(projection.effectiveTranspose),
                    ),
                    IconButton(
                      key: const Key('song-reader-transpose-up'),
                      tooltip: AppStrings.songReaderTransposeUpSemantics,
                      onPressed: onTransposeUp,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                if (showCapo) ...[
                  const _Divider(),
                  _Group(
                    children: [
                      IconButton(
                        key: const Key('song-reader-capo-down'),
                        tooltip: AppStrings.songReaderCapoDownSemantics,
                        onPressed: onCapoDown,
                        icon: const Icon(Icons.remove),
                      ),
                      _ValueChip(
                        key: const Key('song-reader-capo-value'),
                        value: '${AppStrings.songReaderCapoDirectivePrefix}'
                            '${projection.effectiveCapo}',
                      ),
                      IconButton(
                        key: const Key('song-reader-capo-up'),
                        tooltip: AppStrings.songReaderCapoUpSemantics,
                        onPressed: onCapoUp,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
                const _Divider(),
                _Group(
                  children: [
                    IconButton(
                      key: const Key('song-reader-font-decrease'),
                      tooltip: AppStrings.songReaderDecreaseFontSemantics,
                      onPressed: onDecreaseFontScale,
                      icon: const Icon(Icons.text_decrease),
                    ),
                    IconButton(
                      key: const Key('song-reader-font-increase'),
                      tooltip: AppStrings.songReaderIncreaseFontSemantics,
                      onPressed: onIncreaseFontScale,
                      icon: const Icon(Icons.text_increase),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _signed(int value) => value > 0 ? '+$value' : '$value';
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 24,
        child: VerticalDivider(
          width: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(value, style: theme.textTheme.labelLarge),
    );
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/presentation/song_reader/widgets/song_reader_control_bar_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze lib/src/presentation/song_reader/widgets/song_reader_control_bar.dart lib/src/shared/app_strings.dart
git add lib/src/presentation/song_reader/widgets/song_reader_control_bar.dart test/presentation/song_reader/widgets/song_reader_control_bar_test.dart lib/src/shared/app_strings.dart
git commit -m "feat(reader): add slim bottom control bar widget"
```

---

## Task 3: Compact surface uses the control bar; delete the overlay

The compact surface currently stacks `SongReaderCompactOverlay` (top Card). Replace
it with `SongReaderControlBar` at the bottom and drop the view-mode plumbing.

**Files:**
- Modify: `lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart`
- Modify: `lib/src/presentation/song_reader/song_reader_screen.dart` (compact call site only)
- Delete: `lib/src/presentation/song_reader/widgets/song_reader_compact_overlay.dart`
- Modify (rename): `test/presentation/song_reader/widgets/song_reader_compact_overlay_test.dart`
  → `test/presentation/song_reader/widgets/song_reader_expanded_tools_panel_test.dart`
- Modify: `test/presentation/song_reader/widgets/song_reader_compact_surface_test.dart`

- [ ] **Step 1: Update the compact-surface test**

In `song_reader_compact_surface_test.dart`, remove the `onToggleViewMode: () {},`
line from the `SongReaderCompactSurface` constructor call (the param is being
removed). Then add a test asserting the control bar shows only when controls are
visible. Replace the file body's `main()` with:

```dart
void main() {
  SongReaderCompactSurface buildSurface({required bool areControlsVisible}) {
    return SongReaderCompactSurface(
      projection: SongReaderProjection(
        song: ParsedSong(
          title: 'Song',
          sourceKey: 'G',
          sections: const [],
          diagnostics: const [],
        ),
        state: SongReaderState(),
      ),
      areControlsVisible: areControlsVisible,
      currentTitle: 'Song',
      onSurfaceTap: () {},
      hasRecoverableWarnings: false,
      warningCount: 0,
      contentColumnCount: 1,
      onTransposeDown: () {},
      onTransposeUp: () {},
      onDecreaseFontScale: () {},
      onIncreaseFontScale: () {},
      showBottomContextBar: false,
      maxContentWidth: 960,
      contentPadding: const EdgeInsets.all(24),
    );
  }

  testWidgets('opens controls from keyboard and exposes semantics tap', (
    tester,
  ) async {
    var surfaceTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderCompactSurface(
            projection: SongReaderProjection(
              song: ParsedSong(
                title: 'Song',
                sourceKey: 'G',
                sections: const [],
                diagnostics: const [],
              ),
              state: SongReaderState(),
            ),
            areControlsVisible: false,
            currentTitle: 'Song',
            onSurfaceTap: () => surfaceTaps += 1,
            hasRecoverableWarnings: false,
            warningCount: 0,
            contentColumnCount: 1,
            onTransposeDown: () {},
            onTransposeUp: () {},
            onDecreaseFontScale: () {},
            onIncreaseFontScale: () {},
            showBottomContextBar: false,
            maxContentWidth: 960,
            contentPadding: const EdgeInsets.all(24),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(surfaceTaps, 1);
  });

  testWidgets('shows the control bar only when controls are visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildSurface(areControlsVisible: false))),
    );
    expect(find.byType(SongReaderControlBar), findsNothing);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildSurface(areControlsVisible: true))),
    );
    expect(find.byType(SongReaderControlBar), findsOneWidget);
  });
}
```

Add the import at the top of the file:

```dart
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_control_bar.dart';
```

- [ ] **Step 2: Run the surface test to verify it fails**

Run: `flutter test test/presentation/song_reader/widgets/song_reader_compact_surface_test.dart`
Expected: FAIL — `onToggleViewMode` still required / `SongReaderControlBar` not found in surface.

- [ ] **Step 3: Update `SongReaderCompactSurface`**

In `song_reader_compact_surface.dart`:

1. Replace the overlay import with the control-bar import:

```dart
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_control_bar.dart';
```
(remove `import '.../song_reader_compact_overlay.dart';`)

2. Remove the `onToggleViewMode` field and its constructor param.

3. In `build`, remove the `SongReaderCompactOverlay(...)` child from the `Stack`
   and instead render the control bar inside the `Column`, below the content and
   above (or in place of) the bottom context bar. Replace the trailing
   `if (widget.showBottomContextBar) ...[...]` block so the layout reads:

```dart
                  Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          // ... unchanged content builder ...
                        ),
                      ),
                      if (widget.areControlsVisible) ...[
                        const SizedBox(height: 12),
                        SongReaderControlBar(
                          projection: widget.projection,
                          onTransposeDown: widget.onTransposeDown,
                          onTransposeUp: widget.onTransposeUp,
                          onCapoDown: widget.onCapoDown,
                          onCapoUp: widget.onCapoUp,
                          onDecreaseFontScale: widget.onDecreaseFontScale,
                          onIncreaseFontScale: widget.onIncreaseFontScale,
                        ),
                      ],
                      if (widget.showBottomContextBar) ...[
                        const SizedBox(height: 16),
                        SongReaderBottomContextBar(
                          currentTitle: widget.currentTitle,
                          previousTitle: widget.previousTitle,
                          nextTitle: widget.nextTitle,
                          onPreviousTap: widget.onPreviousTap,
                          onNextTap: widget.onNextTap,
                        ),
                      ],
                    ],
                  ),
```

   Remove the `SongReaderCompactOverlay(...)` widget that was the second child of
   the `Stack`. The `Stack` now wraps just the `Column` — you may keep the `Stack`
   with a single child or collapse it to the `Column`; keep the `Stack` to
   minimise churn.

- [ ] **Step 4: Update the screen's compact call site**

In `song_reader_screen.dart`, in the `SongReaderCompactSurface(...)` constructor
call (the `else` branch of the layout, ~line 873), remove the
`onToggleViewMode: _toggleViewMode,` argument. Leave all other args.

- [ ] **Step 5: Delete the overlay + retarget its test**

```bash
git rm lib/src/presentation/song_reader/widgets/song_reader_compact_overlay.dart
git mv test/presentation/song_reader/widgets/song_reader_compact_overlay_test.dart test/presentation/song_reader/widgets/song_reader_expanded_tools_panel_test.dart
```

Rewrite `song_reader_expanded_tools_panel_test.dart` to keep only the expanded
panel coverage (the overlay-specific tests are gone with the widget):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart';

void main() {
  testWidgets('expanded panels render transpose/capo/font controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(
                child: SongReaderExpandedContextPanel(
                  previousTitle: 'Before',
                  nextTitle: 'After',
                ),
              ),
              Expanded(
                child: SongReaderExpandedToolsPanel(
                  projection: SongReaderProjection(
                    song: _buildSong(),
                    state: SongReaderState(),
                  ),
                  onTransposeDown: () {},
                  onTransposeUp: () {},
                  onCapoDown: () {},
                  onCapoUp: () {},
                  onDecreaseFontScale: () {},
                  onIncreaseFontScale: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    expect(find.byKey(const Key('song-reader-transpose-up')), findsOneWidget);
  });
}

ParsedSong _buildSong({int baseCapo = 2}) {
  return ParsedSong(
    title: 'Reader Song',
    sourceKey: 'G',
    baseTranspose: 2,
    baseCapo: baseCapo,
    sections: [
      SongSection(
        kind: SongSectionKind.verse,
        label: 'Verse',
        lines: [
          LyricLine(
            segments: const [
              LyricSegment(leadingChord: 'G', text: 'Hello world'),
            ],
          ),
        ],
      ),
    ],
    diagnostics: const [],
  );
}
```

> NOTE: This test uses the trimmed `SongReaderExpandedToolsPanel` signature
> (no `onToggleViewMode` / `hasRecoverableWarnings` / `warningCount`). The panel
> is trimmed in Task 6 — if running tasks strictly in order this test will not
> compile until Task 6. Either (a) run Tasks 3 and 6 together, or (b) temporarily
> keep the old args here and remove them in Task 6. Recommended: keep the old args
> in this step, then trim them in Task 6 Step 1.

For option (b) in this step, include the old args in the panel call:

```dart
                SongReaderExpandedToolsPanel(
                  projection: SongReaderProjection(
                    song: _buildSong(),
                    state: SongReaderState(),
                  ),
                  hasRecoverableWarnings: false,
                  warningCount: 0,
                  onToggleViewMode: () {},
                  onTransposeDown: () {},
                  onTransposeUp: () {},
                  onCapoDown: () {},
                  onCapoUp: () {},
                  onDecreaseFontScale: () {},
                  onIncreaseFontScale: () {},
                ),
```

- [ ] **Step 6: Run the affected tests**

Run:
```
flutter test test/presentation/song_reader/widgets/song_reader_compact_surface_test.dart test/presentation/song_reader/widgets/song_reader_expanded_tools_panel_test.dart
```
Expected: PASS.

- [ ] **Step 7: Update screen test imports/refs that named the overlay**

`song_reader_screen_test.dart` imports `song_reader_compact_overlay.dart` (line 31).
Remove that import. If any test references `SongReaderCompactOverlay`, retarget it
to `SongReaderControlBar` (import
`.../widgets/song_reader_control_bar.dart`). Run the screen test to find breakage:

Run: `flutter test test/presentation/song_reader/song_reader_screen_test.dart`
Fix references until it compiles. (Overlay-visibility assertions become
control-bar assertions: `find.byType(SongReaderControlBar)`.) Auto-hide-specific
screen assertions are handled in Task 4 — if a test depends on the 3s timer, mark
it and adjust it in Task 4.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(reader): replace top overlay with bottom control bar in compact surface"
```

---

## Task 4: Immersive toggle + remove auto-hide

**Files:**
- Modify: `lib/src/presentation/song_reader/song_reader_screen.dart`
- Test: `test/presentation/song_reader/song_reader_screen_test.dart`

- [ ] **Step 1: Write the failing immersive test**

Add this test in `song_reader_screen_test.dart` `main()` (it records platform
channel calls for `SystemChrome.setEnabledSystemUIMode`):

```dart
  testWidgets('tapping the surface toggles immersive system UI mode', (
    tester,
  ) async {
    final modeCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modeCalls.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    // Tap the song surface to enter immersive mode.
    await tester.tap(find.byType(SongReaderCompactSurface));
    await tester.pump();
    expect(modeCalls, contains('SystemUiMode.immersiveSticky'));

    // Tap again to leave immersive mode.
    modeCalls.clear();
    await tester.tap(find.byType(SongReaderCompactSurface));
    await tester.pump();
    expect(modeCalls, contains('SystemUiMode.edgeToEdge'));
  });
```

Ensure `import 'package:flutter/services.dart';` is present in the test file
(it is, line 2).

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/presentation/song_reader/song_reader_screen_test.dart --plain-name "toggles immersive system UI mode"`
Expected: FAIL — no immersive call is made.

- [ ] **Step 3: Add immersive handling + remove auto-hide**

In `song_reader_screen.dart`:

1. Add the import: `import 'package:flutter/services.dart';`

2. Remove the auto-hide machinery:
   - delete the field `Timer? _compactOverlayHideTimer;`
   - delete `static const _compactOverlayInactivity = Duration(seconds: 3);`
   - delete methods `_handleCompactOverlayVisibilityChanged`,
     `_bumpCompactOverlayInactivityIfVisible`.
   - remove every call to `_bumpCompactOverlayInactivityIfVisible()` inside
     `_toggleViewMode`, `_transposeDown`, `_transposeUp`, `_capoDown`, `_capoUp`,
     `_setInstrumentDisplayMode`, `_adjustSharedFontScale`, `_setSharedFontScale`.
   - in `dispose()`, remove `_compactOverlayHideTimer?.cancel();` and add the
     system-UI restore (see step 4).

3. Add an immersive helper to the State class:

```dart
  void _applyImmersiveMode(bool active) {
    SystemChrome.setEnabledSystemUIMode(
      active ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }
```

4. Rewrite `_toggleCompactControls` to drive immersive mode from the new
   visibility (and drop the auto-hide call):

```dart
  void _toggleCompactControls() {
    if (_isScopedMode) {
      final runtimeController = ref.read(
        sessionScopedReaderRuntimeControllerProvider(_sessionKey),
      );
      runtimeController.toggleCompactControls();
      _applyImmersiveMode(
        runtimeController.state.readerState.areCompactControlsVisible,
      );
      return;
    }

    _updateState((controller) => controller.toggleCompactControls());
    _applyImmersiveMode(_controller.state.areCompactControlsVisible);
  }
```

5. In `dispose()`, restore the bars so other screens are unaffected:

```dart
  @override
  void dispose() {
    _persistZoomTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
```

- [ ] **Step 4: Run the immersive test + the full screen test**

Run: `flutter test test/presentation/song_reader/song_reader_screen_test.dart`
Expected: PASS. If any pre-existing test relied on the 3s auto-hide timer (e.g.
`tester.pump(const Duration(seconds: 3))` then expects controls hidden), update it
to expect controls stay visible until the next tap, and that a second tap hides
them.

- [ ] **Step 5: Commit**

```bash
git add lib/src/presentation/song_reader/song_reader_screen.dart test/presentation/song_reader/song_reader_screen_test.dart
git commit -m "feat(reader): single tap toggles immersive mode, drop auto-hide"
```

---

## Task 5: AppBar — effective key, warning action, view-mode menu item

**Files:**
- Modify: `lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `lib/src/shared/app_strings.dart`
- Test: `test/presentation/song_reader/song_reader_screen_test.dart`

- [ ] **Step 1: Add strings**

In `app_strings.dart` add:

```dart
  static const songReaderWarningDialogTitle = 'Reading warnings';
  static const songReaderWarningsSemantics = 'Show reading warnings';
  static const songReaderCloseAction = 'Close';
```

(`songReaderLyricsOnlyAction` / `songReaderChordsAndLyricsAction` already exist
for the menu item label.)

- [ ] **Step 2: Write the failing tests**

Add to `song_reader_screen_test.dart`:

```dart
  testWidgets('overflow menu toggles the view mode', (tester) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    // chords+lyrics is the default, so the menu offers "Lyrics only".
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songReaderLyricsOnlyAction).last);
    await tester.pumpAndSettle();

    // Re-open: now it offers "Chords + lyrics".
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(
      find.text(AppStrings.songReaderChordsAndLyricsAction),
      findsOneWidget,
    );
  });

  testWidgets('app bar shows the effective key', (tester) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    // sourceKey G, no transpose/capo, guitar → effective key G.
    expect(find.textContaining('G'), findsWidgets);
  });

  testWidgets('warning action appears and opens a dialog', (tester) async {
    await tester.pumpWidget(
      buildApp(
        result: buildResult(
          diagnostics: const [
            ParseDiagnostic(
              severity: ParseDiagnosticSeverity.warning,
              message: 'recoverable',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.warning_amber_outlined));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.songReaderWarningDialogTitle), findsOneWidget);
  });
```

Add the import for `ParseDiagnostic`/severity if not present:
`import 'package:lyron_app/src/domain/song/parse_diagnostic.dart';`
(Confirm the `ParseDiagnostic` constructor signature in
`lib/src/domain/song/parse_diagnostic.dart` and adjust the test args to match.)

- [ ] **Step 3: Run to verify failures**

Run: `flutter test test/presentation/song_reader/song_reader_screen_test.dart --plain-name "view mode"`
Expected: FAIL.

- [ ] **Step 4: Implement the AppBar changes**

In `song_reader_screen.dart` `build`:

1. Add `toggleViewMode` to the overflow enum:

```dart
enum _SongReaderOverflowAction { toggleViewMode, guitarView, pianoView, edit, delete }
```

2. In the `PopupMenuButton.onSelected` switch, add:

```dart
                  case _SongReaderOverflowAction.toggleViewMode:
                    _toggleViewMode();
                    break;
```

3. In `itemBuilder`, prepend a view-mode item whose label reflects the current
   mode. The current view mode is on `readerState.viewMode`:

```dart
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _SongReaderOverflowAction.toggleViewMode,
                  child: Text(
                    readerState.viewMode == SongReaderViewMode.chordsAndLyrics
                        ? AppStrings.songReaderLyricsOnlyAction
                        : AppStrings.songReaderChordsAndLyricsAction,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _SongReaderOverflowAction.guitarView,
                  child: Text(AppStrings.songReaderGuitarViewAction),
                ),
                // ... existing piano / edit / delete items ...
```

   Add `import '.../song_reader_state.dart'` if `SongReaderViewMode` is not
   already imported (it is, via existing imports).

4. Compute the projection-derived effective key for the AppBar. The `projection`
   local is already computed before the `Scaffold` (line ~638). Replace the
   AppBar `title: Text(currentTitle)` with a title + subtitle column:

```dart
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(currentTitle),
            if (projection?.effectiveKey != null)
              Text(
                '${AppStrings.songReaderKeyLabelPrefix}${projection!.effectiveKey}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
```

   Add a string in `app_strings.dart`: `static const songReaderKeyLabelPrefix = 'Key: ';`

5. Add a warning action before the `PopupMenuButton` in `actions:`. The
   recoverable-warning state needs to be known at AppBar build time. The
   `readerResult` local is available (line ~631). Compute:

```dart
    final hasRecoverableWarnings =
        readerResult?.hasRecoverableWarnings ?? false;
    final recoverableWarningCount = readerResult == null
        ? 0
        : readerResult.song.diagnostics
              .where(
                (d) => d.severity == ParseDiagnosticSeverity.warning,
              )
              .length;
```

   Then in `actions:`:

```dart
        actions: [
          if (hasRecoverableWarnings)
            IconButton(
              tooltip: AppStrings.songReaderWarningsSemantics,
              icon: const Icon(Icons.warning_amber_outlined),
              onPressed: () => _showWarningsDialog(context, recoverableWarningCount),
            ),
          if (readerResult != null)
            PopupMenuButton<_SongReaderOverflowAction>( /* ... */ ),
        ],
```

6. Add the dialog method to the State class:

```dart
  Future<void> _showWarningsDialog(BuildContext context, int count) {
    final message = count == 1
        ? '1 recoverable warning while reading this song.'
        : '$count recoverable warnings while reading this song.';
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.songReaderWarningDialogTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.songReaderCloseAction),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 5: Run the screen tests**

Run: `flutter test test/presentation/song_reader/song_reader_screen_test.dart`
Expected: PASS. Adjust the `effective key`/`textContaining` assertion if the
default fixture key differs.

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze lib/src/presentation/song_reader/song_reader_screen.dart lib/src/shared/app_strings.dart
git add lib/src/presentation/song_reader/song_reader_screen.dart lib/src/shared/app_strings.dart test/presentation/song_reader/song_reader_screen_test.dart
git commit -m "feat(reader): app bar effective key, warning action, view-mode menu item"
```

---

## Task 6: Trim the header + expanded panels (centralise key/warnings/view-mode)

The header is now used only by the expanded tools panel. Remove the now-duplicated
view-mode button, source-key chip, and warning surface from it, and drop those
params from the panel and the expanded surface.

**Files:**
- Modify: `lib/src/presentation/song_reader/widgets/song_reader_header.dart`
- Modify: `lib/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart`
- Modify: `lib/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart`
- Modify: `lib/src/presentation/song_reader/song_reader_screen.dart` (expanded call site)
- Modify: `test/presentation/song_reader/widgets/song_reader_expanded_tools_panel_test.dart`
- Modify: `test/presentation/song_reader/song_reader_screen_test.dart` (expanded assertions)

- [ ] **Step 1: Update the expanded-tools-panel test to the trimmed signature**

In `song_reader_expanded_tools_panel_test.dart`, remove `hasRecoverableWarnings`,
`warningCount`, and `onToggleViewMode` from the `SongReaderExpandedToolsPanel`
call (matching the Task 3 Step 5 option-(b) version). Final call args:
`projection`, `onTransposeDown`, `onTransposeUp`, `onCapoDown`, `onCapoUp`,
`onDecreaseFontScale`, `onIncreaseFontScale`.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/presentation/song_reader/widgets/song_reader_expanded_tools_panel_test.dart`
Expected: FAIL — params still required by the panel.

- [ ] **Step 3: Trim `SongReaderHeader`**

In `song_reader_header.dart`:
- Remove constructor params `onToggleViewMode`, `hasRecoverableWarnings`,
  `warningCount` and their fields.
- In `build`, remove: the source-key `_MetadataChip` block, the
  `if (hasRecoverableWarnings) ...[_WarningSurface]` block, and the entire
  `_ControlSection(label: songReaderViewSectionLabel, ...)` (view-mode) section.
- Remove the now-unused `_MetadataChip`, `_WarningSurface`, and `_viewModeLabel`
  members. Keep `_ValueChip`, `_ControlSection`, `_signed`, and the
  transpose/capo/font sections.

- [ ] **Step 4: Trim `SongReaderExpandedToolsPanel`**

In `song_reader_expanded_tools_panel.dart`, remove the `onToggleViewMode`,
`hasRecoverableWarnings`, `warningCount` params/fields and stop passing them to
`SongReaderHeader`.

- [ ] **Step 5: Trim `SongReaderExpandedSurface`**

In `song_reader_expanded_surface.dart`, remove the `onToggleViewMode`,
`hasRecoverableWarnings`, `warningCount` params/fields and stop passing them to
`SongReaderExpandedToolsPanel`.

- [ ] **Step 6: Update the screen's expanded call site**

In `song_reader_screen.dart`, in the `SongReaderExpandedSurface(...)` call
(the `if (layout.shell == SongReaderShell.expanded)` branch, ~line 837), remove
the `onToggleViewMode:`, `hasRecoverableWarnings:`, and `warningCount:` arguments.

- [ ] **Step 7: Fix screen-test expanded assertions**

In `song_reader_screen_test.dart`, any expanded-surface test asserting
`find.text('Key: G')`, the in-panel warning surface, or the in-header
"Lyrics only" button must move to the AppBar equivalents (effective-key subtitle,
`Icons.warning_amber_outlined` action, overflow menu item). Update those
assertions. Remove the now-unused `song_reader_title_bar.dart` import only if it
becomes unreferenced (leave otherwise).

- [ ] **Step 8: Run the affected tests + analyze**

Run:
```
flutter test test/presentation/song_reader/
flutter analyze lib/src/presentation/song_reader/
```
Expected: PASS / no issues.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor(reader): centralise key/warnings/view-mode, trim header + expanded panels"
```

---

## Task 7: Full verification + manual smoke + docs

**Files:**
- Verify only; possibly `docs/specs/2026-06-14-song-reader-immersive-controls.md` (status).

- [ ] **Step 1: Full analyze + test suite**

Run from `apps/lyron_app`:
```
flutter analyze
flutter test
```
Expected: no analyzer issues; all tests pass. Fix any stragglers (integration
tests under `test/integration/` that pump the reader and referenced the overlay or
auto-hide).

- [ ] **Step 2: Manual smoke (device/emulator)**

Run the app and open a song:
- Single tap → status + nav bars hide, bottom icon bar appears, top app bar +
  (in plan-session mode) next/prev bar remain.
- Tap again → bars restore, icon bar hides.
- Transpose ± / capo ± (guitar) / font ± work from the icon bar; capo group hidden
  in piano mode; capo− disabled at 0.
- `...` menu toggles Lyrics only ↔ Chords + lyrics.
- Effective key shows in the app bar and updates with transpose/capo.
- Warning icon appears only for songs with recoverable warnings; opens the dialog.
- Leaving the reader restores system bars on the previous screen.

- [ ] **Step 3: Flip spec status to Accepted + commit**

In `docs/specs/2026-06-14-song-reader-immersive-controls.md` change
`Status: Draft` → `Status: Accepted`.

```bash
git add docs/specs/2026-06-14-song-reader-immersive-controls.md
git commit -m "docs(reader): mark immersive controls spec accepted"
```

- [ ] **Step 4: Open the PR**

```bash
git push -u origin feat/song-reader-immersive-controls
gh pr create --fill
```

---

## Self-Review Notes

- **Spec coverage:** req1 immersive (Task 4) ✔; req2 bottom icon bar (Tasks 2–3) ✔;
  req3 view-mode in menu (Task 5) ✔; req4 consistency — effective key in app bar
  (Tasks 1, 5), warnings centralised (Task 5–6), expanded parity (Task 6) ✔;
  no auto-hide (Task 4) ✔.
- **Type consistency:** `effectiveKey` (Task 1) consumed in Task 5; control-bar
  keys (`song-reader-transpose-*`, `-capo-*`, `-font-*`) defined Task 2, asserted
  Tasks 2–3; trimmed signatures (`SongReaderHeader`, `SongReaderExpandedToolsPanel`,
  `SongReaderExpandedSurface`) changed and consumed together in Task 6.
- **Ordering caveat:** Task 3 Step 5 documents the one cross-task signature
  coupling (expanded panel trim) — use option (b) to keep every task green.
- **Verify before claiming done:** Task 7 runs the full suite and a manual smoke
  before the PR.
