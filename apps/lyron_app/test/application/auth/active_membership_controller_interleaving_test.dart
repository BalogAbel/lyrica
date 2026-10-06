import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/active_membership_controller.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';

/// Seeded random interleavings of everything that can touch the membership
/// controller (S0 8c). A reference model written from the SG3/SG4 rules, not
/// from the controller's code, predicts after every step what the gate must
/// show; the test also pins which events are allowed to change it.
///
/// Rules the model encodes:
/// - a resolution result is applied only if it belongs to the current user's
///   most recently started resolution, and nothing superseded it since;
/// - reset, a purge for the current user and any change of the current user
///   supersede the running resolution (and end its running state/timer);
/// - the purge handler is authoritative for the current user, and a no-op for
///   anyone else;
/// - an unknown result never replaces a same-user `selected`;
/// - another user's result is never shown (a user switch only hides).
///
/// Assumption mirrored from production: every change of the current user is
/// followed by `noteInputsChanged` (the auth controller notifies on each).
///
/// On failure the message carries the seed, the step and the recent trace.
void main() {
  const seeds = [42, 7, 1234, 31337, 2026, 99, 5, 8675309];
  const stepsPerSeed = 250;

  for (final seed in seeds) {
    test('membership controller interleavings, seed $seed '
        '($stepsPerSeed steps)', () {
      fakeAsync((async) {
        _Run(seed: seed, steps: stepsPerSeed, async: async).execute();
      });
    });
  }
}

const _timeoutMs = 15000; // SG4 default of firstRunTimeout
const _users = <String?>['user-a', 'user-b', null];

/// One resolution the test started. [token] is what the controller returned.
class _Started {
  _Started({
    required this.id,
    required this.user,
    required this.token,
    required this.atMs,
  });

  final int id;
  final String user;
  final int token;
  final int atMs;
  bool delivered = false;
}

/// What the gate shows, as far as the test can see it.
class _Snapshot {
  _Snapshot(this.view, this.last, this.timers);

  final MembershipGateView view;
  final ActiveOrganizationResolution? last;
  final int timers;

  bool sameAs(_Snapshot other) =>
      view == other.view && last == other.last && timers == other.timers;

  @override
  String toString() => '(view: $view, last: $last, timers: $timers)';
}

class _Run {
  _Run({required this.seed, required this.steps, required this.async})
    : random = Random(seed);

  final int seed;
  final int steps;
  final FakeAsync async;
  final Random random;

  // The system under test.
  String? current;
  late final ActiveMembershipController controller = ActiveMembershipController(
    currentUserIdReader: () => current,
  );

  // The reference model.
  String? modelUser;
  _Started? live; // the only resolution whose answer may still count
  ActiveOrganizationResolution? stored;
  String? storedUser;
  int nowMs = 0;

  final started = <_Started>[];
  final trace = <String>[];
  int step = 0;
  int outcomeCounter = 0;
  // Set by an event that, by the rules, must not change what the gate shows.
  bool inert = false;

  void execute() {
    for (step = 0; step < steps; step++) {
      final before = _observe();
      inert = false;
      final event = _pickAndApply();
      _check(before, event);
    }
    controller.dispose();
    expect(
      async.pendingTimers,
      isEmpty,
      reason: _context('timer left after dispose'),
    );
  }

  // --- events -------------------------------------------------------------

  String _pickAndApply() {
    final roll = random.nextInt(100);
    String event;
    if (roll < 25) {
      event = _begin();
    } else if (roll < 55) {
      event = _complete();
    } else if (roll < 60) {
      event = _reset();
    } else if (roll < 65) {
      event = _signOut();
    } else if (roll < 73) {
      event = _switchUser();
    } else if (roll < 78) {
      event = _bounce();
    } else if (roll < 86) {
      event = _purge();
    } else if (roll < 95) {
      event = _elapse();
    } else {
      event = _note();
    }
    trace.add('#$step $event');
    return event;
  }

  String _begin() {
    final user = modelUser;
    if (user == null) {
      return _note();
    }
    final token = controller.beginResolution(userId: user);
    final run = _Started(
      id: started.length,
      user: user,
      token: token,
      atMs: nowMs,
    );
    started.add(run);
    // model
    if (storedUser != null && storedUser != user) {
      stored = null;
      storedUser = null;
    }
    live = run;
    return 'begin($user) -> r${run.id}';
  }

  String _complete() {
    final open = started.where((r) => !r.delivered).toList();
    if (open.isEmpty) {
      return _note();
    }
    // Half the time the newest resolution answers (the interesting case for a
    // user who left and came back), otherwise any outstanding one, however old.
    final run = random.nextBool()
        ? open.last
        : open[random.nextInt(open.length)];
    run.delivered = true;
    final outcome = _outcome(run);
    controller.update(outcome, userId: run.user, token: run.token);
    // model
    final applies = identical(live, run);
    inert = !applies;
    if (applies) {
      final isFailure =
          outcome is ActiveOrganizationUnknownConnectivityFailure ||
          outcome is ActiveOrganizationUnknownNonConnectivityFailure;
      final keep =
          stored is ActiveOrganizationSelected &&
          storedUser == run.user &&
          isFailure;
      live = null;
      if (!keep) {
        stored = outcome;
        storedUser = run.user;
      }
    }
    return 'complete(r${run.id} of ${run.user}, $outcome) '
        '${applies ? 'APPLIES' : 'stale'}';
  }

