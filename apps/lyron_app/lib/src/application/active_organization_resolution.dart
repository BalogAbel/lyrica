import 'package:lyron_app/src/shared/connectivity_failure.dart';

typedef ActiveOrganizationResolutionReader =
    Future<ActiveOrganizationResolution> Function();

sealed class ActiveOrganizationResolution {
  const ActiveOrganizationResolution();

  const factory ActiveOrganizationResolution.selected(String organizationId) =
      ActiveOrganizationSelected;
  const factory ActiveOrganizationResolution.verifiedEmpty() =
      ActiveOrganizationVerifiedEmpty;
  const factory ActiveOrganizationResolution.unknownConnectivityFailure() =
      ActiveOrganizationUnknownConnectivityFailure;
  const factory ActiveOrganizationResolution.unknownNonConnectivityFailure() =
      ActiveOrganizationUnknownNonConnectivityFailure;

  @override
  bool operator ==(Object other) {
    final self = this;
    if (self is ActiveOrganizationSelected &&
        other is ActiveOrganizationSelected) {
      return other.organizationId == self.organizationId;
    }

    return other.runtimeType == runtimeType;
  }

  @override
  int get hashCode {
    if (this case ActiveOrganizationSelected(:final organizationId)) {
      return Object.hash(runtimeType, organizationId);
    }

    return runtimeType.hashCode;
  }
}

final class ActiveOrganizationSelected extends ActiveOrganizationResolution {
  const ActiveOrganizationSelected(this.organizationId);

  final String organizationId;
}

final class ActiveOrganizationVerifiedEmpty
    extends ActiveOrganizationResolution {
  const ActiveOrganizationVerifiedEmpty();
}

final class ActiveOrganizationUnknownConnectivityFailure
    extends ActiveOrganizationResolution {
  const ActiveOrganizationUnknownConnectivityFailure();
}

final class ActiveOrganizationUnknownNonConnectivityFailure
    extends ActiveOrganizationResolution {
  const ActiveOrganizationUnknownNonConnectivityFailure();
}

Future<ActiveOrganizationResolution> resolveActiveOrganizationResolution(
  Future<Object?> Function() lookup,
) async {
  try {
    final response = await lookup();
    if (response is! List) {
      return const ActiveOrganizationResolution.unknownNonConnectivityFailure();
    }

    final organizationIds = List<String>.from(response);

    if (organizationIds.isEmpty) {
      return const ActiveOrganizationResolution.verifiedEmpty();
    }

    organizationIds.sort();
    return ActiveOrganizationResolution.selected(organizationIds.first);
  } catch (error) {
    if (isConnectivityFailure(error)) {
      return const ActiveOrganizationResolution.unknownConnectivityFailure();
    }

    return const ActiveOrganizationResolution.unknownNonConnectivityFailure();
  }
}

/// Returns [resolution] unchanged unless it is an
/// [ActiveOrganizationUnknownConnectivityFailure] AND a [userId] is present AND
/// a cached organization id can be read for that user — in which case it returns
/// `ActiveOrganizationResolution.selected(cachedOrgId)`. If the cache read
/// throws, the original [resolution] is returned — the fallback is best-effort
/// and must never escalate a recoverable connectivity failure into a crash.
///
/// Extracted as a pure top-level function so it can be unit-tested without any
/// Riverpod or Supabase dependency.
Future<ActiveOrganizationResolution> resolveMembershipWithCachedFallback({
  required ActiveOrganizationResolution resolution,
  required String? userId,
  required Future<String?> Function({required String userId})
  readCachedOrganizationId,
}) async {
  if (resolution is! ActiveOrganizationUnknownConnectivityFailure) {
    return resolution;
  }
  if (userId == null) return resolution;
  try {
    final cachedOrgId = await readCachedOrganizationId(userId: userId);
    if (cachedOrgId == null) return resolution;
    return ActiveOrganizationResolution.selected(cachedOrgId);
  } catch (_) {
    // Best-effort fallback: a cache read error must not escalate a recoverable
    // connectivity failure into an unhandled crash. Keep the original
    // resolution so the gate shows the connectivity message instead.
    return resolution;
  }
}
