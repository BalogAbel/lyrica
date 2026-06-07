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
  // Expanded shell is reserved for large desktop windows only.
  // Tablets (including landscape mode on ~1280px devices) use the compact
  // shell so they get overlay controls and full-width content.
  const expandedShellMinWidth = 1600.0;
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
