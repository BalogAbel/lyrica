import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/app/lyrica_app.dart';

void main() {
  testWidgets('renders the song list through the shared app router', (
    tester,
  ) async {
    await tester.pumpWidget(ProviderScope(child: LyricaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Lyrica'), findsOneWidget);
    expect(find.text('A forrásnál'), findsOneWidget);
    expect(find.text('A mi Istenünk (Leborulok előtted)'), findsOneWidget);
    expect(find.text('Egy út'), findsOneWidget);
  });
}
