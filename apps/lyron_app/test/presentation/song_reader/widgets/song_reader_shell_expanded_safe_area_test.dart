// The chrome restructure (song-presentation slice, PR4) removed the blanket
// `SafeArea` that used to wrap the whole reader body and replaced it with
// per-surface inset handling -- but that per-surface handling only exists on
// the COMPACT shell's three chrome widgets (top bar, bottom bar, control
// rail). The EXPANDED shell (>= 1600px, ADR-034) keeps its pre-restructure
// chrome and has no inset handling of its own: `Scaffold.appBar` only ever
// consumed the top inset, so without an explicit `SafeArea` around the
// expanded body, the surface and its side context/tools panels would render
// under the bottom/left/right insets on, e.g., an iPad in landscape.
//
// These tests pin `SongReaderBodyShell`'s fix: a `SafeArea` around the
// expanded path only, restoring its pre-branch behaviour without
// reintroducing the blanket `SafeArea` the restructure exists to remove from
// the compact path.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_layout.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_shell.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_top_bar.dart';

const Size _expandedSize = Size(1920, 1200);
const Size _compactSize = Size(834, 1194);

// A landscape-notch-shaped inset: nonzero on every side, distinguishable
// from a zero default so a widget that silently drops the inset shows up as
// a geometry failure rather than a coincidental pass.
const EdgeInsets _viewPadding = EdgeInsets.fromLTRB(40, 24, 60, 34);

SongReaderResult _result() => SongReaderResult(
  song: ParsedSong(
    title: 'Reader Song',
    sourceKey: 'G',
    sections: const [],
    diagnostics: const [],
  ),
);

Widget _buildShell({
  required Size size,
  EdgeInsets viewPadding = EdgeInsets.zero,
  bool scoped = false,
}) {
  final layout = resolveSongReaderLayout(
    viewportWidth: size.width,
    isAutoFitEnabled: true,
  );

  final shell = SongReaderBodyShell(
    isResolvingCatalogContext: false,
    readerAsync: AsyncValue.data(_result()),
    isScopedMode: scoped,
    catalogState: const CatalogSnapshotState.initial(),
    mutationRecord: null,
    resolvedScopedContext: scoped
        ? const SessionScopedReaderContext(
            planId: 'plan-1',
            planSlug: 'plan-1',
            sessionId: 'session-1',
            sessionSlug: 'session-1',
            sessionItemId: 'item-1',
            songId: 'song-1',
            selectedItem: SessionScopedReaderNeighbor(
              sessionItemId: 'item-1',
              songId: 'song-1',
              title: 'Reader Song',
            ),
            previousItem: SessionScopedReaderNeighbor(
              sessionItemId: 'item-0',
              songId: 'song-0',
              title: 'Previous Song',
            ),
            nextItem: SessionScopedReaderNeighbor(
              sessionItemId: 'item-2',
              songId: 'song-2',
              title: 'Next Song',
            ),
            position: 2,
            itemCount: 3,
          )
        : null,
    readerState: SongReaderState(),
    preservedScopedTitle: 'Reader Song',
    onBack: (_) {},
    onRetry: () {},
    onTransposeDown: () {},
    onTransposeUp: () {},
    onCapoDown: () {},
    onCapoUp: () {},
    onAdjustSharedFontScale: (_) {},
    onSetFontScale: (_) {},
    onPersistFontScale: () {},
    onToggleCompactControls: () {},
    resolveNeighborTap: (context, neighbor) => null,
    compactTopBar: SongReaderTopBar(
      title: 'Reader Song',
      onBack: () {},
      showOverflowMenu: false,
      viewMode: SongReaderViewMode.chordsAndLyrics,
      canEditSongs: false,
      isDarkActive: false,
    ),
    shellLayout: layout,
  );

  return MaterialApp(
    home: MediaQuery(
      // `SafeArea` (unlike the compact chrome widgets, which deliberately
      // read `viewPadding` -- see song_reader_chrome_safe_area_test.dart)
      // consumes `MediaQuery.padding`, so both must carry the inset here.
      data: MediaQueryData(
        size: size,
        viewPadding: viewPadding,
        padding: viewPadding,
      ),
      child: Scaffold(body: shell),
    ),
  );
}

void main() {
  group('expanded shell safe area', () {
    testWidgets('gets its own SafeArea', (tester) async {
      await tester.pumpWidget(
        _buildShell(size: _expandedSize, viewPadding: _viewPadding),
      );

      expect(find.byType(SafeArea), findsOneWidget);
    });

    testWidgets('the tools panel stays clear of the right and bottom insets', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildShell(size: _expandedSize, viewPadding: _viewPadding),
      );

      final panelRect = tester.getRect(
        find.byType(SongReaderExpandedToolsPanel),
      );

      expect(
        panelRect.right,
        lessThanOrEqualTo(_expandedSize.width - _viewPadding.right),
        reason: 'the tools panel must not render under the right-edge inset',
      );
      expect(
        panelRect.bottom,
        lessThanOrEqualTo(_expandedSize.height - _viewPadding.bottom),
        reason: 'the tools panel must not render under the bottom-edge inset',
      );
    });

    testWidgets('the context panel stays clear of the left inset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildShell(
          size: _expandedSize,
          viewPadding: _viewPadding,
          scoped: true,
        ),
      );

      final panelRect = tester.getRect(
        find.byType(SongReaderExpandedContextPanel),
      );

      expect(
        panelRect.left,
        greaterThanOrEqualTo(_viewPadding.left),
        reason: 'the context panel must not render under the left-edge inset',
      );
    });
  });

  group('compact shell keeps no blanket SafeArea', () {
    testWidgets('does not wrap the compact body in a SafeArea', (tester) async {
      await tester.pumpWidget(
        _buildShell(size: _compactSize, viewPadding: _viewPadding),
      );

      // The whole point of the restructure this ADR is part of: the compact
      // shell's chrome surfaces each own the inset they sit against, so an
      // ancestor SafeArea must not reappear and eat it out from under them.
      expect(find.byType(SafeArea), findsNothing);
    });
  });
}
