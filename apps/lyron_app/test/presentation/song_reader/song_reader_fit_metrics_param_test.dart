import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

SongReaderSectionProjection _section() {
  return SongReaderSectionProjection(
    kind: SongSectionKind.verse,
    label: 'Verse',
    number: 1,
    isUnknown: false,
    lines: [
      SongReaderLyricLineProjection(
        segments: const [
          SongReaderSegmentProjection(displayChord: 'C', text: 'one two '),
          SongReaderSegmentProjection(displayChord: 'G', text: 'three four'),
        ],
      ),
    ],
  );
}

double _estimate({SongReaderMetrics? metrics}) {
  if (metrics == null) {
    return estimateSongContentHeight(
      sections: [_section()],
      viewMode: SongReaderViewMode.chordsAndLyrics,
      availableWidth: 300,
      fontScale: 1.0,
    );
  }
  return estimateSongContentHeight(
    sections: [_section()],
    viewMode: SongReaderViewMode.chordsAndLyrics,
    availableWidth: 300,
    fontScale: 1.0,
    metrics: metrics,
  );
}

void main() {
  group('estimator metrics parameter', () {
    test('omitting metrics reproduces the legacy constants', () {
      expect(_estimate(), _estimate(metrics: SongReaderMetrics.legacy));
    });

    test('a taller lyric row raises the estimate', () {
      // Proves the parameter is actually consumed rather than accepted and
      // ignored -- the failure mode a defaulted parameter invites.
      final base = _estimate(metrics: SongReaderMetrics.legacy);
      final taller = _estimate(
        metrics: SongReaderMetrics.legacy.copyWith(lyricRowHeight: 48.0),
      );

      expect(taller, greaterThan(base));
    });

    test('a wider section gap raises the estimate by the delta', () {
      // estimateSectionHeight charges sectionGap exactly once per section, so
      // one section and a +40 gap must move the total by exactly +40. An
      // inequality here would pass even if the gap were charged twice.
      final base = _estimate(metrics: SongReaderMetrics.legacy);
      final wider = _estimate(
        metrics: SongReaderMetrics.legacy.copyWith(sectionGap: 60.0),
      );

      expect(wider, base + 40.0);
    });

    test('a taller section label row raises the estimate', () {
      // headerHeight is derived (sectionLabelRowHeight + sectionLabelToLineGap),
      // so this also pins that the estimator reads the derived getter rather
      // than a separately stored value.
      final base = _estimate(metrics: SongReaderMetrics.legacy);
      final taller = _estimate(
        metrics: SongReaderMetrics.legacy.copyWith(sectionLabelRowHeight: 48.0),
      );

      expect(taller, base + 20.0);
    });
  });
}
