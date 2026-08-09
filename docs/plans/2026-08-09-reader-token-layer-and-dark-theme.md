# Reader token layer and dark theme — implementation plan (PR1 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/specs/2026-08-09-song-presentation.md`

**Goal:** Give the song reader a single source of truth for its colours and text styles (a `ReaderTheme` `ThemeExtension`), and ship a dark theme designed for a dim stage — without changing a single rendered pixel in the light theme.

**Architecture:** Reader widgets and the fit estimator's char-width measurement currently each reach into `Theme.of(context).textTheme` / `.colorScheme` and re-derive the same styles by hand. That duplication is what makes typography changes dangerous: the renderer and the estimator can drift apart silently. This PR routes both through one `ReaderTheme` object so the later typography change (PR2) has exactly one place to edit. Spacing constants are *not* moved — they already live in one place (`song_reader_metrics.dart`, `song_reader_fit.dart`) and are theme-independent.

**Tech stack:** Flutter (Material 3), `ThemeExtension<T>`, `flutter_test`.

**Scope boundary:** this PR is PR1 of the four in the spec. It does **not** change typography, spacing, layout or chrome. Plans for PR2–PR4 are written at the start of their own sessions, because their task content depends on the API this PR actually lands.

---

## Why the light theme must not move

`measureSongReaderCharWidths` (`song_reader_char_metrics.dart:125`) measures the exact styles `SongLineView` renders with, and feeds those widths into the fit estimator's upper bound. If the two ever describe different styles, the estimator can fall below the render and fit-to-screen overflows — the failure the whole estimator exists to prevent.

Today they agree only by convention: `song_line_view.dart:22-30` builds `labelLarge + w700` / `bodyLarge + height: 1.25`, and `song_reader_char_metrics.dart:128-135` re-types the same expressions. After this PR they agree structurally, because both read the same `ReaderTheme` fields.

That is the whole point of the PR, so **the three estimator consistency suites are the acceptance test**, and they must stay green at every commit:

```
apps/lyron_app/test/presentation/song_reader/song_line_view_estimate_consistency_test.dart
apps/lyron_app/test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart
apps/lyron_app/test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart
```

## File structure

