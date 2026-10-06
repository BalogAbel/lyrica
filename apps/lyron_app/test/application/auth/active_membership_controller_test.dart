import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/active_membership_controller.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';

void main() {
  const selected = ActiveOrganizationResolution.selected('org-1');
  const empty = ActiveOrganizationResolution.verifiedEmpty();
  const offline = ActiveOrganizationResolution.unknownConnectivityFailure();
  const broken = ActiveOrganizationResolution.unknownNonConnectivityFailure();

  MembershipGateView viewOf(ActiveMembershipController controller) =>
      controller.viewFor(hasPendingInvite: false);

  test('starts unresolved; with nothing running it shows the connectivity '
      'message', () {
    final controller = ActiveMembershipController();
    addTearDown(controller.dispose);

    expect(controller.last, isNull);
    expect(viewOf(controller), MembershipGateView.connectivityFailure);
    expect(controller.allowsAuthenticatedRoutes, isFalse);
  });

  test('an update without a user id still opens the gate (existing '
      'callers)', () {
    final controller = ActiveMembershipController()..update(selected);
    addTearDown(controller.dispose);

    expect(controller.last, selected);
    expect(viewOf(controller), MembershipGateView.home);
    expect(controller.allowsAuthenticatedRoutes, isTrue);
  });

  test('a known organization opens the gate before any resolution (SG1)', () {
    final controller = ActiveMembershipController(
      currentUserIdReader: () => 'user-1',
      knownOrganizationIdReader: () => 'org-1',
    );
    addTearDown(controller.dispose);

    expect(viewOf(controller), MembershipGateView.home);
    expect(controller.allowsAuthenticatedRoutes, isTrue);
  });

  test('a running resolution shows the loading state until the first-run '
      'timeout, then the connectivity message (SG4)', () {
    fakeAsync((async) {
      final controller = ActiveMembershipController(
        currentUserIdReader: () => 'user-1',
      );

      controller.beginResolution(userId: 'user-1');
      expect(viewOf(controller), MembershipGateView.resolving);

      async.elapse(const Duration(seconds: 14));
      expect(viewOf(controller), MembershipGateView.resolving);

      async.elapse(const Duration(seconds: 1));
      expect(viewOf(controller), MembershipGateView.connectivityFailure);

      controller.update(selected, userId: 'user-1');
      expect(viewOf(controller), MembershipGateView.home);
      controller.dispose();
    });
  });

  test('a live connectivity failure shows the message without waiting for '
      'the timer', () {
    fakeAsync((async) {
      final controller = ActiveMembershipController(
        currentUserIdReader: () => 'user-1',
      );
      controller.beginResolution(userId: 'user-1');
      controller.update(offline, userId: 'user-1');

      expect(viewOf(controller), MembershipGateView.connectivityFailure);
      controller.dispose();
    });
  });

  test('an unknown result never replaces a selected result for the same '
      'user (SG3)', () {
    final controller = ActiveMembershipController(
      currentUserIdReader: () => 'user-1',
    );
    addTearDown(controller.dispose);

    controller.update(selected, userId: 'user-1');
    controller.update(offline, userId: 'user-1');
    expect(controller.last, selected);
    controller.update(broken, userId: 'user-1');
    expect(controller.last, selected);

    controller.update(empty, userId: 'user-1');
    expect(controller.last, empty, reason: 'verifiedEmpty is not a failure');
  });

  test('a result for a user who is no longer current is dropped (SG3)', () {
    final controller = ActiveMembershipController(
      currentUserIdReader: () => 'user-2',
    );
    addTearDown(controller.dispose);

    controller.update(selected, userId: 'user-1');

    expect(controller.last, isNull);
  });

  test('another user never sees the previous user result (SG3)', () {
    var current = 'user-1';
    final controller = ActiveMembershipController(
      currentUserIdReader: () => current,
    );
    addTearDown(controller.dispose);

    controller.update(selected, userId: 'user-1');
    current = 'user-2';
    expect(controller.last, isNull);

    controller.beginResolution(userId: 'user-2');
    expect(viewOf(controller), MembershipGateView.resolving);
  });

  test('a late result after an explicit sign-out is dropped, so the same '
      'user signing in again starts clean (SG3, F3)', () {
    String? current = 'user-1';
    final controller = ActiveMembershipController(
      currentUserIdReader: () => current,
    );
    addTearDown(controller.dispose);

    controller.beginResolution(userId: 'user-1');
    controller.reset();
    current = null;
    controller.update(empty, userId: 'user-1');
    expect(controller.last, isNull);

    current = 'user-1';
    controller.beginResolution(userId: 'user-1');
    expect(viewOf(controller), MembershipGateView.resolving);
  });

  test('a dropped result for the user whose resolution was running stops it, '
      'so the new current user is not left loading (SG3, F4)', () {
    fakeAsync((async) {
      var current = 'user-b';
      final controller = ActiveMembershipController(
        currentUserIdReader: () => current,
      );
      controller.beginResolution(userId: 'user-b');
      current = 'user-a';

      controller.update(selected, userId: 'user-b');

      expect(controller.last, isNull);
      expect(viewOf(controller), MembershipGateView.connectivityFailure);
      expect(async.pendingTimers, isEmpty);
      controller.dispose();
    });
  });

  test('a dropped result for another user never stops the current user '
      'resolution (SG3, F4)', () {
    fakeAsync((async) {
      final controller = ActiveMembershipController(
        currentUserIdReader: () => 'user-a',
      );
      controller.beginResolution(userId: 'user-a');

      controller.update(selected, userId: 'user-b');

      expect(viewOf(controller), MembershipGateView.resolving);
      expect(async.pendingTimers, hasLength(1));
      async.elapse(const Duration(seconds: 15));
      expect(viewOf(controller), MembershipGateView.connectivityFailure);
      controller.dispose();
    });
  });

  test('a resolution running for a user who is not current does not '
      'count as loading for the current user (SG4, F4)', () {
    fakeAsync((async) {
      final controller = ActiveMembershipController(
        currentUserIdReader: () => 'user-a',
      );
      controller.beginResolution(userId: 'user-b');

      expect(viewOf(controller), MembershipGateView.connectivityFailure);
      controller.dispose();
    });
  });

  test('reset forgets the live resolution', () {
    final controller = ActiveMembershipController(
      currentUserIdReader: () => 'user-1',
    )..update(selected, userId: 'user-1');
    addTearDown(controller.dispose);

    controller.reset();

    expect(controller.last, isNull);
  });

  test('noteInputsChanged notifies listeners', () {
    final controller = ActiveMembershipController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.noteInputsChanged();

    expect(notifications, 1);
  });

  test('allowsAuthenticatedRoutes follows the pending invite reader', () {
    var pending = true;
    final controller = ActiveMembershipController(
      currentUserIdReader: () => 'user-1',
      knownOrganizationIdReader: () => 'org-1',
      hasPendingInviteReader: () => pending,
    )..update(empty, userId: 'user-1');
    addTearDown(controller.dispose);

    expect(controller.allowsAuthenticatedRoutes, isFalse);
    pending = false;
    expect(controller.allowsAuthenticatedRoutes, isTrue);
  });

  group('per-resolution token (S0 8c)', () {
    test('a result from a resolution started before reset is ignored, so the '
        'resolution after it keeps running and decides (C2)', () {
      fakeAsync((async) {
        final controller = ActiveMembershipController(
          currentUserIdReader: () => 'user-a',
        );
        final r1 = controller.beginResolution(userId: 'user-a');
        controller.reset();
        final r2 = controller.beginResolution(userId: 'user-a');

        controller.update(empty, userId: 'user-a', token: r1);

        expect(controller.last, isNull);
        expect(viewOf(controller), MembershipGateView.resolving);
        expect(async.pendingTimers, hasLength(1));

        controller.update(selected, userId: 'user-a', token: r2);

        expect(controller.last, selected);
        expect(viewOf(controller), MembershipGateView.home);
        expect(async.pendingTimers, isEmpty);
        controller.dispose();
      });
    });

    test('a later resolution supersedes an earlier one for the same user, '
        'whichever answers first (Retry over a slow refresh)', () {
      fakeAsync((async) {
        final controller = ActiveMembershipController(
          currentUserIdReader: () => 'user-a',
        );
        final r1 = controller.beginResolution(userId: 'user-a');
        final r2 = controller.beginResolution(userId: 'user-a');

        controller.update(empty, userId: 'user-a', token: r1);
        expect(controller.last, isNull);
        expect(viewOf(controller), MembershipGateView.resolving);

        controller.update(selected, userId: 'user-a', token: r2);
        expect(controller.last, selected);
        controller.dispose();
      });
    });

    test('a user change invalidates the resolution running before it, even '
        'when the same user comes back (A to B to A)', () {
      fakeAsync((async) {
        var current = 'user-a';
        final controller = ActiveMembershipController(
          currentUserIdReader: () => current,
        );
        final r1 = controller.beginResolution(userId: 'user-a');
        current = 'user-b';
        controller.noteInputsChanged();
        current = 'user-a';
        controller.noteInputsChanged();

        controller.update(empty, userId: 'user-a', token: r1);

        expect(controller.last, isNull);
        expect(async.pendingTimers, isEmpty);
        controller.dispose();
      });
    });

    test('a user change is noticed at the next update even when nothing '
        'called noteInputsChanged', () {
      fakeAsync((async) {
        var current = 'user-a';
        final controller = ActiveMembershipController(
          currentUserIdReader: () => current,
        );
        final r1 = controller.beginResolution(userId: 'user-a');
        current = 'user-b';

        controller.update(selected, userId: 'user-a', token: r1);

        expect(controller.last, isNull);
        expect(viewOf(controller), MembershipGateView.connectivityFailure);
        expect(async.pendingTimers, isEmpty);
        controller.dispose();
      });
    });

    test('the latest resolution of a user who is not current ends the '
        'running state when it answers (F4 with tokens)', () {
      fakeAsync((async) {
        final controller = ActiveMembershipController(
          currentUserIdReader: () => 'user-a',
        );
        final token = controller.beginResolution(userId: 'user-b');

        controller.update(selected, userId: 'user-b', token: token);

        expect(controller.last, isNull);
        expect(async.pendingTimers, isEmpty);
        controller.dispose();
      });
    });

    test('a purge for the current user is authoritative: it ends the running '
        'resolution and a late result of that resolution is ignored', () {
      fakeAsync((async) {
        final controller = ActiveMembershipController(
          currentUserIdReader: () => 'user-a',
        );
        final r1 = controller.beginResolution(userId: 'user-a');

        controller.recordPurgeResult(userId: 'user-a');

        expect(controller.last, empty);
        expect(async.pendingTimers, isEmpty);

        controller.update(selected, userId: 'user-a', token: r1);
        expect(controller.last, empty);
        controller.dispose();
      });
    });

    test('a purge for a user who is not current changes nothing', () {
      fakeAsync((async) {
        final controller = ActiveMembershipController(
          currentUserIdReader: () => 'user-a',
        );
        final r1 = controller.beginResolution(userId: 'user-a');

        controller.recordPurgeResult(userId: 'user-b');

        expect(controller.last, isNull);
        expect(viewOf(controller), MembershipGateView.resolving);
        expect(async.pendingTimers, hasLength(1));

        controller.update(selected, userId: 'user-a', token: r1);
        expect(controller.last, selected);
        controller.dispose();
      });
    });

    test('a result begun before a purge never overrides a result that a later '
        'resolution recorded after it', () {
      final controller = ActiveMembershipController(
        currentUserIdReader: () => 'user-a',
      );
      addTearDown(controller.dispose);
      final r1 = controller.beginResolution(userId: 'user-a');
      controller.recordPurgeResult(userId: 'user-a');
      final r2 = controller.beginResolution(userId: 'user-a');
      controller.update(selected, userId: 'user-a', token: r2);

      controller.update(empty, userId: 'user-a', token: r1);

      expect(controller.last, selected);
    });

    test('an unknown result still never replaces selected, with tokens', () {
      final controller = ActiveMembershipController(
        currentUserIdReader: () => 'user-a',
      );
      addTearDown(controller.dispose);
      controller.update(
        selected,
        userId: 'user-a',
        token: controller.beginResolution(userId: 'user-a'),
      );

      controller.update(
        offline,
        userId: 'user-a',
        token: controller.beginResolution(userId: 'user-a'),
      );

      expect(controller.last, selected);
      expect(viewOf(controller), MembershipGateView.home);
    });
  });

  test('the first-run timer does nothing after dispose', () {
    fakeAsync((async) {
      final controller = ActiveMembershipController(
        currentUserIdReader: () => 'user-1',
      )..beginResolution(userId: 'user-1');
      controller.dispose();

      async.elapse(const Duration(seconds: 20));
      expect(async.pendingTimers, isEmpty);
    });
  });
}
