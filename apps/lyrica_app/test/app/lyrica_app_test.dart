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
    expect(find.text('Song library and reader flow'), findsOneWidget);
    expect(find.text('Open a song to read and transpose it'), findsOneWidget);
  });
}