**Create**
- `apps/lyron_app/lib/src/app/reader_theme.dart` — the `ReaderTheme` extension, its `fromM3` (today's derivation) and `stageDark` factories, `copyWith`, `lerp`, and the `of(context)` lookup.
- `apps/lyron_app/test/app/reader_theme_test.dart` — unit tests for the extension itself.
- `apps/lyron_app/test/app/app_theme_test.dart` — tests that both `ThemeData`s register a `ReaderTheme`, and that the light one is byte-for-byte what the widgets used to derive.
- `apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart` — tests that each reader widget renders with the values from the extension, including under a deliberately non-default extension.
- `docs/architecture/decisions/ADR-033-reader-design-token-layer.md`

**Modify**
- `apps/lyron_app/lib/src/app/app_theme.dart` — split `buildAppTheme()` into `buildLightTheme()` / `buildDarkTheme()`, register the extension on both.
- `apps/lyron_app/lib/src/app/lyron_app.dart:34` — wire `theme:` and `darkTheme:`.
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart:22-30`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart:190-201, 233-255`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/comment_line_view.dart:16-26`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/directive_line_view.dart:11-23`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/tab_block_view.dart:16-28`
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_char_metrics.dart:125-162`
- `docs/architecture/repository-review-2026-06-22.md` — strike through UX-7.

**Deliberately untouched in this PR:** `song_reader_app_bar.dart`, `song_reader_control_bar.dart`, `song_reader_bottom_context_bar.dart`, `song_reader_header.dart`, `song_reader_title_bar.dart`, the expanded-surface panels. These are chrome, rebuilt in PR3; in the dark theme they inherit Material 3's dark `ColorScheme` and will look plausible but not designed. That is expected at this stage.

---

### Task 1: The `ReaderTheme` extension

**Files:**
- Create: `apps/lyron_app/lib/src/app/reader_theme.dart`
- Test: `apps/lyron_app/test/app/reader_theme_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// apps/lyron_app/test/app/reader_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/reader_theme.dart';

void main() {
  final lightBase = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F)),
    useMaterial3: true,
  );

  group('ReaderTheme.fromM3', () {
    test('reproduces the styles the reader widgets derive by hand today', () {
      final tokens = ReaderTheme.fromM3(
        colorScheme: lightBase.colorScheme,
        textTheme: lightBase.textTheme,
      );

      expect(
        tokens.lyricStyle,
        lightBase.textTheme.bodyLarge!.copyWith(height: 1.25),
      );
      expect(
        tokens.chordStyle,
        lightBase.textTheme.labelLarge!.copyWith(
          fontWeight: FontWeight.w700,
          color: lightBase.colorScheme.primary,
        ),
      );
      expect(
        tokens.sectionLabelStyle,
        lightBase.textTheme.titleLarge!.copyWith(
          color: lightBase.colorScheme.primary,
        ),
      );
      expect(tokens.unknownSectionLabelColor, lightBase.colorScheme.tertiary);
      expect(tokens.chordChipColor, isNull);
    });
  });

  group('lerp', () {
    test('returns the receiver when other is null', () {
      final tokens = ReaderTheme.fromM3(
        colorScheme: lightBase.colorScheme,
        textTheme: lightBase.textTheme,
      );

      expect(tokens.lerp(null, 0.5), same(tokens));
    });

    test('interpolates every colour field', () {
      final a = ReaderTheme.fromM3(
        colorScheme: lightBase.colorScheme,
        textTheme: lightBase.textTheme,
      ).copyWith(unknownSectionLabelColor: const Color(0xFF000000));
      final b = a.copyWith(unknownSectionLabelColor: const Color(0xFFFFFFFF));

      final mid = a.lerp(b, 0.5);

      expect(
        mid.unknownSectionLabelColor,
        Color.lerp(const Color(0xFF000000), const Color(0xFFFFFFFF), 0.5),
      );
    });
  });

  group('stageDark', () {
    test('uses the stage palette rather than inverting the light one', () {
      final darkBase = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B6E4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );

      final tokens = ReaderTheme.stageDark(textTheme: darkBase.textTheme);

      expect(tokens.lyricStyle.color, const Color(0xFFCDCAC0));
      expect(tokens.chordStyle.color, const Color(0xFF7ACFA8));
      expect(tokens.sectionLabelStyle.color, const Color(0xFF6FA98D));
      // The light-theme green is unreadable on black; it must not leak through.
      expect(tokens.chordStyle.color, isNot(const Color(0xFF0B6E4F)));
    });
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd apps/lyron_app && flutter test test/app/reader_theme_test.dart`
Expected: compile error — `Target of URI doesn't exist: 'package:lyron_app/src/app/reader_theme.dart'`.

- [ ] **Step 3: Write the extension**

```dart
// apps/lyron_app/lib/src/app/reader_theme.dart
import 'package:flutter/material.dart';

/// Colours and text styles for the song reader's content surface.
///
/// The reader's renderer and its fit estimator must describe the *same* text
/// styles: `measureSongReaderCharWidths` measures the styles the reader draws
/// with and feeds the result into an estimate that must never fall below the
/// rendered height. Before this extension existed they agreed only by
/// convention — `song_line_view.dart` and `song_reader_char_metrics.dart` each
/// re-derived `labelLarge + w700` / `bodyLarge + height: 1.25` by hand. Reading
/// both from one object makes that agreement structural.
///
/// Spacing is deliberately NOT here. Line, section and padding constants live
/// in `song_reader_metrics.dart` and `song_reader_fit.dart`, are shared by the
/// renderer and the estimator already, and do not vary by theme. Copying them
/// into a theme object would create the second definition this class exists to
/// remove.
@immutable
class ReaderTheme extends ThemeExtension<ReaderTheme> {
  const ReaderTheme({
    required this.lyricStyle,
    required this.chordStyle,
    required this.chordChipColor,
    required this.sectionLabelStyle,
    required this.unknownSectionLabelColor,
    required this.commentStyle,
    required this.directiveStyle,
    required this.leadingDirectiveStyle,
    required this.tabStyle,
    required this.tabBackgroundColor,
  });

  /// Lyric text. Font size is the BASE size; the reader multiplies it by
  /// `sharedFontScale` at render time and the estimator converts it with
  /// `SongReaderFitTextScale.factorFor`.
  final TextStyle lyricStyle;

  /// Chord label text, at its base size.
  final TextStyle chordStyle;

  /// Background fill behind a chord label, or null for no fill.
  ///
  /// Null in both themes today. PR2 introduces the tinted chip; it is declared
  /// now so the chip's colour has a home and the renderer/estimator agree from
  /// the start about whether a chip exists.
  final Color? chordChipColor;

  /// Section header label ("Verse 1"), at its base size.
  final TextStyle sectionLabelStyle;

  /// Label colour for a section whose kind the parser did not recognise.
  final Color unknownSectionLabelColor;

  /// Comment line ({comment: ...}) text, at its base size.
  final TextStyle commentStyle;

  /// Inline directive line text.
  final TextStyle directiveStyle;

  /// The leading directive line rendered above the first section (capo).
  final TextStyle leadingDirectiveStyle;

  /// Tab block text. Monospaced; the block scrolls horizontally rather than
  /// wrapping.
  final TextStyle tabStyle;

  /// Tab block container fill.
  final Color tabBackgroundColor;

  /// Builds the tokens exactly as the reader widgets derived them from a
  /// Material 3 theme before this class existed. Used for the light theme, and
  /// as the fallback for any `ThemeData` that has not registered the extension
  /// (notably widget tests that pump a bare `MaterialApp`), so that such a tree
  /// renders identically to how it did before.
  factory ReaderTheme.fromM3({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return ReaderTheme(
      lyricStyle: textTheme.bodyLarge!.copyWith(height: 1.25),
      chordStyle: textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w700,
        color: colorScheme.primary,
      ),
      chordChipColor: null,
      sectionLabelStyle: textTheme.titleLarge!.copyWith(
        color: colorScheme.primary,
      ),
      unknownSectionLabelColor: colorScheme.tertiary,
      commentStyle: textTheme.bodyMedium!.copyWith(
        fontStyle: FontStyle.italic,
        color: colorScheme.onSurface.withValues(alpha: 0.55),
        height: 1.4,
      ),
      directiveStyle: textTheme.labelMedium!.copyWith(
        color: colorScheme.tertiary,
        fontWeight: FontWeight.w500,
      ),
      leadingDirectiveStyle: textTheme.labelLarge!.copyWith(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.02,
      ),
      tabStyle: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        height: 1.5,
        color: colorScheme.onSurface,
      ),
      tabBackgroundColor: colorScheme.surfaceContainerHighest,
    );
  }

  /// The dark theme's reader palette, designed for a dim stage.
  ///
  /// Not an inversion of the light palette. Two measurements drove it:
  /// lifting the page off pure black reduced emitted light by 0% (the light
  /// comes from the text, not the background), while dropping the text from
  /// #E8E6DD to #CDCAC0 cut relative text luminance from 79% to 59% and still
  /// leaves 12.8:1 contrast. And the light theme's #0B6E4F sits near 2:1 on
  /// black, so the accent needs its own value rather than an inversion.
  /// See docs/specs/2026-08-09-song-presentation.md.
  factory ReaderTheme.stageDark({required TextTheme textTheme}) {
    const lyricColor = Color(0xFFCDCAC0);
    const chordColor = Color(0xFF7ACFA8);
    const sectionLabelColor = Color(0xFF6FA98D);
    const unknownSectionColor = Color(0xFFD8B892);

    return ReaderTheme(
      lyricStyle: textTheme.bodyLarge!.copyWith(
        height: 1.25,
        color: lyricColor,
      ),
      chordStyle: textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w700,
        color: chordColor,
      ),
      chordChipColor: null,
      sectionLabelStyle: textTheme.titleLarge!.copyWith(
        color: sectionLabelColor,
      ),
      unknownSectionLabelColor: unknownSectionColor,
      commentStyle: textTheme.bodyMedium!.copyWith(
        fontStyle: FontStyle.italic,
        color: lyricColor.withValues(alpha: 0.62),
        height: 1.4,
      ),
      directiveStyle: textTheme.labelMedium!.copyWith(
        color: unknownSectionColor,
        fontWeight: FontWeight.w500,
      ),
      leadingDirectiveStyle: textTheme.labelLarge!.copyWith(
        color: chordColor,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.02,
      ),
      tabStyle: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        height: 1.5,
        color: lyricColor,
      ),
      tabBackgroundColor: const Color(0xFF1A1C18),
    );
  }

  /// The reader tokens for [context].
  ///
  /// Falls back to [ReaderTheme.fromM3] over the ambient theme when no
  /// extension is registered, so a tree that predates the extension renders
  /// unchanged. `app_theme_test.dart` pins the fallback to the registered
  /// light tokens so the two cannot drift.
  static ReaderTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ReaderTheme>() ??
        ReaderTheme.fromM3(
          colorScheme: theme.colorScheme,
          textTheme: theme.textTheme,
        );
  }

  @override
  ReaderTheme copyWith({
    TextStyle? lyricStyle,
    TextStyle? chordStyle,
    Color? chordChipColor,
    TextStyle? sectionLabelStyle,
    Color? unknownSectionLabelColor,
    TextStyle? commentStyle,
    TextStyle? directiveStyle,
    TextStyle? leadingDirectiveStyle,
    TextStyle? tabStyle,
    Color? tabBackgroundColor,
  }) {
    return ReaderTheme(
      lyricStyle: lyricStyle ?? this.lyricStyle,
      chordStyle: chordStyle ?? this.chordStyle,
      chordChipColor: chordChipColor ?? this.chordChipColor,
      sectionLabelStyle: sectionLabelStyle ?? this.sectionLabelStyle,
      unknownSectionLabelColor:
          unknownSectionLabelColor ?? this.unknownSectionLabelColor,
      commentStyle: commentStyle ?? this.commentStyle,
      directiveStyle: directiveStyle ?? this.directiveStyle,
      leadingDirectiveStyle:
          leadingDirectiveStyle ?? this.leadingDirectiveStyle,
      tabStyle: tabStyle ?? this.tabStyle,
      tabBackgroundColor: tabBackgroundColor ?? this.tabBackgroundColor,
    );
  }

  @override
  ReaderTheme lerp(ThemeExtension<ReaderTheme>? other, double t) {
    if (other is! ReaderTheme) {
      return this;
    }

    return ReaderTheme(
      lyricStyle: TextStyle.lerp(lyricStyle, other.lyricStyle, t)!,
      chordStyle: TextStyle.lerp(chordStyle, other.chordStyle, t)!,
      chordChipColor: Color.lerp(chordChipColor, other.chordChipColor, t),
      sectionLabelStyle:
          TextStyle.lerp(sectionLabelStyle, other.sectionLabelStyle, t)!,
      unknownSectionLabelColor: Color.lerp(
        unknownSectionLabelColor,
        other.unknownSectionLabelColor,
        t,
      )!,
      commentStyle: TextStyle.lerp(commentStyle, other.commentStyle, t)!,
      directiveStyle: TextStyle.lerp(directiveStyle, other.directiveStyle, t)!,
      leadingDirectiveStyle: TextStyle.lerp(
        leadingDirectiveStyle,
        other.leadingDirectiveStyle,
        t,
      )!,
      tabStyle: TextStyle.lerp(tabStyle, other.tabStyle, t)!,
      tabBackgroundColor:
          Color.lerp(tabBackgroundColor, other.tabBackgroundColor, t)!,
    );
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd apps/lyron_app && flutter test test/app/reader_theme_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/app/reader_theme.dart apps/lyron_app/test/app/reader_theme_test.dart
git commit -m "feat(reader): add a ReaderTheme extension for reader colours and text styles"
```

---

### Task 2: Register the extension on both themes

**Files:**
- Modify: `apps/lyron_app/lib/src/app/app_theme.dart`
- Test: `apps/lyron_app/test/app/app_theme_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// apps/lyron_app/test/app/app_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/app/reader_theme.dart';

void main() {
  test('the light theme registers reader tokens', () {
    final theme = buildLightTheme();

    expect(theme.extension<ReaderTheme>(), isNotNull);
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F4EA));
  });

  test('the dark theme registers reader tokens and a black page', () {
    final theme = buildDarkTheme();

    expect(theme.extension<ReaderTheme>(), isNotNull);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
  });

  test(
    'the light tokens equal the fallback, so a tree without the extension '
    'renders identically to one with it',
    () {
      final theme = buildLightTheme();

      expect(
        theme.extension<ReaderTheme>(),
        ReaderTheme.fromM3(
          colorScheme: theme.colorScheme,
          textTheme: theme.textTheme,
        ),
      );
    },
  );
}
```

Note for the implementer: this last test only passes if `ReaderTheme` has value equality. `ThemeExtension` does not provide it. Add `operator ==` and `hashCode` over all ten fields to `ReaderTheme` in this task (it belongs with the test that needs it, not with Task 1).

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd apps/lyron_app && flutter test test/app/app_theme_test.dart`
Expected: compile error — `buildLightTheme` and `buildDarkTheme` are not defined.

- [ ] **Step 3: Rewrite `app_theme.dart`**

```dart
// apps/lyron_app/lib/src/app/app_theme.dart
import 'package:flutter/material.dart';
import 'package:lyron_app/src/app/reader_theme.dart';

const _seedColor = Color(0xFF0B6E4F);
const _lightPage = Color(0xFFF7F4EA);

/// The dark reader keeps a pure black page: emitted light — and therefore
/// glare on a dim stage — comes from the text, not the background, so the
/// text is dimmed instead. See docs/specs/2026-08-09-song-presentation.md.
const _darkPage = Color(0xFF000000);

ThemeData buildLightTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
    useMaterial3: true,
    scaffoldBackgroundColor: _lightPage,
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      ReaderTheme.fromM3(
        colorScheme: base.colorScheme,
        textTheme: base.textTheme,
      ),
    ],
  );
}

