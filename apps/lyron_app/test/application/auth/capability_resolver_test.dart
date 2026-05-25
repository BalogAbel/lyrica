import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/capability_resolver.dart';
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

    expect(await resolver.hasCapability('org-1', Capability.editSongs), isFalse);
    expect(await resolver.hasCapability('org-1', Capability.viewSongs), isTrue);
  });
}
