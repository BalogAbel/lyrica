import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/presentation/song_library/widgets/import_summary_dialog.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows correct imported count', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showImportSummaryDialog(
              context: context,
              result: const ImportBatchResult(
                successes: [
                  ImportSuccess(
                    title: 'Song A',
                    source: '',
                    filename: 'song_a.cho',
                  ),
                  ImportSuccess(
                    title: 'Song B',
                    source: '',
                    filename: 'song_b.cho',
                  ),
                ],
                duplicates: [],
                errors: [],
              ),
              skippedCount: 0,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsWidgets);
    expect(
      find.text(AppStrings.songImportSummaryImportedLabel),
      findsOneWidget,
    );
  });

  testWidgets('shows skipped count', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showImportSummaryDialog(
              context: context,
              result: const ImportBatchResult(
                successes: [],
                duplicates: [],
                errors: [],
              ),
              skippedCount: 3,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsWidgets);
    expect(find.text(AppStrings.songImportSummarySkippedLabel), findsOneWidget);
  });

  testWidgets('shows error filenames when errors exist', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showImportSummaryDialog(
              context: context,
              result: const ImportBatchResult(
                successes: [],
                duplicates: [],
                errors: [
                  ImportError(filename: 'bad.cho', reason: 'Empty file'),
                ],
              ),
              skippedCount: 0,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('bad.cho'), findsOneWidget);
    expect(find.text('Empty file'), findsOneWidget);
  });

  testWidgets('Done button dismisses the dialog', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showImportSummaryDialog(
              context: context,
              result: const ImportBatchResult(
                successes: [],
                duplicates: [],
                errors: [],
              ),
              skippedCount: 0,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songImportSummaryDoneAction));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songImportSummaryTitle), findsNothing);
  });
}