ThemeData buildDarkTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: _darkPage,
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      ReaderTheme.stageDark(textTheme: base.textTheme),
    ],
  );
}
```

- [ ] **Step 4: Add value equality to `ReaderTheme`**

Append to `apps/lyron_app/lib/src/app/reader_theme.dart`, inside the class:

```dart
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is ReaderTheme &&
        other.lyricStyle == lyricStyle &&
        other.chordStyle == chordStyle &&
        other.chordChipColor == chordChipColor &&
        other.sectionLabelStyle == sectionLabelStyle &&
        other.unknownSectionLabelColor == unknownSectionLabelColor &&
        other.commentStyle == commentStyle &&
        other.directiveStyle == directiveStyle &&
        other.leadingDirectiveStyle == leadingDirectiveStyle &&
        other.tabStyle == tabStyle &&
        other.tabBackgroundColor == tabBackgroundColor;
  }

  @override
  int get hashCode => Object.hash(
    lyricStyle,
    chordStyle,
    chordChipColor,
    sectionLabelStyle,
    unknownSectionLabelColor,
    commentStyle,
    directiveStyle,
    leadingDirectiveStyle,
    tabStyle,
    tabBackgroundColor,
  );
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `cd apps/lyron_app && flutter test test/app/`
Expected: all tests in both files pass.

