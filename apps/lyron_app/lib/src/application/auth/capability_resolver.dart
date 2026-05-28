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
    // Single RPC call returns all granted capability codes in one round-trip,
    // avoiding N concurrent HTTP requests (one per capability).
    final response = await _client.rpc<dynamic>(
      'get_my_capabilities',
      params: {'target_organization_id': organizationId},
    );
    final codes = (response as List<dynamic>).cast<String>().toSet();
    return Capability.values.where((c) => codes.contains(c.code)).toSet();
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

  Future<Set<Capability>> capabilitiesFor(String organizationId) {
    // Capture version before putIfAbsent so the factory closure can guard
    // against writing stale data when invalidate() fires mid-flight.
    final capturedVersion = _version;
    return _cache.putIfAbsent(organizationId, () {
      return _gateway
          .resolve(organizationId)
          .then((res) {
            // Only populate the synchronous cache if the resolver has not been
            // invalidated since this future was created.
            if (_version == capturedVersion) {
              _resolved[organizationId] = res;
            }
            return res;
          })
          .catchError((Object error, StackTrace stackTrace) {
            // Only evict the failed future if it is still the current one —
            // a racing invalidate() may have already replaced it.
            if (_version == capturedVersion) {
              _cache.remove(organizationId);
            }
            debugPrint(
              'CapabilityResolver: failed to resolve capabilities '
              'for $organizationId: $error\n$stackTrace',
            );
            throw error;
          });
    });
  }

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
