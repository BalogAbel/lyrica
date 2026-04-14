import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_layout.dart';

void main() {
  test('resolves compact shell for touch-first widths', () {
    final layout = resolveSongReaderLayout(
      viewportWidth: 700,
      sharedFontScale: 1,
      isAutoFitEnabled: true,
    );

    expect(layout.shell, SongReaderShell.compact);
    expect(layout.contentColumnCount, 1);
  });

  test('resolves expanded shell for wide layouts', () {
    final layout = resolveSongReaderLayout(
      viewportWidth: 1280,
      sharedFontScale: 1,
      isAutoFitEnabled: true,
    );

    expect(layout.shell, SongReaderShell.expanded);
  });

  test('keeps one column when auto-fit is disabled', () {
    final layout = resolveSongReaderLayout(
      viewportWidth: 1280,
      sharedFontScale: 1,
      isAutoFitEnabled: false,
    );

    expect(layout.contentColumnCount, 1);
  });

  test('keeps one column when scale is too large for dense layout', () {
    final layout = resolveSongReaderLayout(
      viewportWidth: 1280,
      sharedFontScale: 1.4,
      isAutoFitEnabled: true,
    );

    expect(layout.contentColumnCount, 1);
  });

  test('allows denser layout when width is large and scale stays calm', () {
    final layout = resolveSongReaderLayout(
      viewportWidth: 1280,
      sharedFontScale: 1,
      isAutoFitEnabled: true,
    );

    expect(layout.contentColumnCount, 2);
  });
}
