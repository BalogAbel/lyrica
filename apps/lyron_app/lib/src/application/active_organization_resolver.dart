import 'dart:io';

import 'package:lyron_app/src/application/active_organization_resolution.dart';

/// Single owner of active-organization resolution for the application layer.
///
/// Composes the pure resolution functions into the three flavors the app needs:
/// the raw backend resolution, the connectivity-gated cached-fallback resolution
/// (ADR-016), and the resolution projected to an organization id. Provider seams
/// (`activeOrganizationResolutionProvider`, `membershipResolutionProvider`,
/// `activeOrganizationReaderProvider`) delegate here so resolution lives in one
/// testable place. See ADR-022.
final class ActiveOrganizationResolver {
  ActiveOrganizationResolver({
    required this._resolveRawReader,
    required this._readUserId,
    required this._readCachedOrganizationId,
  });

  final ActiveOrganizationResolutionReader _resolveRawReader;
  final String? Function() _readUserId;
  final Future<String?> Function({required String userId})
  _readCachedOrganizationId;

  /// Raw backend resolution, no fallback.
  Future<ActiveOrganizationResolution> resolveRaw() => _resolveRawReader();

  /// Raw resolution, then connectivity-gated cached fallback (ADR-016): a cached
  /// organization id is only reused on [ActiveOrganizationUnknownConnectivityFailure].
  Future<ActiveOrganizationResolution> resolveWithCachedFallback() async {
    final resolution = await resolveRaw();
    return resolveMembershipWithCachedFallback(
      resolution: resolution,
      userId: _readUserId(),
      readCachedOrganizationId: _readCachedOrganizationId,
    );
  }

  /// Projects the raw resolution to an organization id, throwing on failure
  /// outcomes so callers surface the correct gate state.
  Future<String?> resolveOrganizationId() async {
    final resolution = await resolveRaw();
    return switch (resolution) {
      ActiveOrganizationSelected(:final organizationId) => organizationId,
      ActiveOrganizationVerifiedEmpty() => null,
      ActiveOrganizationUnknownConnectivityFailure() =>
        throw const SocketException(
          'active organization lookup temporarily unavailable',
        ),
      ActiveOrganizationUnknownNonConnectivityFailure() => throw StateError(
        'active organization lookup failed',
      ),
    };
  }
}
