import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/app/lyrica_app.dart';

void main() {
  testWidgets('renders the song-library shell copy', (
    tester,
  ) async {
    await tester.pumpWidget(ProviderScope(child: LyricaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Lyrica'), findsOneWidget);
    expect(find.text('Tablet-first song library'), findsOneWidget);
    expect(find.text('Mock song catalog in progress'), findsOneWidget);
    expect(find.text('Song library and reader screens are next'), findsOneWidget);
    expect(find.text('Repository foundation status'), findsNothing);
    expect(find.text('Authorization: capability-based RLS in Supabase/Postgres'), findsNothing);
    expect(find.textContaining('Local store:'), findsNothing);
    expect(find.textContaining('Sync queue:'), findsNothing);
    expect(find.textContaining('Read strategy:'), findsNothing);
    expect(find.textContaining('Conflict resolution:'), findsNothing);
    expect(find.textContaining('Offline window:'), findsNothing);
  });
}
