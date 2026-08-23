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
    return (await resolveWithCachedFallbackDetailed()).resolution;
  }

  /// YELLOW 4 (final whole-branch review, D5.2): [resolveWithCachedFallback]
  /// collapses a cached-fallback [ActiveOrganizationSelected] into the exact
  /// same shape as a genuine, fresh, online [ActiveOrganizationSelected] --
  /// a caller with only that return value cannot tell them apart. D5.2
  /// forbids a connectivity failure from moving the membership-revocation
  /// marker in either direction, so a caller that acts on the marker (see
  /// `lastKnownIdentityPersistenceProvider` in auth_providers.dart) needs
  /// the distinction this method exposes: [wasCachedFallback] is `true`
  /// only when the raw resolution was itself a connectivity failure AND the
  /// fallback substituted a cached organization id for it.
  Future<({ActiveOrganizationResolution resolution, bool wasCachedFallback})>
  resolveWithCachedFallbackDetailed() async {
    final resolution = await resolveRaw();
    final withFallback = await resolveMembershipWithCachedFallback(
      resolution: resolution,
      userId: _readUserId(),
      readCachedOrganizationId: _readCachedOrganizationId,
    );
    final wasCachedFallback =
        resolution is ActiveOrganizationUnknownConnectivityFailure &&
        withFallback is ActiveOrganizationSelected;
    return (resolution: withFallback, wasCachedFallback: wasCachedFallback);
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