- [ ] **Step 6: Fix the remaining `buildAppTheme` references**

Run: `grep -rn "buildAppTheme" apps/lyron_app`
Update every hit to `buildLightTheme()`. Then run `cd apps/lyron_app && flutter analyze` and expect no issues.

- [ ] **Step 7: Commit**

```bash
git add apps/lyron_app/lib/src/app/app_theme.dart apps/lyron_app/lib/src/app/reader_theme.dart apps/lyron_app/test/app/app_theme_test.dart
git commit -m "feat(theme): build separate light and dark themes carrying reader tokens"
```

---

### Task 3: Wire the dark theme into the app

**Files:**
- Modify: `apps/lyron_app/lib/src/app/lyron_app.dart:32-38`

- [ ] **Step 1: Write the failing test**

Append to `apps/lyron_app/test/app/app_theme_test.dart`:

```dart
  testWidgets('the app offers both themes to the system', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        home: Builder(
          builder: (context) => Text(
            'reader',
            style: ReaderTheme.of(context).lyricStyle,
          ),
        ),
      ),
    );

    expect(find.text('reader'), findsOneWidget);
  });
```

This is a smoke test for the wiring shape. The real assertion that `lyron_app.dart` passes both is Step 4.

- [ ] **Step 2: Run it and confirm it passes already** (it exercises `MaterialApp`, not our widget)

Run: `cd apps/lyron_app && flutter test test/app/app_theme_test.dart`
Expected: PASS. This step exists so the next edit is a wiring change with a known-good baseline, not a leap.

- [ ] **Step 3: Edit `lyron_app.dart`**

Replace the `MaterialApp.router` arguments at `apps/lyron_app/lib/src/app/lyron_app.dart:32`:

```dart
    return MaterialApp.router(
      title: AppStrings.appName,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: router,
      builder: (context, child) =>
          ReauthPromptHost(child: child ?? const SizedBox.shrink()),
    );
```

- [ ] **Step 4: Run the full reader suite**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/`
Expected: PASS, with no change in count. Nothing in the reader reads the extension yet, so this proves the wiring is inert so far.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/app/lyron_app.dart apps/lyron_app/test/app/app_theme_test.dart
git commit -m "feat(theme): follow the system dark mode setting (UX-7)"
```

---

### Task 3b: An in-app light/dark switch

Following the system setting alone is not enough for the use case that justifies
the dark theme: a stage tablet is in light mode all day, and nobody leaves the
app for iOS Settings between two songs. The switch has to be reachable from the
reader.

**Design, kept deliberately small:**

- Three effective states, two stored: no stored value means "follow the system";
  once the user picks, an explicit `light` or `dark` is stored and the system
  setting no longer applies. There is no "back to system" entry — it would be a
  third menu state to explain for a preference people set once.
- The entry point is the reader's existing overflow menu, because that is where
  the user is standing when they need it. The account screen is a more
  conventional home for a setting and can gain one later; it is not built here.
- The preference is app-wide, not per song, so it does **not** belong in
  `SongReaderPreferencesStore` (which is keyed `reader_zoom:userId:songId`).
  It gets its own tiny store.

**Files:**
- Create: `apps/lyron_app/lib/src/app/theme_mode_store.dart`
- Create: `apps/lyron_app/test/app/theme_mode_store_test.dart`
- Modify: `apps/lyron_app/lib/src/app/lyron_app.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_app_bar.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart:396-426`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`

- [ ] **Step 1: Write the failing store test**

```dart
// apps/lyron_app/test/app/theme_mode_store_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/theme_mode_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferencesThemeModeStore> store(
    Map<String, Object> initial,
  ) async {
    SharedPreferences.setMockInitialValues(initial);
    return SharedPreferencesThemeModeStore(
      await SharedPreferences.getInstance(),
    );
  }

  test('with nothing stored it follows the system', () async {
    expect(await (await store({})).read(), ThemeMode.system);
  });

  test('round-trips an explicit dark choice', () async {
    final subject = await store({});
    await subject.write(ThemeMode.dark);

    expect(await subject.read(), ThemeMode.dark);
  });

  test('writing system clears the stored override', () async {
    final subject = await store({'app_theme_mode': 'dark'});
    await subject.write(ThemeMode.system);

    expect(await subject.read(), ThemeMode.system);
  });

  test('an unrecognised stored value falls back to the system', () async {
    expect(
      await (await store({'app_theme_mode': 'sepia'})).read(),
      ThemeMode.system,
    );
  });
}
```

- [ ] **Step 2: Run and confirm it fails**

Run: `cd apps/lyron_app && flutter test test/app/theme_mode_store_test.dart`
Expected: compile error — `theme_mode_store.dart` does not exist.

- [ ] **Step 3: Write the store and controller**

```dart
// apps/lyron_app/lib/src/app/theme_mode_store.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/provider_retry_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists an explicit app-wide light/dark choice.
///
/// Absence of a stored value means "follow the system", so a user who never
/// touches the switch keeps the platform behaviour. This is app-wide state and
/// deliberately does not live in [SongReaderPreferencesStore], whose keys are
/// scoped to a user and a song.
abstract class ThemeModeStore {
  Future<ThemeMode> read();
  Future<void> write(ThemeMode mode);
}

