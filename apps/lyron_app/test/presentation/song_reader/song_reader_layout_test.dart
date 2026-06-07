import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_layout.dart';

void main() {
  test('resolves compact shell for touch-first widths', () {
    final layout = resolveSongReaderLayout(
      viewportWidth: 700,
      isAutoFitEnabled: true,
    );

    expect(layout.shell, SongReaderShell.compact);
    expect(layout.contentColumnCount, 1);
  });

  test('resolves compact shell for tablet-width layouts (< 1600)', () {
    final layout = resolveSongReaderLayout(
      viewportWidth: 1280,
      isAutoFitEnabled: true,
    );

    expect(layout.shell, SongReaderShell.compact);
  });

  test('resolves expanded shell for large desktop layouts (>= 1600)', () {
    final layout = resolveSongReaderLayout(
      viewportWidth: 1600,
      isAutoFitEnabled: true,
    );

    expect(layout.shell, SongReaderShell.expanded);
  });

  test('keeps one column when auto-fit is disabled', () {
    final layout = resolveSongReaderLayout(
      viewportWidth: 1280,
      isAutoFitEnabled: false,
    );

    expect(layout.contentColumnCount, 1);
  });

  // The font-scale gate was removed: column count depends only on width + auto-fit.
  // The grid's own useful-split + tolerance guards collapse to 1 column when the
  // font is too large, so the layout resolver no longer needs to know the scale.
  test('allows two columns when width is >= denseLayoutMinWidth and auto-fit on, '
      'regardless of scale', () {
    // Large scale — previously this would have returned 1 column; now it returns 2.
    final layoutLargeScale = resolveSongReaderLayout(
      viewportWidth: 1280,
      isAutoFitEnabled: true,
    );
    expect(layoutLargeScale.contentColumnCount, 2);

    // Small scale — still 2 columns.
    final layoutSmallScale = resolveSongReaderLayout(
      viewportWidth: 1280,
      isAutoFitEnabled: true,
    );
    expect(layoutSmallScale.contentColumnCount, 2);
  });

  test('width exactly at denseLayoutMinWidth boundary uses two columns', () {
    // denseLayoutMinWidth = 1180.0
    final layout = resolveSongReaderLayout(
      viewportWidth: 1180,
      isAutoFitEnabled: true,
    );
    expect(layout.contentColumnCount, 2);
  });

  test('width just below denseLayoutMinWidth uses one column', () {
    final layout = resolveSongReaderLayout(
      viewportWidth: 1179,
      isAutoFitEnabled: true,
    );
    expect(layout.contentColumnCount, 1);
  });
}
