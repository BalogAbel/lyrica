import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/active_organization_resolver.dart';

ActiveOrganizationResolver buildResolver({
  required ActiveOrganizationResolution resolution,
  String? userId = 'user-1',
  String? cachedOrganizationId,
  bool cacheThrows = false,
}) {
  return ActiveOrganizationResolver(
    resolveRawReader: () async => resolution,
    readUserId: () => userId,
    readCachedOrganizationId: ({required userId}) async {
      if (cacheThrows) throw StateError('cache read failed');
      return cachedOrganizationId;
    },
  );
}

void main() {
  group('ActiveOrganizationResolver', () {
    test('resolveRaw passes the reader resolution through unchanged', () async {
      final resolver = buildResolver(
        resolution: const ActiveOrganizationResolution.selected('org-1'),
      );
      expect(
        await resolver.resolveRaw(),
        const ActiveOrganizationResolution.selected('org-1'),
      );
    });

    test(
      'resolveWithCachedFallback uses cache only on connectivity failure',
      () async {
        final resolver = buildResolver(
          resolution:
              const ActiveOrganizationResolution.unknownConnectivityFailure(),
          cachedOrganizationId: 'org-cached',
        );
        expect(
          await resolver.resolveWithCachedFallback(),
          const ActiveOrganizationResolution.selected('org-cached'),
        );
      },
    );

    test(
      'resolveWithCachedFallback does not fall back on verifiedEmpty',
      () async {
        final resolver = buildResolver(
          resolution: const ActiveOrganizationResolution.verifiedEmpty(),
          cachedOrganizationId: 'org-cached',
        );
        expect(
          await resolver.resolveWithCachedFallback(),
          const ActiveOrganizationResolution.verifiedEmpty(),
        );
      },
    );

    test('resolveOrganizationId returns id on selected', () async {
      final resolver = buildResolver(
        resolution: const ActiveOrganizationResolution.selected('org-1'),
      );
      expect(await resolver.resolveOrganizationId(), 'org-1');
    });

    test('resolveOrganizationId returns null on verifiedEmpty', () async {
      final resolver = buildResolver(
        resolution: const ActiveOrganizationResolution.verifiedEmpty(),
      );
      expect(await resolver.resolveOrganizationId(), isNull);
    });

    test(
      'resolveOrganizationId throws SocketException on connectivity failure',
      () async {
        final resolver = buildResolver(
          resolution:
              const ActiveOrganizationResolution.unknownConnectivityFailure(),
        );
        await expectLater(
          resolver.resolveOrganizationId(),
          throwsA(isA<SocketException>()),
        );
      },
    );

    test(
      'resolveOrganizationId throws StateError on non-connectivity failure',
      () async {
        final resolver = buildResolver(
          resolution:
              const ActiveOrganizationResolution.unknownNonConnectivityFailure(),
        );
        await expectLater(
          resolver.resolveOrganizationId(),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