  String _reset() {
    controller.reset();
    live = null;
    stored = null;
    storedUser = null;
    return 'reset';
  }

  String _signOut() {
    current = null;
    controller.noteInputsChanged();
    controller.reset();
    modelUser = null;
    live = null;
    stored = null;
    storedUser = null;
    return 'signOut';
  }

  String _switchUser() {
    final next = _users[random.nextInt(_users.length)];
    current = next;
    controller.noteInputsChanged();
    if (next != modelUser) {
      modelUser = next;
      live = null;
    }
    return 'switchUser($next)';
  }

  /// The user leaves and comes back with no resolution begun in between
  /// (A to B to A, a reauth that is cancelled): everything started before
  /// the departure is superseded.
  String _bounce() {
    final home = current;
    final away = _users.firstWhere((u) => u != home);
    current = away;
    controller.noteInputsChanged();
    current = home;
    controller.noteInputsChanged();
    live = null;
    return 'bounce($home via $away)';
  }

  String _purge() {
    final user = _users[random.nextInt(2)]!;
    controller.recordPurgeResult(userId: user);
    inert = user != modelUser;
    if (user == modelUser) {
      live = null;
      stored = const ActiveOrganizationResolution.verifiedEmpty();
      storedUser = user;
    }
    return 'purge($user)';
  }

  String _elapse() {
    final wasPending = _timerPending;
    final ms = random.nextInt(21) * 1000;
    async.elapse(Duration(milliseconds: ms));
    nowMs += ms;
    // Only the first-run timer may change the view, and only by expiring.
    inert = !(wasPending && !_timerPending);
    return 'elapse(${ms}ms)';
  }

  String _note() {
    controller.noteInputsChanged();
    inert = true;
    return 'noteInputsChanged';
  }

  ActiveOrganizationResolution _outcome(_Started run) {
    outcomeCounter++;
    return switch (random.nextInt(4)) {
      0 => ActiveOrganizationResolution.selected('${run.user}-$outcomeCounter'),
      1 => const ActiveOrganizationResolution.verifiedEmpty(),
      2 => const ActiveOrganizationResolution.unknownConnectivityFailure(),
      _ => const ActiveOrganizationResolution.unknownNonConnectivityFailure(),
    };
  }

  // --- model predictions --------------------------------------------------

  ActiveOrganizationResolution? get _visible =>
      stored != null && storedUser == modelUser ? stored : null;

  bool get _timerPending {
    final run = live;
    return run != null && nowMs < run.atMs + _timeoutMs;
  }

  MembershipGateView get _expectedView {
    final result = _visible;
    if (result == null) {
      return _timerPending
          ? MembershipGateView.resolving
          : MembershipGateView.connectivityFailure;
    }
    return switch (result) {
      ActiveOrganizationSelected() => MembershipGateView.home,
      ActiveOrganizationVerifiedEmpty() => MembershipGateView.inviteRequired,
      ActiveOrganizationUnknownConnectivityFailure() =>
        MembershipGateView.connectivityFailure,
      ActiveOrganizationUnknownNonConnectivityFailure() =>
        MembershipGateView.nonConnectivityFailure,
    };
  }

  // --- checks -------------------------------------------------------------

  _Snapshot _observe() => _Snapshot(
    controller.viewFor(hasPendingInvite: false),
    controller.last,
    async.pendingTimers.length,
  );

  void _check(_Snapshot before, String event) {
    final after = _observe();

    // The controller and the model agree on who is current.
    expect(current, modelUser, reason: _context('test bookkeeping'));

    // The running resolution and its timer: present exactly while the model's
    // live resolution is, and only until the SG4 timeout (invariant 2).
    expect(
      after.timers,
      _timerPending ? 1 : 0,
      reason: _context('timer vs model after $event'),
    );

    if (modelUser != null) {
      // The view and the live result for the current user (invariant 1).
      expect(
        after.last,
        _visible,
        reason: _context('last for $modelUser after $event'),
      );
      expect(
        after.view,
        _expectedView,
        reason: _context('view for $modelUser after $event'),
      );
      // Never another user's result.
      final shown = after.last;
      if (shown is ActiveOrganizationSelected) {
        expect(
          shown.organizationId,
          startsWith('$modelUser-'),
          reason: _context('imported another user result after $event'),
        );
      }
    } else {
      // Nobody is current: nothing may be running.
      expect(
        after.timers,
        0,
        reason: _context('a resolution runs with nobody current'),
      );
    }

    // Events that, by the rules, may not change anything the gate shows: a
    // stale result, a purge for someone else, an input note, a clock tick
    // that expires nothing (invariants 1 and 2).
    if (inert && modelUser != null) {
      expect(
        after.sameAs(before),
        isTrue,
        reason: _context('$event must not change $before, got $after'),
      );
    }

    // A begin never changes what the current user already sees as a result.
    if (event.startsWith('begin')) {
      expect(
        after.last,
        before.last,
        reason: _context('begin changed the live result'),
      );
    }
    // A reset forgets the result.
    if (event == 'reset' || event == 'signOut') {
      expect(after.last, isNull, reason: _context('reset kept a result'));
    }
  }

  String _context(String what) {
    final recent = trace.length > 14
        ? trace.sublist(trace.length - 14)
        : List<String>.of(trace);
    return 'seed=$seed step=$step: $what\nrecent events:\n${recent.join('\n')}';
  }
}
