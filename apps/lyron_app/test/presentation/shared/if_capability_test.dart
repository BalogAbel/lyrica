import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/capability_resolver.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';
import 'package:lyron_app/src/presentation/shared/if_capability.dart';

class _HangingGateway implements CapabilityGateway {
  @override
  Future<Set<Capability>> resolve(String organizationId) =>
      Completer<Set<Capability>>().future;
}

class _ThrowingGateway implements CapabilityGateway {
  @override
  Future<Set<Capability>> resolve(String organizationId) =>
      Future<Set<Capability>>.error(StateError('offline'));
}

void main() {
  testWidgets('a stored capability shows the affordance with no network '
      'answer (SG6)', (tester) async {
    final database = LastKnownIdentityDatabase.inMemory();
    final store = DriftLastKnownIdentityStore(database);
    await tester.runAsync(() async {
      await store.write(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user-1@example.com',
          organizationId: 'org-1',
        ),
      );
      await store.writeCapabilityCodes(
        userId: 'user-1',
        organizationId: 'org-1',
        codes: {Capability.editSongs.code},
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          capabilityResolverProvider.overrideWith(
            (_) => CapabilityResolver(
              gateway: _HangingGateway(),
              snapshotStore: store,
              readUserId: () => 'user-1',
            ),
          ),
        ],
        child: const MaterialApp(
          home: IfCapability(
            capability: Capability.editSongs,
            organizationId: 'org-1',
            child: Text('edit'),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.text('edit'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
  });

  testWidgets('no stored set and a failing gateway fails open (SG6 '
      '"No stored set")', (tester) async {
    final database = LastKnownIdentityDatabase.inMemory();
    final store = DriftLastKnownIdentityStore(database);
    await tester.runAsync(() async {
      await store.write(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user-1@example.com',
          organizationId: 'org-1',
        ),
      );
    });

    // The resolver logs the expected failure through debugPrint.
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          capabilityResolverProvider.overrideWith(
            (_) => CapabilityResolver(
              gateway: _ThrowingGateway(),
              snapshotStore: store,
              readUserId: () => 'user-1',
            ),
          ),
        ],
        child: const MaterialApp(
          home: IfCapability(
            capability: Capability.editSongs,
            organizationId: 'org-1',
            child: Text('edit'),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.text('edit'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    debugPrint = originalDebugPrint;
    await tester.runAsync(database.close);
  });
}
