import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/app/lyrica_app.dart';

void main() {
  testWidgets('renders app shell title and architecture sections', (
    tester,
  ) async {
    await tester.pumpWidget(ProviderScope(child: LyricaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Lyrica'), findsOneWidget);
    expect(find.text('Offline-first worship planning'), findsOneWidget);
    expect(find.text('Architecture foundation'), findsOneWidget);
    expect(
      find.text('Capabilities are enforced in Supabase/Postgres.'),
      findsOneWidget,
    );
  });
}
