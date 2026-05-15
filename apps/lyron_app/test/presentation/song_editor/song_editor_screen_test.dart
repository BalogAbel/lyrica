import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_screen.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('wide layout shows the summary and canonical source shells', (
    tester,
  ) async {
    await _pumpScreen(tester, const Size(1440, 1200));

    expect(find.text('Derived summary'), findsOneWidget);
    expect(find.text('Canonical source'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Source'), findsNothing);
    expect(find.text('Overview'), findsNothing);
    expect(
      find.textContaining('ChordPro-first workspace for song'),
      findsNothing,
    );
  });

  testWidgets('wide layout keeps the summary shell compact', (tester) async {
    await _pumpScreen(tester, const Size(1440, 1200));

    final summaryShell = find.byKey(
      const ValueKey('song-editor-overview-shell'),
    );
    expect(summaryShell, findsOneWidget);
    expect(tester.getSize(summaryShell).height, lessThan(420));
  });

  testWidgets(
    'wide layout swaps the canonical block between source and preview',
    (tester) async {
      await _pumpScreen(tester, const Size(1440, 1200));

      expect(
        find.byKey(const ValueKey('song-editor-source-panel')),
        findsOneWidget,
      );
      expect(find.text('Source'), findsNothing);
      expect(find.text('Preview'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('song-editor-preview-panel')),
        findsNothing,
      );

      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('song-editor-source-panel')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('song-editor-preview-panel')),
        findsOneWidget,
      );
      expect(find.text('Source'), findsOneWidget);
      expect(find.text('Preview'), findsNothing);
    },
  );

  testWidgets('wide layout surfaces recoverable parse warnings', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      const Size(1440, 1200),
      initialSource: '''
{title:Example Song}
{comment:<Verse>}
Line one
{unknown:token}
Line two
''',
    );

    expect(
      find.text('Source parsed with 1 recoverable warning(s).'),
      findsOneWidget,
    );
  });

  testWidgets(
    'wide layout preserves the selected canonical view after resize',
    (tester) async {
      await _pumpScreen(tester, const Size(1440, 1200));

      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();

      await _resizeViewport(tester, const Size(820, 1200));

      expect(
        find.byKey(const ValueKey('song-editor-preview-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('song-editor-source-panel')),
        findsNothing,
      );
    },
  );

  testWidgets('transpose and capo controls keep the source textarea in sync', (
    tester,
  ) async {
    await _pumpScreen(tester, const Size(1440, 1200));

    await tester.tap(find.byKey(const ValueKey('transpose-increase')));
    await tester.pumpAndSettle();

    expect(find.textContaining('{transpose: 1}'), findsOneWidget);
    expect(find.widgetWithText(Chip, '+1'), findsOneWidget);
    expect(find.textContaining('Transpose +1 · Capo 0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('capo-increase')));
    await tester.pumpAndSettle();

    expect(find.textContaining('{capo: 1}'), findsOneWidget);
    expect(find.widgetWithText(Chip, '1'), findsOneWidget);
    expect(find.textContaining('Transpose +1 · Capo 1'), findsOneWidget);
  });

  testWidgets('transpose and capo controls preserve source cursor location', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      const Size(1440, 1200),
      initialSource: '''
{title: Heart of Worship}
{comment:<Intro>}
[D]When the music fades
''',
    );
    final textField = tester.widget<TextField>(find.byType(TextField));
    final controller = textField.controller!;
    final lyricOffset = controller.text.indexOf('[D]When');
    controller.selection = TextSelection.collapsed(offset: lyricOffset);

    await tester.tap(find.byKey(const ValueKey('transpose-increase')));
    await tester.pumpAndSettle();

    expect(
      controller.text.substring(controller.selection.baseOffset),
      startsWith('[D]When'),
    );
  });

  testWidgets('dirty back asks before discarding edits', (tester) async {
    await _pumpScreen(tester, const Size(1440, 1200));

    await tester.enterText(find.byType(TextField), '''
{title: Changed Song}
[D]Changed line
''');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('song-editor-back-button')));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.text('You have unsaved song edits.'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
  });

  testWidgets('dirty cancel asks before discarding edits', (tester) async {
    await _pumpScreen(tester, const Size(1440, 1200));

    await tester.enterText(find.byType(TextField), '''
{title: Changed Song}
[D]Changed line
''');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.text('You have unsaved song edits.'), findsOneWidget);
  });

  testWidgets('tablet layout uses overview, source, and preview tabs', (
    tester,
  ) async {
    await _pumpScreen(tester, const Size(820, 1200));

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('song-editor-overview-panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('song-editor-source-panel')),
      findsOneWidget,
    );

    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('song-editor-overview-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('song-editor-source-panel')),
      findsNothing,
    );

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('song-editor-preview-panel')),
      findsOneWidget,
    );
  });

  testWidgets('create mode renders with New song title', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            const UnifiedSyncOverview.initial(),
          ),
        ],
        child: const MaterialApp(
          home: SongEditorScreen.create(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songCreateTitle), findsOneWidget);
    expect(find.text(AppStrings.songEditAction), findsNothing);
  });

  testWidgets('edit mode renders with Edit song title', (tester) async {
    await _pumpScreen(tester, const Size(1440, 1200));
    expect(find.text(AppStrings.songEditAction), findsOneWidget);
    expect(find.text(AppStrings.songCreateTitle), findsNothing);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Size physicalSize, {
  String? initialSource,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = physicalSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        unifiedSyncOverviewProvider.overrideWithValue(
          const UnifiedSyncOverview.initial(),
        ),
      ],
      child: MaterialApp(
        home: SongEditorScreen.edit(
          songId: 'song-1',
          songSlug: 'egy-ut',
          initialSource: initialSource,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _resizeViewport(WidgetTester tester, Size physicalSize) async {
  tester.view.physicalSize = physicalSize;
  await tester.pumpAndSettle();
}
