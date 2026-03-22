import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/app/lyrica_app.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

void main() {
  testWidgets('renders the song-library shell copy', (
    tester,
  ) async {
    await tester.pumpWidget(ProviderScope(child: LyricaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Lyrica'), findsOneWidget);
    expect(find.text(AppStrings.songLibraryHeading), findsOneWidget);
    expect(find.text(AppStrings.songLibraryFlowHeading), findsOneWidget);
    expect(find.text(AppStrings.songLibraryFlowSummary), findsOneWidget);
  });
}
