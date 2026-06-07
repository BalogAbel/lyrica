import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';

enum SongReaderShell { compact, expanded }

class SongReaderLayout {
  const SongReaderLayout({
    required this.shell,
    required this.contentColumnCount,
  });

  final SongReaderShell shell;
  final int contentColumnCount;
}

/// Resolves the shell type and content column count for the given viewport.
///
/// Column count depends only on width + auto-fit, NOT on font scale. The
/// grid's own useful-split and tolerance guards already collapse to 1 column
/// when the font is too large, so the layout resolver must not second-guess
/// them — doing so was the root cause of the double-tap fit overflow bug.
///
/// [denseLayoutMinWidth] is imported from song_reader_fit.dart so all three
/// components (layout resolver, fit calculator, section grid) share a single
/// constant. There is no import cycle: song_reader_fit.dart does not import
/// song_reader_layout.dart.
SongReaderLayout resolveSongReaderLayout({
  required double viewportWidth,
  required bool isAutoFitEnabled,
}) {
  // Expanded shell is reserved for large desktop windows only.
  // Tablets (including landscape mode on ~1280px devices) use the compact
  // shell so they get overlay controls and full-width content.
  const expandedShellMinWidth = 1600.0;

  final shell = viewportWidth >= expandedShellMinWidth
      ? SongReaderShell.expanded
      : SongReaderShell.compact;
  final allowTwoColumns =
      isAutoFitEnabled && viewportWidth >= denseLayoutMinWidth;

  return SongReaderLayout(
    shell: shell,
    contentColumnCount: allowTwoColumns ? 2 : 1,
  );
}
