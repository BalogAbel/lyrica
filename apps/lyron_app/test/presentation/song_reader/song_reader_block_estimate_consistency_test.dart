import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_char_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/comment_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/directive_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/tab_block_view.dart';

// ---------------------------------------------------------------------------
// Full-sweep render-vs-estimate consistency for every NON-lyric-line kind
// the fit estimator assigns a height to.
// ---------------------------------------------------------------------------
//
// Three rounds in a row found the same shape of defect (some rendered
// element wraps/grows in a way the estimator does not model) one fixture at
// a time: first the ambient-scaler flattening, then the chord label's own
// wrap, then the inline directive's 6.3x under-estimate found in passing
// while checking for more of the same. Rather than wait for a fourth
// fixture to stumble onto the next one, this file enumerates every kind
// `_lineItemHeight`'s switch and `flowBlockHeight`'s `FlowBlockKind` switch
// (song_reader_fit.dart) assign a height to, OTHER than the lyric line
// (already covered exhaustively by
// song_line_view_estimate_consistency_test.dart, including its own chord-
// label-wrap case):
//   - comment line              (SongReaderCommentProjection / CommentLineView)
//   - tab block                 (SongReaderTabProjection / TabBlockView)
//   - inline directive          (SongReaderDirectiveProjection / DirectiveLineView)
//   - leading capo/tuning directive (FlowBlockKind.leadingDirective / the
//     grid's private `_DirectiveLine`)
//   - section header            (FlowBlockKind.sectionHeader / the grid's
//     private `_buildHeaderWidget`)
//
// For each, a SHORT instance (should already satisfy the contract trivially)
// and a LONG instance at a narrow width (forcing whatever growth that
// widget is actually capable of) are rendered for real and compared against
// the exact quantity the estimator charges for that kind.

const _viewMode = SongReaderViewMode.chordsAndLyrics;
const _fontScale = 1.0;

