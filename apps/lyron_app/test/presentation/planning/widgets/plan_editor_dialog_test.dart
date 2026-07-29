import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/planning/widgets/plan_editor_dialog.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Widget _harness({
  required String planId,
  required String initialName,
  String? initialDescription,
  DateTime? initialScheduledFor,
  required ValueChanged<PlanEditDraft?> onResult,
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
              final result = await showDialog<PlanEditDraft>(
                context: context,
                builder: (_) => PlanEditorDialog(
                  planId: planId,
                  initialName: initialName,
                  initialDescription: initialDescription,
                  initialScheduledFor: initialScheduledFor,
                ),
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
  testWidgets('pre-fills the name field from initialName', (tester) async {
    await tester.pumpWidget(
      _harness(
        planId: 'plan-1',
        initialName: 'Team Rehearsal',
        onResult: (_) {},
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(AlertDialog, AppStrings.planEditorTitleEdit),
      findsOneWidget,
    );
    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey('plan-editor-name')),
    );
    expect(nameField.controller?.text, 'Team Rehearsal');
  });

  testWidgets('reports the edited draft when saved', (tester) async {
    PlanEditDraft? reported;

    await tester.pumpWidget(
      _harness(
        planId: 'plan-1',
        initialName: 'Team Rehearsal',
        onResult: (draft) => reported = draft,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('plan-editor-name')),
      'Updated Team Rehearsal',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-editor-description')),
      'New description',
    );
    await tester.tap(find.text(AppStrings.planSaveAction));
    await tester.pumpAndSettle();

    expect(reported?.planId, 'plan-1');
    expect(reported?.name, 'Updated Team Rehearsal');
    expect(reported?.description, 'New description');
  });

  testWidgets('returns null when cancelled', (tester) async {
    PlanEditDraft? reported = const PlanEditDraft(planId: 'unset', name: '');
    var called = false;

    await tester.pumpWidget(
      _harness(
        planId: 'plan-1',
        initialName: 'Team Rehearsal',
        onResult: (draft) {
          reported = draft;
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

  testWidgets(
    'picking a date and time produces a UTC value in the resulting draft',
    (tester) async {
      PlanEditDraft? reported;

      await tester.pumpWidget(
        _harness(
          planId: 'plan-1',
          initialName: 'Team Rehearsal',
          onResult: (draft) => reported = draft,
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('scheduled-for-pick')));
      await tester.pumpAndSettle();
      final localizations = MaterialLocalizations.of(
        tester.element(find.byKey(const ValueKey('scheduled-for-pick'))),
      );
      // Date picker.
      await tester.tap(
        find.widgetWithText(TextButton, localizations.okButtonLabel).first,
      );
      await tester.pumpAndSettle();
      // Time picker.
      await tester.tap(
        find.widgetWithText(TextButton, localizations.okButtonLabel).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.planSaveAction));
      await tester.pumpAndSettle();

      expect(reported?.scheduledFor, isNotNull);
      expect(reported!.scheduledFor!.isUtc, isTrue);
    },
  );

  testWidgets(
    'round-trips a stored scheduled-for instant through the pickers unchanged',
    (tester) async {
      PlanEditDraft? reported;
      final storedInstant = DateTime.utc(2026, 4, 10, 18);

      await tester.pumpWidget(
        _harness(
          planId: 'plan-1',
          initialName: 'Team Rehearsal',
          initialScheduledFor: storedInstant,
          onResult: (draft) => reported = draft,
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('scheduled-for-pick')));
      await tester.pumpAndSettle();
      final localizations = MaterialLocalizations.of(
        tester.element(find.byKey(const ValueKey('scheduled-for-pick'))),
      );
      // Accept the seeded date, then the seeded time, unchanged.
      await tester.tap(
        find.widgetWithText(TextButton, localizations.okButtonLabel).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, localizations.okButtonLabel).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.planSaveAction));
      await tester.pumpAndSettle();

      expect(reported?.scheduledFor, storedInstant);
    },
  );
}
