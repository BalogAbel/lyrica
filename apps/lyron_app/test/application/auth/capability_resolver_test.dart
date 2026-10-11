import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/capability_resolver.dart';
import 'package:lyron_app/src/application/auth/capability_snapshot_store.dart';
import 'package:lyron_app/src/domain/core/capability.dart';

class _FakeCapabilityGateway implements CapabilityGateway {
  _FakeCapabilityGateway(this._capabilities);
  final Set<Capability> _capabilities;
  int calls = 0;

  @override
  Future<Set<Capability>> resolve(String organizationId) async {
    calls += 1;
    return _capabilities;
  }
}

class _FakeSnapshotStore implements CapabilitySnapshotStore {
  final Map<String, Set<String>> rows = {};
  int writes = 0;

  static String _key(String userId, String organizationId) =>
      '$userId|$organizationId';

  @override
  Future<Set<String>?> readCapabilityCodes({
    required String userId,
    required String organizationId,
  }) async => rows[_key(userId, organizationId)];

  @override
  Future<bool> writeCapabilityCodes({
    required String userId,
    required String organizationId,
    required Set<String> codes,
  }) async {
    writes += 1;
    rows[_key(userId, organizationId)] = codes;
    return true;
  }
}

class _ScriptedGateway implements CapabilityGateway {
  _ScriptedGateway(this.answer);

  Future<Set<Capability>> Function() answer;
  int calls = 0;

  @override
  Future<Set<Capability>> resolve(String organizationId) {
    calls += 1;
    return answer();
  }
}

void main() {
  test('caches resolved capabilities per organization id', () async {
    final gateway = _FakeCapabilityGateway({Capability.viewSongs});
    final resolver = CapabilityResolver(gateway: gateway);

    final first = await resolver.capabilitiesFor('org-1');
    final second = await resolver.capabilitiesFor('org-1');

    expect(first, equals({Capability.viewSongs}));
    expect(second, equals({Capability.viewSongs}));
    expect(gateway.calls, equals(1));
  });

  test('invalidate clears the cache', () async {
    final gateway = _FakeCapabilityGateway({Capability.viewSongs});
    final resolver = CapabilityResolver(gateway: gateway);

    await resolver.capabilitiesFor('org-1');
    resolver.invalidate();
    await resolver.capabilitiesFor('org-1');

    expect(gateway.calls, equals(2));
  });

  test('hasCapability returns false when capability is missing', () async {
    final gateway = _FakeCapabilityGateway({Capability.viewSongs});
    final resolver = CapabilityResolver(gateway: gateway);

    expect(
      await resolver.hasCapability('org-1', Capability.editSongs),
      isFalse,
    );
    expect(await resolver.hasCapability('org-1', Capability.viewSongs), isTrue);
  });

  group('stored capabilities (SG6)', () {
    test('answer before the network does', () async {
      final store = _FakeSnapshotStore()
        ..rows['user-1|org-1'] = {'canEditSongs'};
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(() => Completer<Set<Capability>>().future),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );

      final capabilities = await resolver.capabilitiesFor('org-1');

      expect(capabilities, {Capability.editSongs});
      expect(resolver.hasCapabilitySync('org-1', Capability.editSongs), isTrue);
    });

    test('a failed refresh keeps the stored set', () async {
      final store = _FakeSnapshotStore()
        ..rows['user-1|org-1'] = {'canEditSongs'};
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(() async => throw StateError('offline')),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );

      await resolver.capabilitiesFor('org-1');
      await pumpEventQueue();

      expect(store.rows['user-1|org-1'], {'canEditSongs'});
      expect(resolver.hasCapabilitySync('org-1', Capability.editSongs), isTrue);
    });

    test('a successful refresh replaces, persists and notifies', () async {
      final store = _FakeSnapshotStore()
        ..rows['user-1|org-1'] = {'canEditSongs'};
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(() async => {Capability.viewSongs}),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );
      var notifications = 0;
      resolver.addListener(() => notifications++);

      await resolver.capabilitiesFor('org-1');
      await pumpEventQueue();

      expect(
        resolver.hasCapabilitySync('org-1', Capability.editSongs),
        isFalse,
      );
      expect(resolver.hasCapabilitySync('org-1', Capability.viewSongs), isTrue);
      expect(store.rows['user-1|org-1'], {'canViewSongs'});
      expect(notifications, 1);
    });

    test('with nothing stored the network answer is persisted', () async {
      final store = _FakeSnapshotStore();
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(() async => {Capability.viewSongs}),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );

      expect(await resolver.capabilitiesFor('org-1'), {Capability.viewSongs});
      expect(store.rows['user-1|org-1'], {'canViewSongs'});
    });

    test('another user\'s stored set is never applied', () async {
      final store = _FakeSnapshotStore()
        ..rows['user-1|org-1'] = {'canEditSongs'};
      final gateway = _ScriptedGateway(() async => {Capability.viewSongs});
      final resolver = CapabilityResolver(
        gateway: gateway,
        snapshotStore: store,
        readUserId: () => 'user-2',
      );

      expect(await resolver.capabilitiesFor('org-1'), {Capability.viewSongs});
      expect(gateway.calls, 1);
    });

    test('invalidate re-reads the store instead of deleting it', () async {
      final store = _FakeSnapshotStore()
        ..rows['user-1|org-1'] = {'canEditSongs'};
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(() => Completer<Set<Capability>>().future),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );
      await resolver.capabilitiesFor('org-1');

      resolver.invalidate();

      expect(await resolver.capabilitiesFor('org-1'), {Capability.editSongs});
      expect(store.rows['user-1|org-1'], {'canEditSongs'});
    });

    test('an answer arriving after invalidate is never persisted', () async {
      final store = _FakeSnapshotStore();
      final held = Completer<Set<Capability>>();
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(() => held.future),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );

      final first = resolver.capabilitiesFor('org-1');
      await pumpEventQueue();
      resolver.invalidate();
      held.complete({Capability.viewSongs});
      await first;
      await pumpEventQueue();

      expect(store.rows.containsKey('user-1|org-1'), isFalse);
      expect(store.writes, 0);
    });

    test('a refresh answering after invalidate is never persisted', () async {
      final store = _FakeSnapshotStore()
        ..rows['user-1|org-1'] = {'canEditSongs'};
      final held = Completer<Set<Capability>>();
      final resolver = CapabilityResolver(
        gateway: _ScriptedGateway(() => held.future),
        snapshotStore: store,
        readUserId: () => 'user-1',
      );

      await resolver.capabilitiesFor('org-1');
      resolver.invalidate();
      held.complete({Capability.viewSongs});
      await pumpEventQueue();

      expect(store.rows['user-1|org-1'], {'canEditSongs'});
      expect(store.writes, 0);
    });
  });
}
