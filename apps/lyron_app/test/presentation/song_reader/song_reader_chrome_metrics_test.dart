import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_chrome_metrics.dart';

void main() {
  group('SongReaderChromeMetrics.resolve', () {
    test('phone width (599, just below the breakpoint) uses 58', () {
      final metrics = SongReaderChromeMetrics.resolve(599);
      expect(metrics.bottomBarHeight, 58.0);
    });

    test('exactly at the breakpoint (600) uses 64', () {
      final metrics = SongReaderChromeMetrics.resolve(600);
      expect(metrics.bottomBarHeight, 64.0);
    });

    test('just above the breakpoint (601) uses 64', () {
      final metrics = SongReaderChromeMetrics.resolve(601);
      expect(metrics.bottomBarHeight, 64.0);
    });

    test('top bar height follows the same phone/tablet split', () {
      expect(SongReaderChromeMetrics.resolve(599).topBarHeight, 58.0);
      expect(SongReaderChromeMetrics.resolve(600).topBarHeight, 64.0);
      expect(SongReaderChromeMetrics.resolve(601).topBarHeight, 64.0);
    });

    test('rail edge inset is constant across the breakpoint', () {
      expect(SongReaderChromeMetrics.resolve(599).railEdgeInset, 12.0);
      expect(SongReaderChromeMetrics.resolve(600).railEdgeInset, 12.0);
      expect(SongReaderChromeMetrics.resolve(601).railEdgeInset, 12.0);
    });
  });

  group('SongReaderChromeMetrics equality', () {
    test('equal values are ==', () {
      const a = SongReaderChromeMetrics(
        bottomBarHeight: 58.0,
        topBarHeight: 58.0,
        railEdgeInset: 12.0,
      );
      const b = SongReaderChromeMetrics(
        bottomBarHeight: 58.0,
        topBarHeight: 58.0,
        railEdgeInset: 12.0,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing values are not ==', () {
      const a = SongReaderChromeMetrics(
        bottomBarHeight: 58.0,
        topBarHeight: 58.0,
        railEdgeInset: 12.0,
      );
      const b = SongReaderChromeMetrics(
        bottomBarHeight: 64.0,
        topBarHeight: 58.0,
        railEdgeInset: 12.0,
      );
      expect(a == b, isFalse);
    });
  });
}
