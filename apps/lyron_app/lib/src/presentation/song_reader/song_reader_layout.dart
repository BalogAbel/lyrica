enum SongReaderShell { compact, expanded }

class SongReaderLayout {
  const SongReaderLayout({
    required this.shell,
    required this.contentColumnCount,
  });

  final SongReaderShell shell;
  final int contentColumnCount;
}

SongReaderLayout resolveSongReaderLayout({
  required double viewportWidth,
  required double sharedFontScale,
  required bool isAutoFitEnabled,
}) {
  const expandedShellMinWidth = 1024.0;
  const denseLayoutMinWidth = 1180.0;
  const denseLayoutMaxScale = 1.15;

  final shell = viewportWidth >= expandedShellMinWidth
      ? SongReaderShell.expanded
      : SongReaderShell.compact;
  final canUseDenseLayout =
      isAutoFitEnabled &&
      viewportWidth >= denseLayoutMinWidth &&
      sharedFontScale <= denseLayoutMaxScale;

  return SongReaderLayout(
    shell: shell,
    contentColumnCount: canUseDenseLayout ? 2 : 1,
  );
}
