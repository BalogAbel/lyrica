import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/app/lyrica_app.dart';

void main() {
  testWidgets('renders app shell title and architectural boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(ProviderScope(child: LyricaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Lyrica'), findsOneWidget);
    expect(find.text('Offline-first worship planning'), findsOneWidget);
    expect(find.text('Repository foundation status'), findsOneWidget);
    expect(
      find.text('Authorization: capability-based RLS in Supabase/Postgres'),
      findsOneWidget,
    );
    expect(find.text('Local store: Drift'), findsOneWidget);
    expect(find.text('Sync queue: enabled'), findsOneWidget);
    expect(find.text('Conflict resolution: manual'), findsOneWidget);
  });
}
