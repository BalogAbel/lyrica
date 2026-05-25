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

  // Stores in-flight and completed futures keyed by organizationId.
  // Using Future<> deduplicates concurrent resolves triggered by multiple
  // IfCapability widgets mounting in the same frame.
  final Map<String, Future<Set<Capability>>> _cache = {};

  // Bumped on every invalidation so IfCapability can detect stale futures.
  int _version = 0;
  int get version => _version;

  Future<Set<Capability>> capabilitiesFor(String organizationId) => _cache
      .putIfAbsent(organizationId, () => _gateway.resolve(organizationId));

  Future<bool> hasCapability(
    String organizationId,
    Capability capability,
  ) async {
    final set = await capabilitiesFor(organizationId);
    return set.contains(capability);
  }

  void invalidate() {
    _cache.clear();
    _version++;
    notifyListeners();
  }
}