class SharedPreferencesThemeModeStore implements ThemeModeStore {
  SharedPreferencesThemeModeStore(this._prefs);

  static const _key = 'app_theme_mode';

  final SharedPreferences _prefs;

  @override
  Future<ThemeMode> read() async {
    return switch (_prefs.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  @override
  Future<void> write(ThemeMode mode) async {
    switch (mode) {
      case ThemeMode.light:
        await _prefs.setString(_key, 'light');
      case ThemeMode.dark:
        await _prefs.setString(_key, 'dark');
      case ThemeMode.system:
        await _prefs.remove(_key);
    }
  }
}

final themeModeStoreProvider = FutureProvider<ThemeModeStore>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return SharedPreferencesThemeModeStore(prefs);
}, retry: noAutomaticProviderRetry);

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final store = await ref.watch(themeModeStoreProvider.future);
    return store.read();
  }

  /// Flips to the opposite of what is currently on screen.
  ///
  /// Takes the rendered brightness rather than reading state, so that the first
  /// tap while still following the system flips away from what the user is
  /// actually looking at, not away from `ThemeMode.system`.
  Future<void> toggle(Brightness activeBrightness) async {
    final next = activeBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    final store = await ref.read(themeModeStoreProvider.future);
    await store.write(next);
    state = AsyncData(next);
  }
}

final themeModeControllerProvider =
    AsyncNotifierProvider<ThemeModeController, ThemeMode>(
      ThemeModeController.new,
      retry: noAutomaticProviderRetry,
    );
```

Note for the implementer: this repo is on Riverpod 3.4.2 and makes provider
failures terminal (ADR-032). Before writing the provider declarations above,
run `grep -rn "noAutomaticProviderRetry" apps/lyron_app/lib | head` and match the
exact declaration style used by the neighbouring providers — if `AsyncNotifierProvider`
is spelled differently in this codebase's Riverpod 3 style, follow the codebase.

- [ ] **Step 4: Run the store test and confirm it passes**

Run: `cd apps/lyron_app && flutter test test/app/theme_mode_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Add the strings**

In `apps/lyron_app/lib/src/shared/app_strings.dart`, next to the other
`songReader*` entries:

```dart
  static const String songReaderDarkThemeAction = 'Dark view';
  static const String songReaderLightThemeAction = 'Light view';
```

- [ ] **Step 6: Add the menu entry**

In `song_reader_overflow_menu.dart`, add to the enum:

```dart
  toggleTheme,
```

add a constructor parameter and field:

```dart
    required this.isDarkActive,
```
```dart
  /// Whether the reader is currently rendering dark. Passed in rather than read
  /// from a provider: this widget stays provider-free, like the rest of the
  /// reader's leaf widgets.
  final bool isDarkActive;
```

and add the item after the instrument entries, before the `canEditSongs` block:

```dart
        const PopupMenuDivider(),
        PopupMenuItem(
          value: SongReaderOverflowAction.toggleTheme,
          child: Text(
            isDarkActive
                ? AppStrings.songReaderLightThemeAction
                : AppStrings.songReaderDarkThemeAction,
          ),
        ),
```

In `song_reader_app_bar.dart`, thread the same flag through: add
`required this.isDarkActive;` to the constructor and field list, and pass
`isDarkActive: isDarkActive` into `SongReaderOverflowMenu`.

- [ ] **Step 7: Handle the action in the screen**

In `song_reader_screen.dart`, pass the flag into the app bar:

```dart
        isDarkActive: Theme.of(context).brightness == Brightness.dark,
```

and add the case to the `switch` at line 400:

```dart
            case SongReaderOverflowAction.toggleTheme:
              unawaited(
                ref
                    .read(themeModeControllerProvider.notifier)
                    .toggle(Theme.of(context).brightness),
              );
              break;
```

Add the `theme_mode_store.dart` import.

- [ ] **Step 8: Wire `themeMode` into the app**

In `lyron_app.dart`, watch the controller and pass the mode. While the stored
value is still loading, follow the system — that is the pre-existing behaviour,
so a slow read cannot flash a theme the user never chose:

```dart
    final themeMode = ref
        .watch(themeModeControllerProvider)
        .valueOrNull ??
        ThemeMode.system;

    return MaterialApp.router(
      title: AppStrings.appName,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) =>
          ReauthPromptHost(child: child ?? const SizedBox.shrink()),
    );
```

- [ ] **Step 9: Write the widget test**

Append to `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_overflow_menu_test.dart`, following the existing pump helper in that file:

```dart
  testWidgets('offers dark view while light is active', (tester) async {
    // ...pump SongReaderOverflowMenu with isDarkActive: false, open the menu
    expect(find.text(AppStrings.songReaderDarkThemeAction), findsOneWidget);
    expect(find.text(AppStrings.songReaderLightThemeAction), findsNothing);
  });

  testWidgets('offers light view while dark is active', (tester) async {
    // ...pump SongReaderOverflowMenu with isDarkActive: true, open the menu
    expect(find.text(AppStrings.songReaderLightThemeAction), findsOneWidget);
  });

  testWidgets('emits toggleTheme when the entry is tapped', (tester) async {
    // ...pump with a recording onSelected, open the menu, tap the entry
    expect(selected, SongReaderOverflowAction.toggleTheme);
  });
```

Fill the pump bodies by copying the existing tests in the same file — they
already build the menu, open it and assert on emitted actions.

- [ ] **Step 10: Run the reader suite**

Run: `cd apps/lyron_app && flutter test test/app/ test/presentation/song_reader/`
Expected: PASS. `song_reader_screen_test.dart` may need the new required
`isDarkActive` argument wherever it constructs the app bar directly.

- [ ] **Step 11: Commit**

```bash
git add apps/lyron_app/lib/src/app/theme_mode_store.dart apps/lyron_app/lib/src/app/lyron_app.dart apps/lyron_app/lib/src/shared/app_strings.dart apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_app_bar.dart apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart apps/lyron_app/test/app/theme_mode_store_test.dart apps/lyron_app/test/presentation/song_reader/widgets/song_reader_overflow_menu_test.dart
git commit -m "feat(theme): let the reader switch between light and dark"
```

