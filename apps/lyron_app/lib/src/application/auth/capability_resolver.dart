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
    // Fan-out all capability checks concurrently to minimise latency.
    final resolutions = await Future.wait(
      Capability.values.map((capability) async {
        final response = await _client.rpc<dynamic>(
          'has_capability',
          params: {
            'target_organization_id': organizationId,
            'capability': capability.code,
          },
        );
        return response == true ? capability : null;
      }),
    );
    return resolutions.whereType<Capability>().toSet();
  }
}

class CapabilityResolver extends ChangeNotifier {
  CapabilityResolver({required CapabilityGateway gateway}) : _gateway = gateway;

  final CapabilityGateway _gateway;

  // Stores in-flight and completed futures keyed by organizationId.
  // Using Future<> deduplicates concurrent resolves triggered by multiple
  // IfCapability widgets mounting in the same frame.
  final Map<String, Future<Set<Capability>>> _cache = {};

  // Synchronous resolved sets — populated once a future completes.
  // Widgets use this for zero-flicker synchronous rendering on cache hits.
  final Map<String, Set<Capability>> _resolved = {};

  // Bumped on every invalidation so IfCapability can detect stale futures.
  int _version = 0;
  int get version => _version;

  Future<Set<Capability>> capabilitiesFor(String organizationId) =>
      _cache.putIfAbsent(organizationId, () {
        return _gateway
            .resolve(organizationId)
            .then((res) {
              _resolved[organizationId] = res;
              return res;
            })
            .catchError((Object error) {
              // Remove failed future so the next call retries instead of
              // permanently returning the same error.
              _cache.remove(organizationId);
              throw error;
            });
      });

  /// Synchronous check — returns null if capabilities have not been resolved
  /// yet for [organizationId].
  bool? hasCapabilitySync(String organizationId, Capability capability) =>
      _resolved[organizationId]?.contains(capability);

  Future<bool> hasCapability(
    String organizationId,
    Capability capability,
  ) async {
    final set = await capabilitiesFor(organizationId);
    return set.contains(capability);
  }

  void invalidate() {
    _cache.clear();
    _resolved.clear();
    _version++;
    notifyListeners();
  }
}
