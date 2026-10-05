import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';

void main() {
  const selected = ActiveOrganizationResolution.selected('org-1');
  const empty = ActiveOrganizationResolution.verifiedEmpty();
  const offline = ActiveOrganizationResolution.unknownConnectivityFailure();
  const broken = ActiveOrganizationResolution.unknownNonConnectivityFailure();

  MembershipGateView decide({
    String? known,
    ActiveOrganizationResolution? live,
    bool pending = false,
    bool awaiting = false,
  }) {
    return decideMembershipGate(
      knownOrganizationId: known,
      liveResolution: live,
      hasPendingInvite: pending,
      awaitingFirstResolution: awaiting,
    );
  }

  group('with a known organization (SG1, SG2)', () {
    test('opens before any network answer', () {
      expect(decide(known: 'org-1'), MembershipGateView.home);
      expect(decide(known: 'org-1', awaiting: true), MembershipGateView.home);
    });

    test('stays open over every failure', () {
      expect(decide(known: 'org-1', live: offline), MembershipGateView.home);
      expect(decide(known: 'org-1', live: broken), MembershipGateView.home);
    });

    test('stays open after a live verifiedEmpty until the purge runs', () {
      expect(decide(known: 'org-1', live: empty), MembershipGateView.home);
    });

    test('shows the redeem screen for a live verifiedEmpty with a pending '
        'invite', () {
      expect(
        decide(known: 'org-1', live: empty, pending: true),
        MembershipGateView.redeem,
      );
    });

    test('ignores a pending invite while membership is selected', () {
      expect(
        decide(known: 'org-1', live: selected, pending: true),
        MembershipGateView.home,
      );
    });
  });

  group('without a known organization', () {
    test('follows the live resolution', () {
      expect(decide(live: selected), MembershipGateView.home);
      expect(decide(live: empty), MembershipGateView.inviteRequired);
      expect(decide(live: empty, pending: true), MembershipGateView.redeem);
      expect(decide(live: offline), MembershipGateView.connectivityFailure);
      expect(decide(live: broken), MembershipGateView.nonConnectivityFailure);
    });

    test('shows the loading state while the first resolution runs (SG4)', () {
      expect(decide(awaiting: true), MembershipGateView.resolving);
    });

    test('shows the connectivity message when nothing is running or the '
        'first-run timer elapsed', () {
      expect(decide(), MembershipGateView.connectivityFailure);
    });
  });
}
