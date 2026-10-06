import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/active_membership_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/membership_gate.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Future<void> _pumpGate(
  WidgetTester tester,
  ActiveMembershipController controller, {
  ActiveOrganizationResolutionReader? reader,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeMembershipControllerProvider.overrideWith((_) => controller),
        if (reader != null)
          membershipResolutionProvider.overrideWithValue(reader),
      ],
      child: const MaterialApp(home: MembershipGate(child: Text('home-child'))),
    ),
  );
}

void main() {
  testWidgets('a known organization shows the home route with no '
      'resolution (SG1)', (tester) async {
    await _pumpGate(
      tester,
      ActiveMembershipController(
        currentUserIdReader: () => 'user-1',
        knownOrganizationIdReader: () => 'org-1',
      ),
    );

    expect(find.text('home-child'), findsOneWidget);
  });

  testWidgets('a running first resolution shows the loading copy, never the '
      'failure (G-C)', (tester) async {
    await _pumpGate(
      tester,
      ActiveMembershipController(currentUserIdReader: () => 'user-1')
        ..beginResolution(userId: 'user-1'),
    );

    expect(find.text(AppStrings.membershipResolvingMessage), findsOneWidget);
    expect(
      find.text(AppStrings.membershipConnectivityFailureMessage),
      findsNothing,
    );
  });

  testWidgets('after the first-run timeout the connectivity message and '
      'Retry appear (SG4)', (tester) async {
    await _pumpGate(
      tester,
      ActiveMembershipController(currentUserIdReader: () => 'user-1')
        ..beginResolution(userId: 'user-1'),
    );

    await tester.pump(const Duration(seconds: 15));

    expect(
      find.text(AppStrings.membershipConnectivityFailureMessage),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('membership-gate-retry')), findsOneWidget);
  });

  testWidgets('Retry resolves for the current user and opens the gate', (
    tester,
  ) async {
    final answer = Completer<ActiveOrganizationResolution>();
    final controller =
        ActiveMembershipController(currentUserIdReader: () => 'user-1')..update(
          const ActiveOrganizationResolution.unknownConnectivityFailure(),
          userId: 'user-1',
        );
    await _pumpGate(tester, controller, reader: () => answer.future);

    await tester.tap(find.byKey(const ValueKey('membership-gate-retry')));
    await tester.pump();
    answer.complete(const ActiveOrganizationResolution.selected('org-1'));
    await tester.pump();

    expect(find.text('home-child'), findsOneWidget);
    expect(controller.last, isA<ActiveOrganizationSelected>());
  });

  testWidgets('a non-connectivity failure without a known organization shows '
      'its own message', (tester) async {
    await _pumpGate(
      tester,
      ActiveMembershipController(currentUserIdReader: () => 'user-1')..update(
        const ActiveOrganizationResolution.unknownNonConnectivityFailure(),
        userId: 'user-1',
      ),
    );

    expect(
      find.text(AppStrings.membershipNonConnectivityFailureMessage),
      findsOneWidget,
    );
  });

  group('sign-in action while the session is expired (F2)', () {
    Future<GoRouter> pumpRouted(
      WidgetTester tester, {
      required bool sessionExpired,
      required ActiveOrganizationResolution failure,
    }) async {
      final controller = ActiveMembershipController(
        currentUserIdReader: () => 'user-1',
        sessionExpiredReader: () => sessionExpired,
      )..update(failure, userId: 'user-1');
      final router = GoRouter(
        initialLocation: '/?tab=1',
        routes: [
          GoRoute(
            path: AppRoutes.home.path,
            builder: (context, state) =>
                const MembershipGate(child: Text('home-child')),
          ),
          GoRoute(
            path: AppRoutes.signIn.path,
            builder: (context, state) => const Text('sign-in-screen'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMembershipControllerProvider.overrideWith((_) => controller),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      return router;
    }

    const signInKey = ValueKey('membership-gate-sign-in');
    const connectivity =
        ActiveOrganizationResolution.unknownConnectivityFailure();
    const nonConnectivity =
        ActiveOrganizationResolution.unknownNonConnectivityFailure();

    for (final failure in [connectivity, nonConnectivity]) {
      testWidgets('${failure.runtimeType} offers sign-in with the re-auth '
          'banner route and its from parameter', (tester) async {
        final router = await pumpRouted(
          tester,
          sessionExpired: true,
          failure: failure,
        );

        await tester.tap(find.byKey(signInKey));
        await tester.pumpAndSettle();

        expect(find.text('sign-in-screen'), findsOneWidget);
        expect(
          router.state.uri.toString(),
          Uri(
            path: AppRoutes.signIn.path,
            queryParameters: {'from': '/?tab=1'},
          ).toString(),
        );
      });

      testWidgets('${failure.runtimeType} offers no sign-in action while '
          'signed in', (tester) async {
        await pumpRouted(tester, sessionExpired: false, failure: failure);

        expect(find.byKey(signInKey), findsNothing);
      });
    }
  });
}