---

### Task 4: `SongLineView` reads the tokens

This is the task that matters: `SongLineView` and `measureSongReaderCharWidths` must describe the same styles, and after this task plus Task 7 they read the same object.

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart:20-30`
- Test: `apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_line_view.dart';

/// A deliberately unmistakable token set: if a widget still derives its style
/// from the ambient TextTheme/ColorScheme instead of reading the extension,
/// these values will not appear.
ReaderTheme _markedTokens(ThemeData base) {
  return ReaderTheme.fromM3(
    colorScheme: base.colorScheme,
    textTheme: base.textTheme,
  ).copyWith(
    lyricStyle: const TextStyle(fontSize: 31, color: Color(0xFFAA0001)),
    chordStyle: const TextStyle(fontSize: 29, color: Color(0xFFAA0002)),
  );
}

ThemeData _themeWith(ReaderTheme Function(ThemeData) tokens) {
  final base = buildLightTheme();
  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[tokens(base)],
  );
}

void main() {
  testWidgets('SongLineView styles chords and lyrics from ReaderTheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _themeWith(_markedTokens),
        home: const Scaffold(
          body: SongLineView(
            line: SongReaderLyricLineProjection(
              segments: [
                SongReaderSegmentProjection(
                  text: 'lyric',
                  displayChord: 'Am',
                ),
              ],
            ),
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1,
          ),
        ),
      ),
    );

    final lyric = tester.widget<Text>(find.text('lyric'));
    final chord = tester.widget<Text>(find.text('Am'));

    expect(lyric.style!.fontSize, 31);
    expect(lyric.style!.color, const Color(0xFFAA0001));
    expect(chord.style!.fontSize, 29);
    expect(chord.style!.color, const Color(0xFFAA0002));
  });

  testWidgets('SongLineView still multiplies the base size by the font scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _themeWith(_markedTokens),
        home: const Scaffold(
          body: SongLineView(
            line: SongReaderLyricLineProjection(
              segments: [
                SongReaderSegmentProjection(
                  text: 'lyric',
                  displayChord: 'Am',
                ),
              ],
            ),
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 2,
          ),
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('lyric')).style!.fontSize, 62);
    expect(tester.widget<Text>(find.text('Am')).style!.fontSize, 58);
  });
}
```

Note for the implementer: check the real constructor signatures of `SongReaderLyricLineProjection` and `SongReaderSegmentProjection` in `song_reader_projection.dart` before running, and adjust the fixture to match — the names above are what the reader uses at `song_line_view.dart:113` and `song_reader_section_grid.dart:206`, but the required arguments may differ.

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/reader_theme_adoption_test.dart`
Expected: FAIL — the reported font sizes are 16 and 14 (the M3 defaults), not 31 and 29.

- [ ] **Step 3: Change `SongLineView`**

Replace `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart:21-30` with:

```dart
    final tokens = ReaderTheme.of(context);
    final chordStyle = tokens.chordStyle.copyWith(
      fontSize: (tokens.chordStyle.fontSize ?? 14) * sharedFontScale,
    );
    final lyricStyle = tokens.lyricStyle.copyWith(
      fontSize: (tokens.lyricStyle.fontSize ?? 16) * sharedFontScale,
    );
```

Add the import:

```dart
import 'package:lyron_app/src/app/reader_theme.dart';
```

and delete the now-unused `final theme = Theme.of(context);` line.

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/reader_theme_adoption_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the estimator consistency suites**

Run:
```bash
cd apps/lyron_app && flutter test \
  test/presentation/song_reader/song_line_view_estimate_consistency_test.dart \
  test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart \
  test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart
```
Expected: PASS, no ceiling changed. If any fixture goes red here, the tokens are not reproducing today's styles — fix `ReaderTheme.fromM3`, do not adjust the fixture.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart
git commit -m "refactor(reader): style song lines from ReaderTheme"
```

---

### Task 5: Section headers and the leading directive line

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart:190-201, 233-255`
- Test: `apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `reader_theme_adoption_test.dart`, and extend `_markedTokens` with:

```dart
    sectionLabelStyle: const TextStyle(fontSize: 27, color: Color(0xFFAA0003)),
    unknownSectionLabelColor: const Color(0xFFAA0004),
    leadingDirectiveStyle: const TextStyle(fontSize: 25, color: Color(0xFFAA0005)),
```

```dart
  testWidgets('the section header uses the ReaderTheme label style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _themeWith(_markedTokens),
        home: Scaffold(
          body: SongReaderSectionGrid(
            leadingDirectiveText: 'Capo 2',
            sections: [
              SongReaderSectionProjection(
                label: 'Verse',
                number: 1,
                isUnknown: false,
                lines: const [],
              ),
            ],
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1,
            columnCount: 1,
            availableHeight: 600,
          ),
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('Verse 1')).style!.fontSize, 27);
    expect(
      tester.widget<Text>(find.text('Verse 1')).style!.color,
      const Color(0xFFAA0003),
    );
    expect(tester.widget<Text>(find.text('Capo 2')).style!.color,
        const Color(0xFFAA0005));
  });

  testWidgets('an unrecognised section kind uses the unknown label colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _themeWith(_markedTokens),
        home: Scaffold(
          body: SongReaderSectionGrid(
            sections: [
              SongReaderSectionProjection(
                label: 'Interlude',
                number: null,
                isUnknown: true,
                lines: const [],
              ),
            ],
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1,
            columnCount: 1,
            availableHeight: 600,
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('Interlude')).style!.color,
      const Color(0xFFAA0004),
    );
  });
```

Note for the implementer: `SongReaderSectionProjection`'s real constructor is in `song_reader_projection.dart`; match its required arguments. `song_reader_section_grid_test.dart` already builds these fixtures — copy the shape from there rather than inventing one.

- [ ] **Step 2: Run and confirm failure**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/reader_theme_adoption_test.dart`
Expected: FAIL on the font size (22, the `titleLarge` default) and on both colours.

- [ ] **Step 3: Change the grid**

`_buildHeaderWidget` (line 190) becomes:

