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
              throw StateError('offline');
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
