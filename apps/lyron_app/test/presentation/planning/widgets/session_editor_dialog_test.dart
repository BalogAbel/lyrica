import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/planning/widgets/session_editor_dialog.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Widget _harness({
  String initialName = '',
  required ValueChanged<String?> onResult,
}) {
  return ProviderScope(
    overrides: [
      activePlanningContextProvider.overrideWithValue(
        const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showDialog<String>(
                context: context,
                builder: (_) => SessionEditorDialog(initialName: initialName),
              );
              onResult(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the create title when initialName is empty', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(onResult: (_) {}));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(AlertDialog, AppStrings.sessionEditorTitleCreate),
      findsOneWidget,
    );
  });

  testWidgets('shows the rename title and pre-fills the name when renaming', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(initialName: 'Warm-Up', onResult: (_) {}));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(AlertDialog, AppStrings.sessionEditorTitleRename),
      findsOneWidget,
    );
    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey('session-editor-name')),
    );
    expect(nameField.controller?.text, 'Warm-Up');
  });

  testWidgets('reports the trimmed name when saved', (tester) async {
    String? reported;

    await tester.pumpWidget(_harness(onResult: (name) => reported = name));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('session-editor-name')),
      '  Closing  ',
    );
    await tester.tap(find.text(AppStrings.planSaveAction));
    await tester.pumpAndSettle();

    expect(reported, 'Closing');
  });

  testWidgets('returns an empty string for whitespace-only input', (
    tester,
  ) async {
    String? reported = 'unset';
    var called = false;

    await tester.pumpWidget(
      _harness(
        onResult: (name) {
          reported = name;
          called = true;
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('session-editor-name')),
      '   ',
    );
    await tester.tap(find.text(AppStrings.planSaveAction));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(reported, '');
  });

  testWidgets('returns null when cancelled', (tester) async {
    String? reported = 'unset';
    var called = false;

    await tester.pumpWidget(
      _harness(
        onResult: (name) {
          reported = name;
          called = true;
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(reported, isNull);
  });
}
