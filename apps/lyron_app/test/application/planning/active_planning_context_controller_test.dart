import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/active_planning_context_controller.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';

void main() {
  group('ActivePlanningContextController', () {
    late AppAuthSession? session;
    late String? organizationId;
    late String? latestCachedOrganizationId;
    late bool shouldThrowOnOrganizationRead;

    setUp(() {
      session = const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyron.local',
      );
      organizationId = 'org-1';
      latestCachedOrganizationId = null;
      shouldThrowOnOrganizationRead = false;
    });

    test(
      'resolves the signed-in active organization into planning context',
      () async {
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            if (shouldThrowOnOrganizationRead) {
              throw const SocketException('offline');
            }
            return organizationId;
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
        );

        await controller.refresh();

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );
      },
    );

    test(
      'falls back to the latest cached organization when active organization lookup fails',
      () async {
        shouldThrowOnOrganizationRead = true;
        latestCachedOrganizationId = 'cached-org';
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            if (shouldThrowOnOrganizationRead) {
              throw const SocketException('offline');
            }
            return organizationId;
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
        );

        await controller.refresh(allowCachedFallback: true);

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'cached-org',
          ),
        );
      },
    );

    test(
      'keeps the established planning boundary when connectivity lookup fails after a verified org was already selected',
      () async {
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            if (shouldThrowOnOrganizationRead) {
              throw const SocketException('offline');
            }
            return organizationId;
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
        );

        await controller.refresh();
        shouldThrowOnOrganizationRead = true;
        latestCachedOrganizationId = 'cached-org';

        await controller.refresh(allowCachedFallback: true);

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );
      },
    );

    test(
      'does not reuse a cached organization for non-connectivity lookup failures',
      () async {
        latestCachedOrganizationId = 'cached-org';
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            throw StateError('membership lookup failed');
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
        );

        await controller.refresh(allowCachedFallback: true);

        expect(controller.state, isNull);
      },
    );

    test(
      // D5.4/D5.5 (docs/specs/2026-08-19-local-data-durability-contract.md,
      // ADR-035 Phase 4): a verified-empty resolution no longer clears
      // _state by itself -- the controller now defers entirely to the
      // injected handler's reported outcome (in production,
      // VerifiedEmptyMembershipCleanupCoordinator, gated on two
      // confirmations through LocalDataLifecycle). The handler here
      // simulates a genuine purge having already run (returns true) so this
      // test keeps pinning the controller's OWN responsibility once told
      // that happened.
      'keeps cached fallback blocked after verified empty membership clears the planning boundary',
      () async {
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            if (shouldThrowOnOrganizationRead) {
              throw const SocketException('offline');
            }
            return organizationId;
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
          onVerifiedEmptyMembership: ({required userId}) async => true,
        );

        await controller.refresh();
        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        organizationId = null;
        await controller.refresh(allowCachedFallback: true);

        expect(controller.state, isNull);

        shouldThrowOnOrganizationRead = true;
        latestCachedOrganizationId = 'cached-org';

        await controller.refresh(allowCachedFallback: true);

        expect(controller.state, isNull);
      },
    );

    test(
      // Required test 9 (D5.4/D5.5, ADR-035 Phase 4): reads stay served
      // when nothing was purged -- ADR-020's read access is unchanged until
      // data is genuinely gone.
      'a verified empty membership resolution that does not purge (handler '
      'reports false, or no handler at all) leaves the planning context '
      'fully intact',
      () async {
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async => organizationId,
          latestOrganizationReader: ({required userId}) async =>
              latestCachedOrganizationId,
          onVerifiedEmptyMembership: ({required userId}) async => false,
        );

        await controller.refresh();
        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        organizationId = null;
        await controller.refresh();

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );
      },
    );

    test('clears state when no signed-in session is available', () async {
      final controller = ActivePlanningContextController(
        authSessionReader: () => session,
        organizationReader: () async => organizationId,
        latestOrganizationReader: ({required userId}) async {
          return latestCachedOrganizationId;
        },
      );
      await controller.refresh();
      session = null;

      await controller.refresh();

      expect(controller.state, isNull);
    });

    test(
      'keeps the established context when a later organization lookup fails',
      () async {
        latestCachedOrganizationId = 'cached-org';
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            if (shouldThrowOnOrganizationRead) {
              throw StateError('offline');
            }
            return organizationId;
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
        );

        await controller.refresh();
        shouldThrowOnOrganizationRead = true;

        await controller.refresh();

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );
      },
    );

    test(
      'adopts active organization changes from the catalog context signal',
      () {
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async => organizationId,
          latestOrganizationReader: ({required userId}) async {
            return latestCachedOrganizationId;
          },
        );

        controller.syncToCatalogContext(
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-2'),
        );

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-2',
          ),
        );
      },
    );
  });
}
