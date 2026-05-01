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

    final List<String> organizationIds;
    try {
      organizationIds = List<String>.from(response);
    } on TypeError {
      return const ActiveOrganizationResolution.unknownNonConnectivityFailure();
    }

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
