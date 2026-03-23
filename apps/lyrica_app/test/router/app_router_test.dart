import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/router/app_router.dart';
import 'package:lyrica_app/src/router/app_routes.dart';

void main() {
  test('list and reader route constants remain stable', () {
    expect(AppRoutes.home.path, '/');
    expect(AppRoutes.songReader.path, '/songs/:songId');
  });

  testWidgets('appRouter renders the song list and navigates to the reader route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: appRouter),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Egy út'), findsOneWidget);

    await tester.tap(find.text('Egy út'));
    await tester.pumpAndSettle();

    expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/songs/egy_ut');
  });
}
