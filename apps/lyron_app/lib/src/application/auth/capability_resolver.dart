import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/core/capability.dart';

abstract class CapabilityGateway {
  Future<Set<Capability>> resolve(String organizationId);
}

class SupabaseCapabilityGateway implements CapabilityGateway {
  SupabaseCapabilityGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<Set<Capability>> resolve(String organizationId) async {
    final results = <Capability>{};
    for (final capability in Capability.values) {
      final response = await _client.rpc<dynamic>(
        'has_capability',
        params: {
          'target_organization_id': organizationId,
          'capability': capability.code,
        },
      );
      if (response == true) {
        results.add(capability);
      }
    }
    return results;
  }
}

class CapabilityResolver extends ChangeNotifier {
  CapabilityResolver({required CapabilityGateway gateway}) : _gateway = gateway;

  final CapabilityGateway _gateway;
  final Map<String, Set<Capability>> _cache = {};

  Future<Set<Capability>> capabilitiesFor(String organizationId) async {
    final cached = _cache[organizationId];
    if (cached != null) {
      return cached;
    }
    final resolved = await _gateway.resolve(organizationId);
    _cache[organizationId] = resolved;
    return resolved;
  }

  Future<bool> hasCapability(String organizationId, Capability capability) async {
    final set = await capabilitiesFor(organizationId);
    return set.contains(capability);
  }

  void invalidate() {
    _cache.clear();
    notifyListeners();
  }
}
