import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/planning/widgets/scheduled_for_field.dart';

Widget _harness({
  required DateTime? value,
  required ValueChanged<DateTime?> onChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ScheduledForField(value: value, onChanged: onChanged),
    ),
  );
}

MaterialLocalizations _localizations(WidgetTester tester) {
  return MaterialLocalizations.of(tester.element(find.byType(Scaffold)));
}

Future<void> _acceptDatePicker(WidgetTester tester) async {
  final localizations = _localizations(tester);
  await tester.tap(
    find.widgetWithText(TextButton, localizations.okButtonLabel).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _cancelDatePicker(WidgetTester tester) async {
  final localizations = _localizations(tester);
  await tester.tap(
    find.widgetWithText(TextButton, localizations.cancelButtonLabel).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('picking a date and time yields a UTC instant', (tester) async {
    DateTime? reported;
    var called = false;

    await tester.pumpWidget(
      _harness(
        value: null,
        onChanged: (value) {
          reported = value;
          called = true;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('scheduled-for-pick')));
    await tester.pumpAndSettle();

    // Date picker.
    await _acceptDatePicker(tester);
    // Time picker.
    await _acceptDatePicker(tester);

    expect(called, isTrue);
    expect(reported, isNotNull);
    expect(reported!.isUtc, isTrue);
  });

  testWidgets('opens the picker for a plan scheduled far in the past', (
    tester,
  ) async {
    // A plan whose stored date predates the default five-year window. The
    // picker asserts that initialDate lies inside firstDate..lastDate, so a
    // fixed window would throw here instead of opening.
    final longAgo = DateTime(DateTime.now().year - 12, 4, 5, 8, 30).toUtc();

    await tester.pumpWidget(_harness(value: longAgo, onChanged: (_) {}));

    await tester.tap(find.byKey(const ValueKey('scheduled-for-pick')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('opens the picker for a plan scheduled far in the future', (
    tester,
  ) async {
    final farAhead = DateTime(DateTime.now().year + 12, 4, 5, 8, 30).toUtc();

    await tester.pumpWidget(_harness(value: farAhead, onChanged: (_) {}));

    await tester.tap(find.byKey(const ValueKey('scheduled-for-pick')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('renders the stored instant as local time', (tester) async {
    final stored = DateTime.utc(2026, 4, 5, 8, 30);

    await tester.pumpWidget(_harness(value: stored, onChanged: (_) {}));

    final context = tester.element(find.byType(Scaffold));
    final localizations = MaterialLocalizations.of(context);
    final local = stored.toLocal();
    final expectedDate = localizations.formatMediumDate(local);
    final expectedTime = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
    );

    expect(find.textContaining(expectedDate), findsOneWidget);
    expect(find.textContaining(expectedTime), findsOneWidget);
  });

  testWidgets('clearing reports null', (tester) async {
    DateTime? reported = DateTime.utc(2026, 4, 5, 8, 30);
    var called = false;

    await tester.pumpWidget(
      _harness(
        value: DateTime.utc(2026, 4, 5, 8, 30),
        onChanged: (value) {
          reported = value;
          called = true;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('scheduled-for-clear')));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(reported, isNull);
  });

  testWidgets('cancelling the date picker leaves the value untouched', (
    tester,
  ) async {
    var called = false;

    await tester.pumpWidget(
      _harness(value: null, onChanged: (_) => called = true),
    );

    await tester.tap(find.byKey(const ValueKey('scheduled-for-pick')));
    await tester.pumpAndSettle();

    await _cancelDatePicker(tester);

    expect(called, isFalse);
  });

  testWidgets('cancelling the time picker leaves the value untouched', (
    tester,
  ) async {
    var called = false;

    await tester.pumpWidget(
      _harness(value: null, onChanged: (_) => called = true),
    );

    await tester.tap(find.byKey(const ValueKey('scheduled-for-pick')));
    await tester.pumpAndSettle();

    await _acceptDatePicker(tester);
    await _cancelDatePicker(tester);

    expect(called, isFalse);
  });

  testWidgets('seeds the pickers from the stored instant', (tester) async {
    final stored = DateTime.utc(2026, 4, 5, 8, 30);

    await tester.pumpWidget(_harness(value: stored, onChanged: (_) {}));

    await tester.tap(find.byKey(const ValueKey('scheduled-for-pick')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold));
    final localizations = MaterialLocalizations.of(context);
    final expectedHeader = localizations.formatMediumDate(stored.toLocal());

    expect(find.text(expectedHeader), findsOneWidget);
  });
}
