import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';

void main() {
  group('SongReaderMetrics.legacy', () {
    // These are the values the estimator and the renderer used before the
    // metrics became a passed-in value. They are pinned here so that the
    // "inert plumbing" commit cannot silently change behaviour: every other
    // test in the suite measures against these numbers.
    test('reproduces the pre-extraction constants exactly', () {
      const m = SongReaderMetrics.legacy;

      expect(m.lineRunSpacing, 10.0);
      expect(m.chordOnlySpacing, 22.0);
      expect(m.chordToLyricGap, 2.0);
      expect(m.sectionGap, 20.0);
      expect(m.sectionLabelRowHeight, 28.0);
      expect(m.sectionLabelToLineGap, 12.0);
      expect(m.lineGap, 10.0);
      expect(m.chordRowHeight, 20.0);
      expect(m.lyricRowHeight, 24.0);
      expect(m.directiveLineHeight, 36.0);
      expect(m.tabBlockVerticalPadding, 16.0);
      expect(m.lineWidgetBottomPadding, 2.0);
      expect(m.chordChipHorizontalPadding, 0.0);
    });

    test('headerHeight is the label row plus the gap under it', () {
      // The estimator charged a flat headerHeight of 40 while the renderer
      // drew a ~28px label followed by a literal SizedBox(height: 12).
      // Splitting the constant is what lets the renderer stop hardcoding 12.
      expect(SongReaderMetrics.legacy.headerHeight, 40.0);
    });
  });
}
