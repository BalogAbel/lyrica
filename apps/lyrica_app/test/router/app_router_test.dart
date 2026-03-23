import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/router/app_router.dart';
import 'package:lyrica_app/src/router/app_routes.dart';

void main() {
  test('list and reader route constants remain stable', () {
    expect(AppRoutes.home.path, '/');
    expect(AppRoutes.songReader.path, '/songs/:songId');
  });

  testWidgets('appRouter registers the song reader route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: appRouter),
    );
    await tester.pumpAndSettle();

    appRouter.go('/songs/egy_ut');
    await tester.pumpAndSettle();

    expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/songs/egy_ut');
  });
}