```dart
  Widget _buildHeaderWidget(FlowBlock block, BuildContext context) {
    final tokens = ReaderTheme.of(context);
    final section = sections[block.sectionIndex];
    final label = _sectionLabel(section)!;
    return Text(
      label,
      style: section.isUnknown
          ? tokens.sectionLabelStyle.copyWith(
              color: tokens.unknownSectionLabelColor,
            )
          : tokens.sectionLabelStyle,
    );
  }
```

`_DirectiveLine.build` (line 239) becomes:

```dart
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        key: const Key('song-reader-capo-directive-line'),
        style: ReaderTheme.of(context).leadingDirectiveStyle,
      ),
    );
  }
```

Add the `reader_theme.dart` import and drop any now-unused `theme` locals.

- [ ] **Step 4: Run and confirm pass**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/reader_theme_adoption_test.dart test/presentation/song_reader/widgets/song_reader_section_grid_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart
git commit -m "refactor(reader): style section headers and the capo line from ReaderTheme"
```

---

### Task 6: Comment, inline directive and tab views

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/comment_line_view.dart:15-27`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/directive_line_view.dart:10-25`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/tab_block_view.dart:15-28`
- Test: `apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart`

- [ ] **Step 1: Write the failing test**

Extend `_markedTokens` with:

```dart
    commentStyle: const TextStyle(fontSize: 23, color: Color(0xFFAA0006)),
    directiveStyle: const TextStyle(fontSize: 21, color: Color(0xFFAA0007)),
    tabStyle: const TextStyle(fontSize: 19, color: Color(0xFFAA0008)),
    tabBackgroundColor: const Color(0xFFAA0009),
```

```dart
  testWidgets('comment, directive and tab views read ReaderTheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _themeWith(_markedTokens),
        home: Scaffold(
          body: Column(
            children: [
              CommentLineView(
                projection: const SongReaderCommentProjection(text: 'note'),
                sharedFontScale: 1,
              ),
              const DirectiveLineView(
                projection: SongReaderDirectiveProjection(
                  name: 'tempo',
                  value: '72',
                ),
              ),
              TabBlockView(
                projection: const SongReaderTabProjection(rawLines: ['e|--0--']),
                sharedFontScale: 1,
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('note')).style!.color,
        const Color(0xFFAA0006));
    expect(tester.widget<Text>(find.text('{tempo: 72}')).style!.color,
        const Color(0xFFAA0007));
    expect(tester.widget<Text>(find.text('e|--0--')).style!.color,
        const Color(0xFFAA0008));

    final container = tester.widget<Container>(
      find.ancestor(
        of: find.text('e|--0--'),
        matching: find.byType(Container),
      ).first,
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      const Color(0xFFAA0009),
    );
  });
```

- [ ] **Step 2: Run and confirm failure**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/reader_theme_adoption_test.dart`
Expected: FAIL on all four colour assertions.

- [ ] **Step 3: Change the three widgets**

`comment_line_view.dart` build body:

```dart
  @override
  Widget build(BuildContext context) {
    final style = ReaderTheme.of(context).commentStyle;
    return Text(
      projection.text,
      style: style.copyWith(
        fontSize: (style.fontSize ?? 14) * sharedFontScale,
      ),
    );
  }
```

`directive_line_view.dart` build body:

```dart
  @override
  Widget build(BuildContext context) {
    final label = projection.value != null
        ? '{${projection.name}: ${projection.value}}'
        : '{${projection.name}}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(label, style: ReaderTheme.of(context).directiveStyle),
    );
  }
