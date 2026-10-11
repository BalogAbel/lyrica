import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/core/capability.dart';
import 'capability_snapshot_store.dart';

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
    final codes = response is List
        ? response.map((e) => e.toString()).toSet()
        : <String>{};
    return Capability.values.where((c) => codes.contains(c.code)).toSet();
  }
}

class CapabilityResolver extends ChangeNotifier {
  CapabilityResolver({
    required this._gateway,
    this._snapshotStore,
    String? Function()? readUserId,
  }) : _readUserId = readUserId ?? _nobody;

  static String? _nobody() => null;

  final CapabilityGateway _gateway;
  // SG6 (docs/specs/2026-10-05-offline-first-startup-gate.md): the last
  // known capabilities, so gated affordances answer offline from the local
  // store instead of after the network fails.
  final CapabilitySnapshotStore? _snapshotStore;
  final String? Function() _readUserId;

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

  bool _disposed = false;

  Future<Set<Capability>> capabilitiesFor(String organizationId) {
    // Capture version before putIfAbsent so the factory closure can guard
    // against writing stale data when invalidate() fires mid-flight.
    final capturedVersion = _version;
    return _cache.putIfAbsent(
      organizationId,
      () => _load(organizationId, capturedVersion),
    );
  }

  Future<Set<Capability>> _load(
    String organizationId,
    int capturedVersion,
  ) async {
    final userId = _readUserId();
    final stored = await _readStored(userId, organizationId);
    if (stored != null) {
      if (_version == capturedVersion) {
        _resolved[organizationId] = stored;
      }
      unawaited(
        _refreshInBackground(organizationId, userId, capturedVersion, stored),
      );
      return stored;
    }
    try {
      final resolved = await _gateway.resolve(organizationId);
      // Only populate the synchronous cache, and only persist, if the
      // resolver has not been invalidated since this load started: an answer
      // arriving after a sign-out must never reach the store.
      if (_version == capturedVersion) {
        _resolved[organizationId] = resolved;
        await _persist(userId, organizationId, resolved);
      }
      return resolved;
    } catch (error, stackTrace) {
      // Only evict the failed future if it is still the current one —
      // a racing invalidate() may have already replaced it.
      if (_version == capturedVersion) {
        _cache.remove(organizationId);
      }
      debugPrint(
        'CapabilityResolver: failed to resolve capabilities '
        'for $organizationId: $error\n$stackTrace',
      );
      rethrow;
    }
  }

  Future<void> _refreshInBackground(
    String organizationId,
    String? userId,
    int capturedVersion,
    Set<Capability> stored,
  ) async {
    try {
      final resolved = await _gateway.resolve(organizationId);
      if (_version != capturedVersion) {
        return;
      }
      _resolved[organizationId] = resolved;
      _cache[organizationId] = Future.value(resolved);
      await _persist(userId, organizationId, resolved);
      if (!setEquals(resolved, stored) && !_disposed) {
        notifyListeners();
      }
    } catch (error) {
      // SG6: a failed resolve keeps the stored set.
      debugPrint(
        'CapabilityResolver: background refresh failed for '
        '$organizationId; keeping the stored capabilities: $error',
      );
    }
  }

  Future<Set<Capability>?> _readStored(
    String? userId,
    String organizationId,
  ) async {
    final store = _snapshotStore;
    if (store == null || userId == null) {
      return null;
    }
    try {
      final codes = await store.readCapabilityCodes(
        userId: userId,
        organizationId: organizationId,
      );
      if (codes == null) {
        return null;
      }
      return Capability.values.where((c) => codes.contains(c.code)).toSet();
    } catch (error) {
      debugPrint(
        'CapabilityResolver: could not read stored capabilities: $error',
      );
      return null;
    }
  }

  Future<void> _persist(
    String? userId,
    String organizationId,
    Set<Capability> capabilities,
  ) async {
    final store = _snapshotStore;
    if (store == null || userId == null) {
      return;
    }
    try {
      await store.writeCapabilityCodes(
        userId: userId,
        organizationId: organizationId,
        codes: {for (final capability in capabilities) capability.code},
      );
    } catch (error) {
      debugPrint('CapabilityResolver: could not store capabilities: $error');
    }
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