void main() {
  group('comment line', () {
    Future<void> runCase(
      WidgetTester tester, {
      required String text,
      required double width,
      required double ceilingMultiplier,
    }) async {
      final projection = SongReaderCommentProjection(text: text);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: CommentLineView(
                  projection: projection,
                  sharedFontScale: _fontScale,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final rendered =
          tester.getSize(find.byType(CommentLineView)).height +
          SongReaderMetrics.legacy.lineGap;
      final charWidths = measureSongReaderCharWidths(
        tester.element(find.byType(CommentLineView)),
      );
      final estimated = flowBlockHeight(
        block: FlowBlock(
          kind: FlowBlockKind.line,
          sectionIndex: 0,
          line: projection,
        ),
        viewMode: _viewMode,
        columnWidth: width,
        fontScale: _fontScale,
        lyricCharWidth: charWidths.lyricCharWidth,
        chordCharWidth: charWidths.chordCharWidth,
        textScale: charWidths.textScale,
      );

      expect(
        estimated,
        greaterThanOrEqualTo(rendered),
        reason:
            'the estimate must never fall below the real render for a '
            'comment line; rendered=$rendered estimated=$estimated',
      );
      expect(
        estimated,
        lessThan(rendered * ceilingMultiplier),
        reason:
            'the estimate must not be uselessly loose either; '
            'rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * ceilingMultiplier}',
      );
    }

    // PRE-FIX (2026-07-28, full-sweep round): rendered=30.0 estimated=34.0
    // (short case already passed -- a flat char-count division degrades to
    // 1 line for short text regardless). POST-FIX: unchanged, 30.0/34.0.
    testWidgets('short comment, wide column', (tester) async {
      await runCase(
        tester,
        text: 'A short comment',
        width: 300.0,
        ceilingMultiplier: 1.3,
      );
    });

    // PRE-FIX: rendered=410.0 estimated=346.0 -- RED, a genuine
    // under-estimate (the plain char-count division undercounted wraps the
    // same way the lyric line's used to, before this file's word-wrap
    // model existed). POST-FIX (word-boundary wrap via _wordWrapLineCount,
    // reusing lyricCharWidth as a conservative proxy -- see the comment
    // case's own doc in song_reader_fit.dart): rendered=410.0
    // estimated=586.0 (ratio 1.43x).
    testWidgets('long comment, narrow column forces several wrapped lines', (
      tester,
    ) async {
      await runCase(
        tester,
        text:
            'This is a much longer comment that describes performance notes '
            'in detail and should wrap across several lines at a narrow '
            'column width, exercising the word-wrap model',
        width: 150.0,
        ceilingMultiplier: 1.5,
      );
    });
  });

  group('tab block', () {
    Future<void> runCase(
      WidgetTester tester, {
      required List<String> rawLines,
      required double width,
      required double ceilingMultiplier,
    }) async {
      final projection = SongReaderTabProjection(rawLines: rawLines);

      // Wrapped in a (vertical) SingleChildScrollView, matching how
      // TabBlockView is always actually used in production (it sits inside
      // the section grid's Column, itself inside the surface's scrollable):
      // TabBlockView's OWN inner Column (widgets/tab_block_view.dart, inside
      // a horizontal-scrolling SingleChildScrollView) defaults to Flutter's
      // `MainAxisSize.max` too, so a bounded incoming height (from a plain
      // Align/Scaffold.body, matching the test viewport's ~600-610px)
      // makes it expand to fill that instead of reporting its real content
      // height -- the exact same measurement bug the grid-based groups
      // below hit, just one level down in a different widget's internal
      // Column.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: TabBlockView(
                    projection: projection,
                    sharedFontScale: _fontScale,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final rendered =
          tester.getSize(find.byType(TabBlockView)).height +
          SongReaderMetrics.legacy.lineGap;
      final charWidths = measureSongReaderCharWidths(
        tester.element(find.byType(TabBlockView)),
      );
      final estimated = flowBlockHeight(
        block: FlowBlock(
          kind: FlowBlockKind.line,
          sectionIndex: 0,
          line: projection,
        ),
        viewMode: _viewMode,
        columnWidth: width,
        fontScale: _fontScale,
        lyricCharWidth: charWidths.lyricCharWidth,
        chordCharWidth: charWidths.chordCharWidth,
        textScale: charWidths.textScale,
      );

      expect(
        estimated,
        greaterThanOrEqualTo(rendered),
        reason:
            'the estimate must never fall below the real render for a tab '
            'block; rendered=$rendered estimated=$estimated',
      );
      expect(
        estimated,
        lessThan(rendered * ceilingMultiplier),
        reason:
            'the estimate must not be uselessly loose either; '
            'rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * ceilingMultiplier}',
      );
    }

    // Tab lines cannot wrap at all (see song_reader_fit.dart's
    // SongReaderTabProjection case doc), so both cases were already green
    // pre-fix and needed no change: short=46.0/50.0, long/narrow
    // (4 long lines, width 100)=106.0/122.0. This IS the "proven tight,
    // leave the constant alone" result the coordinator asked for -- growth
    // was checked, found impossible, and the estimator's existing formula
    // (unmodified here) already proves it.
    testWidgets('single short tab line', (tester) async {
      await runCase(
        tester,
        rawLines: const ['e|--0--|'],
        width: 300.0,
        ceilingMultiplier: 1.3,
      );
    });

    testWidgets(
      'several LONG tab lines at a narrow width -- TabBlockView scrolls '
      'horizontally (SingleChildScrollView(scrollDirection: Axis.horizontal)) '
      'rather than wrapping, so this is expected to be tight, not loose',
      (tester) async {
        await runCase(
          tester,
          rawLines: const [
            'e|-----------------0---------------2---------------3-----------------|',
            'B|-----------------1---------------3---------------0-----------------|',
            'G|-----------------0---------------0---------------0-----------------|',
            'D|-----------------2---------------0---------------0-----------------|',
          ],
          width: 100.0,
          ceilingMultiplier: 1.3,
        );
      },
    );
  });

  group('inline directive', () {
    Future<void> runCase(
      WidgetTester tester, {
      required String name,
      String? value,
      required double width,
      required double ceilingMultiplier,
    }) async {
      final projection = SongReaderDirectiveProjection(
        name: name,
        value: value,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: DirectiveLineView(projection: projection),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final rendered =
          tester.getSize(find.byType(DirectiveLineView)).height +
          SongReaderMetrics.legacy.lineGap;
      final charWidths = measureSongReaderCharWidths(
        tester.element(find.byType(DirectiveLineView)),
      );
      final estimated = flowBlockHeight(
        block: FlowBlock(
          kind: FlowBlockKind.line,
          sectionIndex: 0,
          line: projection,
        ),
        viewMode: _viewMode,
        columnWidth: width,
        fontScale: _fontScale,
        lyricCharWidth: charWidths.lyricCharWidth,
        chordCharWidth: charWidths.chordCharWidth,
        textScale: charWidths.textScale,
      );

      expect(
        estimated,
        greaterThanOrEqualTo(rendered),
        reason:
            'the estimate must never fall below the real render for an '
            'inline directive; rendered=$rendered estimated=$estimated',
      );
      expect(
        estimated,
        lessThan(rendered * ceilingMultiplier),
        reason:
            'the estimate must not be uselessly loose either; '
            'rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * ceilingMultiplier}',
      );
    }

    // PRE-FIX (2026-07-28, full-sweep round): rendered=30.0 estimated=36.0
    // (short case already passed -- the old flat directiveLineHeight
    // constant happens to already cover a one-line label). POST-FIX:
    // unchanged, 30.0/36.0.
    testWidgets('short directive, wide column', (tester) async {
      await runCase(
        tester,
        name: 'capo',
        value: '2',
        width: 300.0,
        ceilingMultiplier: 1.5,
      );
    });

    // PRE-FIX: rendered=238.0 estimated=36.0 -- RED, a 6.6x under-estimate
    // (the flat directiveLineHeight constant never accounted for the
    // directive's own text length at all -- this was the finding reported
    // mid-round that triggered this whole sweep). POST-FIX (word-boundary
    // wrap via _wordWrapLineCount, reusing chordCharWidth as a
    // conservative proxy -- see the SongReaderDirectiveProjection case's
    // own doc in song_reader_fit.dart): rendered=238.0 estimated=540.0
    // (ratio 2.27x -- loose, because chordCharWidth is a much bolder/wider
    // proxy than the real labelMedium style, but never under).
    testWidgets('long directive value at a narrow column forces word wrap', (
      tester,
    ) async {
      await runCase(
        tester,
        name: 'comment',
        value:
            'This is an extremely long directive comment value that '
            'should in principle wrap across several lines if the width '
            'is narrow',
        width: 150.0,
        ceilingMultiplier: 2.5,
      );
    });
  });

  group('leading capo/tuning directive', () {
    Future<void> runCase(
      WidgetTester tester, {
      required String text,
      required double width,
      required double ceilingMultiplier,
    }) async {
      // Wrapped in a SingleChildScrollView, matching how the grid is always
      // actually used in production (song_reader_expanded_surface.dart /
      // song_reader_compact_surface.dart both scroll it) -- a scrollable
      // gives its child UNBOUNDED height, so the grid's Column (which uses
      // Flutter's default `mainAxisSize: MainAxisSize.max`) sizes to its
      // children's real intrinsic height instead of expanding to fill
      // whatever bounded height a plain Align/Scaffold.body would offer
      // (which would silently report the test viewport's height instead of
      // the grid's actual content height).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: SongReaderSectionGrid(
                    leadingDirectiveText: text,
                    sections: const [],
                    viewMode: _viewMode,
                    sharedFontScale: _fontScale,
                    columnCount: 1,
                    availableHeight: 4000,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Real render: the whole grid, with an empty sections list, is
      // exactly the leading directive block: its own Text plus the literal
      // `SizedBox(height: sectionGap)` _buildBlockWidgets inserts after it
      // (song_reader_section_grid.dart) -- the SAME sectionGap constant
      // flowBlockHeight's leadingDirective branch charges, so this is a
      // full, literal comparison, not just the bare text height.
      final rendered = tester
          .getSize(find.byType(SongReaderSectionGrid))
          .height;
      final charWidths = measureSongReaderCharWidths(
        tester.element(find.byType(SongReaderSectionGrid)),
      );
      final estimated = flowBlockHeight(
        block: FlowBlock(
          kind: FlowBlockKind.leadingDirective,
          sectionIndex: -1,
          blockText: text,
        ),
        viewMode: _viewMode,
        columnWidth: width,
        fontScale: _fontScale,
        lyricCharWidth: charWidths.lyricCharWidth,
        chordCharWidth: charWidths.chordCharWidth,
        textScale: charWidths.textScale,
      );

      expect(
        estimated,
        greaterThanOrEqualTo(rendered),
        reason:
            'the estimate must never fall below the real render for the '
            'leading directive; rendered=$rendered estimated=$estimated',
      );
      expect(
        estimated,
        lessThan(rendered * ceilingMultiplier),
        reason:
            'the estimate must not be uselessly loose either; '
            'rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * ceilingMultiplier}',
      );
    }

    // PRE-FIX (2026-07-28, full-sweep round): rendered=44.0 estimated=56.0
    // (short case already passed). POST-FIX: unchanged, 44.0/56.0.
    testWidgets('short capo text, wide column', (tester) async {
      await runCase(
        tester,
        text: 'Capo: 2',
        width: 300.0,
        ceilingMultiplier: 1.5,
      );
    });

    // PRE-FIX: rendered=304.0 estimated=56.0 -- RED, a 5.4x under-estimate
    // (same flat-constant gap as the inline directive above, just the
    // OTHER directive widget: _DirectiveLine, song_reader_section_grid.dart).
    // POST-FIX (word-boundary wrap, reusing chordCharWidth -- see
    // flowBlockHeight's FlowBlockKind.leadingDirective case doc):
    // rendered=304.0 estimated=560.0 (ratio 1.84x).
    testWidgets('long capo/tuning text at a narrow column forces word wrap', (
      tester,
    ) async {
      await runCase(
        tester,
        text:
            'Capo: 2, Tuning: Drop D, and also play the intro fingerstyle '
            'with a capo on the second fret throughout the whole song',
        width: 150.0,
        ceilingMultiplier: 2.0,
      );
    });
  });

  group('section header', () {
    Future<void> runCase(
      WidgetTester tester, {
      required String label,
      required double width,
      required double ceilingMultiplier,
    }) async {
      // See the leading-directive group above for why this must be wrapped
      // in a SingleChildScrollView (the grid's Column defaults to
      // MainAxisSize.max, which expands to fill a bounded parent instead of
      // reporting its real content height).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: SongReaderSectionGrid(
                    sections: [
                      SongReaderSectionProjection(
                        kind: SongSectionKind.verse,
                        label: label,
                        number: null,
                        isUnknown: false,
                        lines: const [],
                      ),
                    ],
                    viewMode: _viewMode,
                    sharedFontScale: _fontScale,
                    columnCount: 1,
                    availableHeight: 4000,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Real render: a single header-only section (no lines) is exactly the
      // header block: its own Text plus the literal `SizedBox(height: 12)`
      // _buildBlockWidgets inserts after every header
      // (song_reader_section_grid.dart) -- NOT the sectionGap constant the
      // estimator charges here (a pre-existing, harmless mismatch: the
      // estimator's 20px is already MORE conservative than the render's
      // literal 12px, unrelated to whether the header TEXT itself wraps
      // correctly, which is what this fixture is actually testing).
      final rendered = tester
          .getSize(find.byType(SongReaderSectionGrid))
          .height;
      final charWidths = measureSongReaderCharWidths(
        tester.element(find.byType(SongReaderSectionGrid)),
      );
      final estimated = flowBlockHeight(
        block: FlowBlock(
          kind: FlowBlockKind.sectionHeader,
          sectionIndex: 0,
          isSectionStart: true,
          blockText: label,
        ),
        viewMode: _viewMode,
        columnWidth: width,
        fontScale: _fontScale,
        lyricCharWidth: charWidths.lyricCharWidth,
        chordCharWidth: charWidths.chordCharWidth,
        headerCharWidth: charWidths.headerCharWidth,
        textScale: charWidths.textScale,
      );

      expect(
        estimated,
        greaterThanOrEqualTo(rendered),
        reason:
            'the estimate must never fall below the real render for a '
            'section header; rendered=$rendered estimated=$estimated',
      );
      expect(
        estimated,
        lessThan(rendered * ceilingMultiplier),
        reason:
            'the estimate must not be uselessly loose either; '
            'rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * ceilingMultiplier}',
      );
    }

    // PRE-FIX (2026-07-28, full-sweep round): rendered=40.0 estimated=60.0
    // (short case already passed). POST-FIX: unchanged, 40.0/60.0.
    testWidgets('short label, wide column', (tester) async {
      await runCase(
        tester,
        label: 'Verse',
        width: 300.0,
        ceilingMultiplier: 1.75,
      );
    });

    // PRE-FIX: rendered=404.0 estimated=60.0 -- RED, a 6.7x under-estimate
    // (the flat headerHeight constant never accounted for the section
    // label's own text length -- ChordPro section directives can carry an
    // arbitrary custom label, e.g. `{start_of_verse: <label>}`, so this is
    // not a hypothetical). POST-FIX (word-boundary wrap via
    // _wordWrapLineCount, using titleLarge's own genuinely measured
    // headerCharWidth -- see SongReaderCharWidths.headerCharWidth doc for
    // why, unlike the directive kinds, no existing measurement is a safe
    // proxy here): rendered=404.0 estimated=660.0 (ratio 1.63x).
    testWidgets('long custom section label at a narrow column forces word wrap '
        '(ChordPro section directives can carry an arbitrary custom label)', (
      tester,
    ) async {
      await runCase(
        tester,
        label:
            'An Extremely Long Custom Section Label From A ChordPro '
            'start_of_verse Directive',
        width: 150.0,
        ceilingMultiplier: 1.75,
      );
    });
  });
}