```

`tab_block_view.dart` build body, replacing lines 16-28:

```dart
    final tokens = ReaderTheme.of(context);
    final textStyle = tokens.tabStyle.copyWith(
      fontSize: (tokens.tabStyle.fontSize ?? 13) * sharedFontScale,
    );
    return Container(
      decoration: BoxDecoration(
        color: tokens.tabBackgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
```

Add the `reader_theme.dart` import to each file and drop the unused `theme` locals.

- [ ] **Step 4: Run and confirm pass**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/`
Expected: PASS across the directory.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/widgets/comment_line_view.dart apps/lyron_app/lib/src/presentation/song_reader/widgets/directive_line_view.dart apps/lyron_app/lib/src/presentation/song_reader/widgets/tab_block_view.dart apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart
git commit -m "refactor(reader): style comment, directive and tab blocks from ReaderTheme"
```

---

### Task 7: The fit estimator's char metrics read the same tokens

This closes the loop the PR exists for.

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_char_metrics.dart:125-162`
- Test: `apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets(
    'measureSongReaderCharWidths measures the styles ReaderTheme declares, '
    'not the ambient TextTheme',
    (tester) async {
      late SongReaderCharWidths widths;

      await tester.pumpWidget(
        MaterialApp(
          theme: _themeWith(_markedTokens),
          home: Builder(
            builder: (context) {
              widths = measureSongReaderCharWidths(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // The marked tokens set lyric 31 / chord 29 / header 27; the M3 defaults
      // would report 16 / 14 / 22.
      expect(widths.textScale.lyricBaseFontSize, 31);
      expect(widths.textScale.chordBaseFontSize, 29);
      expect(widths.textScale.headerBaseFontSize, 27);
      expect(widths.textScale.inlineDirectiveBaseFontSize, 21);
    },
  );
```

Add the imports `song_reader_char_metrics.dart` and `song_reader_fit.dart` to the test file.

- [ ] **Step 2: Run and confirm failure**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/reader_theme_adoption_test.dart`
Expected: FAIL — reports 16 / 14 / 22 / 12.

- [ ] **Step 3: Change `measureSongReaderCharWidths`**

Replace lines 126-135 of `song_reader_char_metrics.dart`:

```dart
  final tokens = ReaderTheme.of(context);
  final textScaler = MediaQuery.textScalerOf(context);
  final chordStyle = tokens.chordStyle;
  final lyricStyle = tokens.lyricStyle;
  final headerStyle = tokens.sectionLabelStyle;
```

and lines 154-161:

```dart
    textScale: SongReaderFitTextScale(
      textScaler: textScaler,
      lyricBaseFontSize: lyricStyle.fontSize ?? 16.0,
      chordBaseFontSize: chordStyle.fontSize ?? 14.0,
      headerBaseFontSize: headerStyle.fontSize ?? 22.0,
      inlineDirectiveBaseFontSize: tokens.directiveStyle.fontSize ?? 12.0,
    ),
```

Add the `reader_theme.dart` import. Update the class doc comment: the paragraph that describes the styles as `labelLarge + w700` / `bodyLarge + height: 1.25` must now say that the styles come from `ReaderTheme`, and say why — that this is what keeps the estimator and the renderer from drifting.

- [ ] **Step 4: Run the consistency suites**

Run:
```bash
cd apps/lyron_app && flutter test \
  test/presentation/song_reader/song_line_view_estimate_consistency_test.dart \
  test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart \
  test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart \
  test/presentation/song_reader/song_reader_fit_test.dart \
  test/presentation/song_reader/song_reader_fit_to_screen_test.dart \
  test/presentation/song_reader/reader_theme_adoption_test.dart
```
Expected: PASS, and no fixture ceiling changed. A red fixture here means the tokens do not reproduce today's styles; fix the tokens, never the fixture.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/song_reader_char_metrics.dart apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart
git commit -m "refactor(reader): measure char widths from the same tokens the renderer draws with"
```

---

### Task 8: A dark-theme rendering test

**Files:**
- Test: `apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart`

- [ ] **Step 1: Write the test**

```dart
  testWidgets('the dark theme renders the reader with the stage palette', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: SongLineView(
            line: SongReaderLyricLineProjection(
              segments: [
                SongReaderSegmentProjection(text: 'lyric', displayChord: 'Am'),
              ],
            ),
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1,
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('lyric')).style!.color,
      const Color(0xFFCDCAC0),
    );
    expect(
      tester.widget<Text>(find.text('Am')).style!.color,
      const Color(0xFF7ACFA8),
    );
  });
```

- [ ] **Step 2: Run and confirm it passes**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/reader_theme_adoption_test.dart`
Expected: PASS. If it fails, the widget is not reading the extension — go back to Task 4.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart
git commit -m "test(reader): pin the dark stage palette at the render boundary"
```

---

### Task 9: ADR and review-doc closeout

**Files:**
- Create: `docs/architecture/decisions/ADR-033-reader-design-token-layer.md`
- Modify: `docs/architecture/repository-review-2026-06-22.md:80, 1314, 1500`

- [ ] **Step 1: Write the ADR**

Follow the format of `docs/architecture/decisions/ADR-032-no-automatic-provider-retry.md`. It must record:
- **Context:** the renderer and the estimator each re-derived the same text styles by hand, so a typography change could move one without the other; and the dark theme cannot be an inversion, because `#0B6E4F` sits near 2:1 on black.
- **Decision:** one `ReaderTheme` `ThemeExtension` holds the reader's colours and text styles; both the renderer and `measureSongReaderCharWidths` read it. Spacing stays in `song_reader_metrics.dart` / `song_reader_fit.dart` and is not duplicated into the extension.
- **Consequences:** typography changes now have one edit point (which PR2 depends on); a `ThemeData` without the extension falls back to `ReaderTheme.fromM3`, pinned equal to the registered light tokens by `app_theme_test.dart`; reader chrome widgets still read `ColorScheme` directly until PR3.

- [ ] **Step 2: Strike through UX-7**

At `docs/architecture/repository-review-2026-06-22.md:80` and `:1314`, apply the existing `~~struck~~ **Done (...)**` convention used by the already-closed findings in the same tables. Check line 1500's prose reference to dark mode and update it to match.

- [ ] **Step 3: Commit**

```bash
git add docs/architecture/decisions/ADR-033-reader-design-token-layer.md docs/architecture/repository-review-2026-06-22.md
git commit -m "docs(adr): record the reader design-token layer and close UX-7"
```

---

### Task 10: Full verification and visual proof

- [ ] **Step 1: Run the whole gate**

Run: `./scripts/verify.sh`
Expected: green. This includes analyze, the full test suite, the coverage gate and the dependency audit.

- [ ] **Step 2: Bring up the app**

Run: `FLUTTER_DEVICE=web-server ./scripts/run-authenticated-app.sh`
Wait for the Flutter build to report the app is serving, then open the printed single-use magic link, which lands on `http://localhost:8080` already signed in.

- [ ] **Step 3: Screenshot the light reader**

Open a song, at 834x1194 and at 375x812. Compare against the light-theme screenshots in the PR description: these must be **pixel-identical** to the pre-change reader. Any visible difference is a bug in `ReaderTheme.fromM3`, not an improvement.

- [ ] **Step 4: Screenshot the dark reader**

Switch the browser to dark (`resize_window` with `colorScheme: "dark"`, or the OS setting) and reload. Capture the same two widths. Confirm: black page, `#CDCAC0` lyrics, `#7ACFA8` chords, and that the chrome (app bar, control bar, context bar) is legible even though it is not yet designed.

- [ ] **Step 5: Open the PR**

Body must state: light theme pixel-identical, dark theme new, no estimator constant moved, UX-7 closed, and that reader chrome remains Material-default in dark until PR3.

---

## What PR2 will need from this PR

Recorded here so the next session does not have to rediscover it:

- Typography changes are edits to `ReaderTheme.fromM3` / `ReaderTheme.stageDark` plus the spacing constants in `song_reader_metrics.dart` and `song_reader_fit.dart:96-115`. There is no third place.
- `chordChipColor` already exists and is null; PR2 fills it and adds the chip's horizontal padding to **both** the renderer and the chord-width side of the estimator.
- `sectionLabelStyle` gains `letterSpacing` and an uppercase transform in PR2. `measureSongReaderCharWidths` measures `_headerMeasureSample` — that sample must be uppercased there too, or the header width is measured for a string the renderer never draws.
- The lyric weight moves to `w500`; `lyricCharWidth` is measured from `tokens.lyricStyle` after this PR, so the weight change propagates automatically. Verify it did rather than assuming.
- Do not read `docs/deferred/2026-07-28-reader-fit-conservatism-margin.md` end to end — it is 576 lines. Grep it for the measurement tables that need re-measuring (`grep -n "| Line shape\|Rendered | Estimated\|^| " docs/deferred/2026-07-28-reader-fit-conservatism-margin.md`).
