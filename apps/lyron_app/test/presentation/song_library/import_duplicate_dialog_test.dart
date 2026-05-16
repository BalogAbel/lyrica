import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/presentation/song_library/widgets/import_duplicate_dialog.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

const _dup1 = ImportDuplicate(
  filename: 'ag.cho',
  incomingSource: '{title: Amazing Grace}',
  incomingTitle: 'Amazing Grace',
  existingSongId: 'song-1',
  existingTitle: 'Amazing Grace',
);

const _dup2 = ImportDuplicate(
  filename: 'ht.cho',
  incomingSource: '{title: Holy, Holy, Holy}',
  incomingTitle: 'Holy, Holy, Holy',
  existingSongId: 'song-2',
  existingTitle: 'Holy, Holy, Holy',
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders both duplicate rows', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              await showImportDuplicateDialog(
                context: context,
                duplicates: [_dup1, _dup2],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Amazing Grace'), findsWidgets);
    expect(find.text('Holy, Holy, Holy'), findsWidgets);
  });

  testWidgets('default resolution is skip; confirm returns skips', (tester) async {
    List<ResolvedDuplicate>? result;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImportDuplicateDialog(
                context: context,
                duplicates: [_dup1],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songImportDuplicateConfirmAction));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    expect(result!.single.resolution, DuplicateResolution.skip);
  });

  testWidgets('"Overwrite all" sets all items to overwrite', (tester) async {
    List<ResolvedDuplicate>? result;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImportDuplicateDialog(
                context: context,
                duplicates: [_dup1, _dup2],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songImportDuplicateOverwriteAllAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songImportDuplicateConfirmAction));
    await tester.pumpAndSettle();

    expect(result, hasLength(2));
    expect(result!.every((r) => r.resolution == DuplicateResolution.overwrite), isTrue);
  });

  testWidgets('per-item toggle changes individual resolution', (tester) async {
    List<ResolvedDuplicate>? result;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImportDuplicateDialog(
                context: context,
                duplicates: [_dup1, _dup2],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final overwriteButtons = find.text(AppStrings.songImportDuplicateOverwriteAction);
    await tester.tap(overwriteButtons.first);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.songImportDuplicateConfirmAction));
    await tester.pumpAndSettle();

    expect(result, hasLength(2));
    expect(result![0].resolution, DuplicateResolution.overwrite);
    expect(result![1].resolution, DuplicateResolution.skip);
  });
}
