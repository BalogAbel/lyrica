import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';

void main() {
  late String? currentUserId;
  late List<String> countedUsers;
  late Future<int> Function() countResult;
  late Future<void> Function() signOutStep;
  late int signOutCalls;
  late List<Object> reported;

  SignOutCommand buildCommand() => SignOutCommand(
    currentUserIdReader: () => currentUserId,
    countPendingWork: ({required userId}) {
      countedUsers.add(userId);
      return countResult();
    },
    signOut: () async {
      signOutCalls += 1;
      await signOutStep();
    },
    reportError: (error, _) => reported.add(error),
  );

  setUp(() {
    currentUserId = 'user-a';
    countedUsers = [];
    countResult = () async => 0;
    signOutStep = () async {};
    signOutCalls = 0;
    reported = [];
  });

  test('zero pending work signs out without asking', () async {
    final asked = <int?>[];
    final outcome = await buildCommand().run(
      confirmDiscard: (count) async {
        asked.add(count);
        return true;
      },
    );
    expect(outcome, SignOutOutcome.signedOut);
    expect(asked, isEmpty);
    expect(countedUsers, ['user-a']);
    expect(signOutCalls, 1);
  });

  test('pending work asks with the count; confirming signs out', () async {
    countResult = () async => 3;
    final asked = <int?>[];
    final outcome = await buildCommand().run(
      confirmDiscard: (count) async {
        asked.add(count);
        return true;
      },
    );
    expect(outcome, SignOutOutcome.signedOut);
    expect(asked, [3]);
    expect(signOutCalls, 1);
  });

  test('cancelling deletes nothing', () async {
    countResult = () async => 1;
    final outcome = await buildCommand().run(
      confirmDiscard: (_) async => false,
    );
    expect(outcome, SignOutOutcome.cancelled);
    expect(signOutCalls, 0);
  });

  test('an unreadable count asks with null, never as zero', () async {
    countResult = () async => throw StateError('storage failure');
    final asked = <int?>[];
    final outcome = await buildCommand().run(
      confirmDiscard: (count) async {
        asked.add(count);
        return false;
      },
    );
    expect(outcome, SignOutOutcome.cancelled);
    expect(asked, [null]);
    expect(signOutCalls, 0);
  });

  test('no current user asks with null and counts nobody', () async {
    currentUserId = null;
    final asked = <int?>[];
    await buildCommand().run(
      confirmDiscard: (count) async {
        asked.add(count);
        return false;
      },
    );
    expect(asked, [null]);
    expect(countedUsers, isEmpty);
    expect(signOutCalls, 0);
  });

  test('a user change during the count supersedes the run', () async {
    final count = Completer<int>();
    countResult = () => count.future;
    final asked = <int?>[];
    final run = buildCommand().run(
      confirmDiscard: (value) async {
        asked.add(value);
        return true;
      },
    );
    currentUserId = 'user-b';
    count.complete(0);
    expect(await run, SignOutOutcome.superseded);
    expect(asked, isEmpty);
    expect(signOutCalls, 0);
  });

  test('a user change while the dialog is open supersedes the run', () async {
    countResult = () async => 2;
    final answer = Completer<bool>();
    final run = buildCommand().run(confirmDiscard: (_) => answer.future);
    await Future<void>.delayed(Duration.zero);
    currentUserId = 'user-b';
    answer.complete(true);
    expect(await run, SignOutOutcome.superseded);
    expect(signOutCalls, 0);
  });

  test('a second run while one is in flight does nothing', () async {
    countResult = () async => 2;
    final answer = Completer<bool>();
    final command = buildCommand();
    final first = command.run(confirmDiscard: (_) => answer.future);
    await Future<void>.delayed(Duration.zero);
    final asked = <int?>[];
    final second = await command.run(
      confirmDiscard: (count) async {
        asked.add(count);
        return true;
      },
    );
    expect(second, SignOutOutcome.alreadyRunning);
    expect(asked, isEmpty);

    answer.complete(false);
    expect(await first, SignOutOutcome.cancelled);
    countResult = () async => 0;
    expect(
      await command.run(confirmDiscard: (_) async => true),
      SignOutOutcome.signedOut,
    );
  });

  test('a failing sign-out sequence is reported once, gives failed and '
      'releases the lock', () async {
    signOutStep = () async => throw StateError('purge failed');
    final command = buildCommand();
    expect(
      await command.run(confirmDiscard: (_) async => true),
      SignOutOutcome.failed,
    );
    expect(reported, hasLength(1));
    expect(reported.single, isA<StateError>());

    signOutStep = () async {};
    expect(
      await command.run(confirmDiscard: (_) async => true),
      SignOutOutcome.signedOut,
    );
  });

  test('a throwing confirmation is reported once and is not a '
      'confirmation', () async {
    countResult = () async => 1;
    final outcome = await buildCommand().run(
      confirmDiscard: (_) async => throw StateError('dialog failed'),
    );
    expect(outcome, SignOutOutcome.cancelled);
    expect(reported, hasLength(1));
    expect(signOutCalls, 0);
  });
}
