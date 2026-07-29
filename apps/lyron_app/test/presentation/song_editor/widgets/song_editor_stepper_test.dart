import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_editor/widgets/song_editor_stepper.dart';

void main() {
  testWidgets('renders the label and value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongEditorStepper(
            label: 'Transpose',
            value: '+2',
            onDecrease: () {},
            onIncrease: () {},
            enabled: true,
          ),
        ),
      ),
    );

    expect(find.text('Transpose'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('fires onDecrease and onIncrease when enabled', (tester) async {
    var decreases = 0;
    var increases = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongEditorStepper(
            label: 'Transpose',
            value: '+2',
            onDecrease: () => decreases += 1,
            onIncrease: () => increases += 1,
            enabled: true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('transpose-decrease')));
    await tester.tap(find.byKey(const Key('transpose-increase')));
    await tester.pump();

    expect(decreases, 1);
    expect(increases, 1);
  });

  testWidgets('disables both buttons when enabled is false', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongEditorStepper(
            label: 'Capo',
            value: '0',
            onDecrease: () {},
            onIncrease: () {},
            enabled: false,
          ),
        ),
      ),
    );

    final decreaseButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('capo-decrease')),
    );
    final increaseButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('capo-increase')),
    );

    expect(decreaseButton.onPressed, isNull);
    expect(increaseButton.onPressed, isNull);
  });
}
