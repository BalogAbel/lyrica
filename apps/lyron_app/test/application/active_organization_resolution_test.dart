import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('resolveActiveOrganizationResolution', () {
    test(
      'returns selected organization id for a verified single-member response',
      () async {
        final resolution = await resolveActiveOrganizationResolution(
          () async => const ['org-1'],
        );

        expect(
          resolution,
          const ActiveOrganizationResolution.selected('org-1'),
        );
      },
    );

    test(
      'keeps the stable sorted first id for verified multi-member responses',
      () async {
        final resolution = await resolveActiveOrganizationResolution(
          () async => const ['org-b', 'org-a', 'org-c'],
        );

        expect(
          resolution,
          const ActiveOrganizationResolution.selected('org-a'),
        );
      },
    );

    test(
      'returns verified empty when the verified response has no organization ids',
      () async {
        final resolution = await resolveActiveOrganizationResolution(
          () async => const [],
        );

        expect(resolution, const ActiveOrganizationResolution.verifiedEmpty());
      },
    );

    test(
      'classifies connectivity-classified lookup failures as unknown connectivity failure',
      () async {
        final resolution = await resolveActiveOrganizationResolution(
          () async => throw const PostgrestException(
            message: 'Service unavailable',
            code: '503',
            details: 'upstream connect error',
          ),
        );

        expect(
          resolution,
          const ActiveOrganizationResolution.unknownConnectivityFailure(),
        );
      },
    );

    test(
      'classifies malformed responses and non-connectivity failures as unknown non-connectivity failure',
      () async {
        final malformedResolution = await resolveActiveOrganizationResolution(
          () async => 'unexpected',
        );

        expect(
          malformedResolution,
          const ActiveOrganizationResolution.unknownNonConnectivityFailure(),
        );

        final thrownResolution = await resolveActiveOrganizationResolution(
          () async => throw StateError('permission denied'),
        );

        expect(
          thrownResolution,
          const ActiveOrganizationResolution.unknownNonConnectivityFailure(),
        );
      },
    );
  });
}
