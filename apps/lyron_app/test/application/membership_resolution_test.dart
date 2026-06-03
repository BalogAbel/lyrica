import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/providers.dart';

void main() {
  group('resolveMembershipWithCachedFallback', () {
    test('passes through a Selected resolution unchanged', () async {
      const resolution = ActiveOrganizationResolution.selected('org-1');

      final result = await resolveMembershipWithCachedFallback(
        resolution: resolution,
        userId: 'user-1',
        readCachedOrganizationId: ({required userId}) async => 'org-cached',
      );

      expect(result, const ActiveOrganizationResolution.selected('org-1'));
    });

    test('passes through a VerifiedEmpty resolution unchanged', () async {
      const resolution = ActiveOrganizationResolution.verifiedEmpty();

      final result = await resolveMembershipWithCachedFallback(
        resolution: resolution,
        userId: 'user-1',
        readCachedOrganizationId: ({required userId}) async => 'org-cached',
      );

      expect(result, const ActiveOrganizationResolution.verifiedEmpty());
    });

    test(
      'passes through a NonConnectivityFailure resolution unchanged',
      () async {
        const resolution =
            ActiveOrganizationResolution.unknownNonConnectivityFailure();

        final result = await resolveMembershipWithCachedFallback(
          resolution: resolution,
          userId: 'user-1',
          readCachedOrganizationId: ({required userId}) async => 'org-cached',
        );

        expect(
          result,
          const ActiveOrganizationResolution.unknownNonConnectivityFailure(),
        );
      },
    );

    test(
      'returns Selected(cachedOrgId) when connectivity failure and cached org present',
      () async {
        const resolution =
            ActiveOrganizationResolution.unknownConnectivityFailure();

        final result = await resolveMembershipWithCachedFallback(
          resolution: resolution,
          userId: 'user-1',
          readCachedOrganizationId: ({required userId}) async => 'org-cached',
        );

        expect(
          result,
          const ActiveOrganizationResolution.selected('org-cached'),
        );
      },
    );

    test(
      'passes through connectivity failure unchanged when no cached org',
      () async {
        const resolution =
            ActiveOrganizationResolution.unknownConnectivityFailure();

        final result = await resolveMembershipWithCachedFallback(
          resolution: resolution,
          userId: 'user-1',
          readCachedOrganizationId: ({required userId}) async => null,
        );

        expect(
          result,
          const ActiveOrganizationResolution.unknownConnectivityFailure(),
        );
      },
    );

    test(
      'passes through connectivity failure unchanged when userId is null',
      () async {
        const resolution =
            ActiveOrganizationResolution.unknownConnectivityFailure();

        final result = await resolveMembershipWithCachedFallback(
          resolution: resolution,
          userId: null,
          readCachedOrganizationId: ({required userId}) async => 'org-cached',
        );

        expect(
          result,
          const ActiveOrganizationResolution.unknownConnectivityFailure(),
        );
      },
    );
  });
}
