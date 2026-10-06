import 'package:lyron_app/src/application/active_organization_resolution.dart';

/// What the membership gate in front of the authenticated home route shows.
/// See SG1 in docs/specs/2026-10-05-offline-first-startup-gate.md.
enum MembershipGateView {
  home,
  redeem,
  inviteRequired,
  resolving,
  connectivityFailure,
  nonConnectivityFailure,
}

/// The SG1 decision table: a pure function of local state, so no widget ever
/// awaits the network before deciding.
///
/// [knownOrganizationId] is the last known organization of the CURRENT user
/// (null when the stored identity belongs to someone else or has none).
/// [liveResolution] is the latest network resolution for the current user,
/// or null when none has completed. [awaitingFirstResolution] is true while
/// a resolution runs and the SG4 first-run timer has not elapsed.
MembershipGateView decideMembershipGate({
  required String? knownOrganizationId,
  required ActiveOrganizationResolution? liveResolution,
  required bool hasPendingInvite,
  required bool awaitingFirstResolution,
}) {
  if (knownOrganizationId != null) {
    // SG2: a live verifiedEmpty does not hide data that the ADR-035 D5 purge
    // has not removed. The purge clears the identity, which moves the
    // decision to the branch below. A pending invite is the one exception:
    // redemption only starts while its screen is mounted.
    if (liveResolution is ActiveOrganizationVerifiedEmpty && hasPendingInvite) {
      return MembershipGateView.redeem;
    }
    return MembershipGateView.home;
  }
  return switch (liveResolution) {
    ActiveOrganizationSelected() => MembershipGateView.home,
    ActiveOrganizationVerifiedEmpty() =>
      hasPendingInvite
          ? MembershipGateView.redeem
          : MembershipGateView.inviteRequired,
    ActiveOrganizationUnknownConnectivityFailure() =>
      MembershipGateView.connectivityFailure,
    ActiveOrganizationUnknownNonConnectivityFailure() =>
      MembershipGateView.nonConnectivityFailure,
    null =>
      awaitingFirstResolution
          ? MembershipGateView.resolving
          : MembershipGateView.connectivityFailure,
  };
}
