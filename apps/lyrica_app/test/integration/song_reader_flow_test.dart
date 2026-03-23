import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/app/lyrica_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'boots into the song list, opens the reader, and shows parsed asset content',
    (tester) async {
      await tester.pumpWidget(ProviderScope(child: LyricaApp()));
      await tester.pumpAndSettle();

      expect(find.text('Lyrica'), findsOneWidget);
      expect(find.text('Egy út'), findsOneWidget);

      await tester.tap(find.text('Egy út'));
      await tester.pumpAndSettle();

      expect(find.text('Song reader'), findsOneWidget);
      expect(find.text('Egy út'), findsWidgets);
      expect(find.text('One Way'), findsOneWidget);
      expect(find.text('Key: B'), findsOneWidget);
      expect(find.text('Verse 1'), findsOneWidget);
      expect(find.textContaining('Leteszem'), findsWidgets);
    },
  );
}
