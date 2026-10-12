// Cross-user local-first ownership
// (docs/specs/2026-10-06-cross-user-local-first-ownership.md): a user must
// never see, or lose, another user's songs or plans through a local-first
// path. Real AppAuthController, real LocalDataLifecycle, Drift in-memory
// stores and the real different-user reauth providers
// (lastKnownIdentityPersistenceProvider, reauthPromptControllerProvider,
// pendingLocalWorkCounterProvider, membershipRefreshEffectProvider). Only the
// network edges are replaced: the auth session stream, the membership RPC,
// the organization lookup and the remote fetches. The two read gates only
// pause the real Drift reads for user A, to pin an interleaving.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';
import 'package:lyron_app/src/application/auth/pending_local_work_counter.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/application/song_library/drift_song_mutation_store.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/drift_pending_local_work_reader.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/presentation/auth/membership_gate.dart';
import 'package:lyron_app/src/presentation/auth/reauth_banner.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/drift_test_setup.dart';

const _userA = 'user-a';
const _emailA = 'a@lyron.local';
const _orgA = 'org-a';
const _userB = 'user-b';
const _emailB = 'b@lyron.local';
const _orgB = 'org-b';

const _sessionA = AppAuthSession(userId: _userA, email: _emailA);
const _sessionB = AppAuthSession(userId: _userB, email: _emailB);

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('establishment from another user\'s identity (F6)', () {
    test('B loses the session while the different-user reauth is pending; '
        'the catalog must not establish A\'s context for B', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      // Precondition: A is current (sessionExpired(A)), A's own data shows.
      expect(fixture.catalogContextUserId, _userA);

      await fixture.signInAs(_sessionB);
      expect(fixture.auth.state.status, AppAuthStatus.signedIn);
      expect(
        fixture.container.read(reauthPromptControllerProvider).pending,
        isNotNull,
        reason: 'A has pending work, so the different-user prompt is pending',
      );
      expect((await fixture.identityStore.read())?.userId, _userA);
      expect(fixture.gateViewForCurrentUser, MembershipGateView.home);

      // A non-retryable refresh failure: the session goes to null while the
      // app did not initiate a sign-out.
      await fixture.loseSession();
      expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
      expect(fixture.auth.state.currentUserId, _userB);
      expect(fixture.gateViewForCurrentUser, MembershipGateView.home);

      expect(
        fixture.catalogContextUserId,
        isNot(_userA),
        reason: 'the current user is B; A\'s catalog must not be established',
      );
      expect(await fixture.readSongTitles(), isNot(contains('A secret song')));
    });

    test('the same sequence must not establish A\'s planning context for '
        'B', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      expect(fixture.planningUserId, _userA);

      await fixture.signInAs(_sessionB);
      await fixture.loseSession();
      expect(fixture.auth.state.currentUserId, _userB);

      expect(fixture.planningUserId, isNot(_userA));
      expect(await fixture.readPlanNames(), isNot(contains('A secret plan')));
    });

    // AC1: B's way out after losing the session, in both gate states. The
    // gate and the re-auth banner are the real widgets.
    for (final bMembershipAnswered in [true, false]) {
      testWidgets(
        bMembershipAnswered
            ? 'B\'s way out when B\'s membership answered: home with the '
                  're-auth banner, and none of A\'s songs (AC1)'
            : 'B\'s way out when B\'s membership did not answer: the gate\'s '
                  'failure screen offers sign-in, and no context of A\'s (AC1)',
        (tester) async {
          late _Fixture fixture;
          await tester.runAsync(() async {
            fixture = await _Fixture.create(
              seedSongsForA: true,
              seedPlanningForA: true,
              membershipAnswersFor: bMembershipAnswered
                  ? const {_userA, _userB}
                  : const {_userA},
            );
            await fixture.coldStartAsA();
            await fixture.signInAs(_sessionB);
            await fixture.loseSession();
          });
          expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
          expect(fixture.auth.state.currentUserId, _userB);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: fixture.container,
              child: const MaterialApp(
                home: MembershipGate(child: Scaffold(body: ReauthBanner())),
              ),
            ),
          );

          if (bMembershipAnswered) {
            expect(fixture.gateViewForCurrentUser, MembershipGateView.home);
            expect(
              find.byKey(const Key('reauth-banner-action')),
              findsOneWidget,
            );
          } else {
            expect(
              fixture.gateViewForCurrentUser,
              MembershipGateView.connectivityFailure,
            );
            expect(
              find.byKey(const ValueKey('membership-gate-sign-in')),
              findsOneWidget,
            );
          }
          expect(fixture.catalogContextUserId, isNot(_userA));
          expect(fixture.planningUserId, isNot(_userA));

          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  });

  group('contexts held for the previous user (F7)', () {
    test('planning established for A from a sessionExpired cold start does '
        'not survive B\'s sign-in when B\'s planning lookup fails', () async {
      // A has plans cached but no songs, so the catalog never establishes
      // A's context and the catalog's I3 reset never reaches planning.
      final fixture = await _Fixture.create(
        seedSongsForA: false,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      expect(fixture.planningUserId, _userA);
      expect(fixture.catalogContextUserId, isNull);

      await fixture.signInAs(_sessionB);
      expect(fixture.auth.state.currentUserId, _userB);
      expect(fixture.gateViewForCurrentUser, MembershipGateView.home);

      expect(fixture.planningUserId, isNot(_userA));
      expect(await fixture.readPlanNames(), isNot(contains('A secret plan')));
    });

    test('with songs and plans cached, nothing of A\'s survives B\'s '
        'sign-in', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      expect(fixture.planningUserId, _userA);
      expect(fixture.catalogContextUserId, _userA);

      await fixture.signInAs(_sessionB);
      expect(fixture.auth.state.currentUserId, _userB);

      expect(fixture.catalogContextUserId, isNot(_userA));
      expect(fixture.planningUserId, isNot(_userA));
      expect(await fixture.readPlanNames(), isNot(contains('A secret plan')));
    });

    test('B\'s planning organization answering while A\'s reauth prompt is '
        'pending must not delete A\'s plans or pending work (F8)', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: false,
        seedPlanningForA: true,
        lookupAnswersFor: const {_userB},
      );
      await fixture.coldStartAsA();
      expect(fixture.planningUserId, _userA);
      expect(await fixture.pendingPlanningMutationCount(_userA), 1);

      await fixture.signInAs(_sessionB);
      expect(
        fixture.container.read(reauthPromptControllerProvider).pending,
        isNotNull,
      );
      expect(fixture.planningUserId, _userB);

      expect(
        await fixture.pendingPlanningMutationCount(_userA),
        1,
        reason: 'only a confirmed different-user wipe may delete A\'s work',
      );
      expect(
        await fixture.planningStore.hasProjection(
          userId: _userA,
          organizationId: _orgA,
        ),
        isTrue,
      );
    });

    test('a planning establishment started for A does not land after B '
        'signs in', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: false,
        seedPlanningForA: true,
      );
      fixture.planningReadGate.hold();
      await fixture.coldStartAsA();
      expect(fixture.planningUserId, isNull, reason: 'held on the gate');

      await fixture.signInAs(_sessionB);
      fixture.planningReadGate.release();
      await _settle();

      expect(fixture.auth.state.currentUserId, _userB);
      expect(fixture.planningUserId, isNot(_userA));
      expect(await fixture.readPlanNames(), isNot(contains('A secret plan')));
    });

    test('the active planning context held for A does not survive B\'s '
        'sign-in', () async {
      // A re-authenticates while offline: the planning lookup falls back to
      // A's cached organization, so the active planning context is A's while
      // the catalog (no songs cached) has none.
      final fixture = await _Fixture.create(
        seedSongsForA: false,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      await fixture.signInAs(_sessionA);
      expect(fixture.activePlanningUserId, _userA);
      await fixture.loseSession();
      expect(fixture.auth.state.currentUserId, _userA);

      await fixture.signInAs(_sessionB);
      expect(fixture.auth.state.currentUserId, _userB);

      expect(fixture.activePlanningUserId, isNot(_userA));
      final entries = await fixture.container.read(
        planningMutationEntriesProvider.future,
      );
      expect(
        entries.map((entry) => entry.aggregateId),
        isNot(contains('plan-a-edit')),
      );
    });

    test('a catalog establishment started for A does not land after B signs '
        'in', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: false,
      );
      fixture.catalogReadGate.hold();
      await fixture.coldStartAsA();
      expect(fixture.catalogContextUserId, isNull, reason: 'held on the gate');

      await fixture.signInAs(_sessionB);
      fixture.catalogReadGate.release();
      await _settle();

      expect(fixture.auth.state.currentUserId, _userB);
      expect(fixture.catalogContextUserId, isNot(_userA));
      expect(await fixture.readSongTitles(), isNot(contains('A secret song')));
    });
  });

  group('explicit sign-out deletes only the signing-out user\'s data '
      '(AC9, AC10)', () {
    test('B signing out in the F7 state leaves A\'s plans and pending work '
        'and still deletes B\'s own pending work (AC9)', () async {
      // B's own local data: a pending planning mutation without a cached
      // projection, so no planning context of B's is ever established and
      // the sign-out cannot take its target from held state.
      final fixture = await _Fixture.create(
        seedSongsForA: false,
        seedPlanningForA: true,
        seedPendingPlanningForB: true,
      );
      await fixture.coldStartAsA();
      await fixture.signInAs(_sessionB);
      expect(fixture.auth.state.currentUserId, _userB);

      await fixture.signOut();
      expect(fixture.auth.state.status, AppAuthStatus.signedOut);

      expect(await fixture.pendingPlanningMutationCount(_userA), 1);
      expect(
        await fixture.planningStore.hasProjection(
          userId: _userA,
          organizationId: _orgA,
        ),
        isTrue,
      );
      expect(
        await fixture.pendingPlanningMutationCount(_userB),
        0,
        reason: 'explicit sign-out still deletes the signing-out user\'s data',
      );
    });

    test('B signing out after A\'s planning context was held leaves A\'s '
        'plans and pending work (AC9, stale fallback)', () async {
      // A re-authenticates offline first, so planning has recorded A as its
      // last authenticated user; B then signs in and out.
      final fixture = await _Fixture.create(
        seedSongsForA: false,
        seedPlanningForA: true,
        seedPendingPlanningForB: true,
      );
      await fixture.coldStartAsA();
      await fixture.signInAs(_sessionA);
      await fixture.loseSession();
      await fixture.signInAs(_sessionB);
      expect(fixture.auth.state.currentUserId, _userB);

      await fixture.signOut();
      expect(fixture.auth.state.status, AppAuthStatus.signedOut);

      expect(await fixture.pendingPlanningMutationCount(_userA), 1);
      expect(
        await fixture.planningStore.hasProjection(
          userId: _userA,
          organizationId: _orgA,
        ),
        isTrue,
      );
      expect(await fixture.pendingPlanningMutationCount(_userB), 0);
    });

    test('after a cancelled reauth A sees none of B\'s songs, and A\'s '
        'sign-out deletes A\'s data and leaves B\'s (AC10)', () async {
      // B's songs were cached during B's session (a refresh while the
      // different-user prompt was pending). A has plans but no songs.
      final fixture = await _Fixture.create(
        seedSongsForA: false,
        seedPlanningForA: true,
        seedSongsForB: true,
      );
      await fixture.coldStartAsA();
      await fixture.signInAs(_sessionB);
      expect(fixture.catalogContextUserId, _userB);

      fixture.container.read(reauthPromptControllerProvider).answer(false);
      await _settle();
      expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
      expect(fixture.auth.state.currentUserId, _userA);
      expect(fixture.catalogContextUserId, isNot(_userB));
      expect(await fixture.readSongTitles(), isNot(contains('B own song')));
      expect(await fixture.readPlanNames(), contains('A secret plan'));

      await fixture.signOut();
      expect(fixture.auth.state.status, AppAuthStatus.signedOut);

      expect(
        await fixture.cachedSongTitles(userId: _userB, organizationId: _orgB),
        contains('B own song'),
        reason: 'A\'s sign-out must not delete B\'s songs',
      );
      expect(await fixture.pendingPlanningMutationCount(_userA), 0);
      expect(
        await fixture.planningStore.hasProjection(
          userId: _userA,
          organizationId: _orgA,
        ),
        isFalse,
      );
    });
  });

  group('the prior user\'s own access is unchanged', () {
    test('cancelling B\'s reauth returns A\'s songs and plans', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      await fixture.signInAs(_sessionB);
      expect(fixture.catalogContextUserId, isNot(_userA));

      fixture.container.read(reauthPromptControllerProvider).answer(false);
      await _settle();

      expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
      expect(fixture.auth.state.currentUserId, _userA);
      expect(fixture.catalogContextUserId, _userA);
      expect(fixture.planningUserId, _userA);
      expect(await fixture.readSongTitles(), contains('A secret song'));
      expect(await fixture.readPlanNames(), contains('A secret plan'));
    });

    test('A re-authenticating keeps A\'s songs and plans', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();

      await fixture.signInAs(_sessionA);

      expect(fixture.auth.state.status, AppAuthStatus.signedIn);
      expect(fixture.catalogContextUserId, _userA);
      expect(fixture.planningUserId, _userA);
      expect(await fixture.readSongTitles(), contains('A secret song'));
      expect(await fixture.readPlanNames(), contains('A secret plan'));
    });
  });

  // O1 (docs/deferred/2026-10-05-gate-cross-user-leaks.md,
  // docs/specs/2026-10-07-sign-out-pending-work-guard.md): an explicit
  // sign-out clears only the signing-out user's identity row.
  group('explicit sign-out clears only the signing-out user\'s identity '
      '(O1)', () {
    test('B signing out after losing the session leaves A\'s identity '
        'row', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      await fixture.signInAs(_sessionB);
      await fixture.loseSession();
      expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
      expect(fixture.auth.state.currentUserId, _userB);
      expect((await fixture.identityStore.read())?.userId, _userA);

      await fixture.signOut();
      expect(fixture.auth.state.status, AppAuthStatus.signedOut);

      expect(
        (await fixture.identityStore.read())?.userId,
        _userA,
        reason: 'B\'s sign-out must not clear A\'s identity row',
      );
    });

    test('B signing out while A\'s different-user prompt is pending leaves '
        'A\'s identity row', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      await fixture.signInAs(_sessionB);
      expect(fixture.auth.state.currentUserId, _userB);
      expect(
        fixture.container.read(reauthPromptControllerProvider).pending,
        isNotNull,
      );

      await fixture.signOut();
      expect(fixture.auth.state.status, AppAuthStatus.signedOut);

      expect(
        (await fixture.identityStore.read())?.userId,
        _userA,
        reason: 'B\'s sign-out must not clear A\'s identity row',
      );
    });

    test('A signing out clears A\'s own identity row', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      await fixture.signInAs(_sessionA);
      expect(fixture.auth.state.currentUserId, _userA);

      await fixture.signOut();
      expect(fixture.auth.state.status, AppAuthStatus.signedOut);

      expect(await fixture.identityStore.read(), isNull);
    });
  });

  // docs/specs/2026-10-11-reauth-wipe-recount.md: the
  // different-user wipe must not delete more of the prior user's pending
  // work than the user confirmed, and must not delete work written after a
  // zero count without asking. The import is the real ChordProImportController
  // over the real import service; only the platform file picker answers from
  // the test, and two gates pin the interleaving.
  group('the different-user wipe deletes only counted work', () {
    const importedTitles = ['Imported one', 'Imported two', 'Imported three'];

    test('rows the import writes behind the prompt are not deleted by the '
        'confirmation that named fewer', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      expect(fixture.catalogContextUserId, _userA);

      // A's import reaches its commit and waits before its first row.
      fixture.songWriteGate.hold();
      final importRun = fixture.startImport(importedTitles);
      await _settle();
      expect(fixture.importState, isA<ImportCommitting>());

      await fixture.signInAs(_sessionB);
      final prompt = fixture.container.read(reauthPromptControllerProvider);
      expect(
        (prompt.pending as ReauthDifferentUserPrompt?)?.pendingCount,
        1,
        reason: 'A\'s one plan edit',
      );

      // The import keeps writing A's rows behind the prompt.
      fixture.songWriteGate.release();
      await importRun;
      await _settle();
      expect(await fixture.pendingSongCount(_userA), importedTitles.length);

      prompt.answer(true);
      await _settle();

      expect(
        await fixture.pendingSongCount(_userA),
        importedTitles.length,
        reason:
            'the confirmation named 1 item; the 3 imported rows written '
            'after it must not be deleted by it',
      );
      expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
      expect(fixture.auth.state.currentUserId, _userA);
      expect((await fixture.identityStore.read())?.userId, _userA);
      expect(await fixture.pendingPlanningMutationCount(_userA), 1);
    });

    test('rows written between a zero count and the wipe are not deleted '
        'without a prompt', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
        seedPendingPlanningForA: false,
        gatePendingCount: true,
      );
      await fixture.coldStartAsA();
      expect(fixture.catalogContextUserId, _userA);

      fixture.songWriteGate.hold();
      final importRun = fixture.startImport(importedTitles);
      await _settle();
      expect(fixture.importState, isA<ImportCommitting>());

      // The count reads zero and is paused before the resolution acts on it.
      fixture.pendingCountGate.hold();
      await fixture.signInAs(_sessionB);
      expect(
        fixture.container.read(reauthPromptControllerProvider).pending,
        isNull,
      );

      // The import writes A's rows after the count.
      fixture.songWriteGate.release();
      await importRun;
      await _settle();
      expect(await fixture.pendingSongCount(_userA), importedTitles.length);

      fixture.pendingCountGate.release();
      await _settle();

      expect(
        await fixture.pendingSongCount(_userA),
        importedTitles.length,
        reason:
            'nobody was asked about these rows; a zero count must not '
            'authorise deleting work written after it',
      );
      expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
      expect(fixture.auth.state.currentUserId, _userA);
      expect((await fixture.identityStore.read())?.userId, _userA);
    });
  });

  group('the import guard protects only the prior user\'s work (AC10)', () {
    test('B\'s own import running during B\'s zero-count resolution does not '
        'decline B\'s sign-in, and B\'s files stay in B\'s catalog', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
        seedPendingPlanningForA: false,
        seedSongsForB: true,
        lookupAnswersFor: const {_userB},
        gatePendingCount: true,
      );
      await fixture.coldStartAsA();

      // A's count is held after its reads returned zero.
      fixture.pendingCountGate.hold();
      await fixture.signInAs(_sessionB);
      expect(fixture.catalogContextUserId, _userB);
      expect(
        fixture.container.read(reauthPromptControllerProvider).pending,
        isNull,
      );

      // B starts an import in B's own context; it waits at its first write.
      fixture.songWriteGate.hold(user: _userB);
      final importRun = fixture.startImport(const ['B one', 'B two']);
      await _settle();
      expect(fixture.importState, isA<ImportCommitting>());

      fixture.pendingCountGate.release();
      await _settle();

      expect(
        fixture.auth.state.status,
        AppAuthStatus.signedIn,
        reason: 'B\'s own import is not the prior user\'s work',
      );
      expect(fixture.auth.state.currentUserId, _userB);
      expect((await fixture.identityStore.read())?.userId, _userB);
      expect(
        fixture.container.read(reauthPromptControllerProvider).pending,
        isNull,
      );

      fixture.songWriteGate.release();
      await importRun;
      await _settle();
      expect(await fixture.pendingSongCount(_userB), 2);
      expect(await fixture.pendingSongCount(_userA), 0);
    });
  });

  // RW3 (docs/specs/2026-10-11-reauth-wipe-recount.md): a running import is
  // work nobody has counted yet, so the wipe declines while one runs; and the
  // guard must never stick once the import ended in any way.
  group('no different-user wipe while an import runs', () {
    const importedTitles = ['Imported one', 'Imported two', 'Imported three'];

    test('AC3: a confirmation made while the import is held deletes nothing '
        'and returns to A', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();

      fixture.songWriteGate.hold();
      final importRun = fixture.startImport(importedTitles);
      await _settle();
      expect(fixture.importState, isA<ImportCommitting>());

      await fixture.signInAs(_sessionB);
      final prompt = fixture.container.read(reauthPromptControllerProvider);
      expect((prompt.pending as ReauthDifferentUserPrompt?)?.pendingCount, 1);

      prompt.answer(true);
      await _settle();

      expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
      expect(fixture.auth.state.currentUserId, _userA);
      expect((await fixture.identityStore.read())?.userId, _userA);
      expect(await fixture.pendingPlanningMutationCount(_userA), 1);

      fixture.songWriteGate.release();
      await importRun;
      await _settle();
      expect(await fixture.pendingSongCount(_userA), importedTitles.length);
      expect(await fixture.pendingPlanningMutationCount(_userA), 1);
      expect((await fixture.identityStore.read())?.userId, _userA);
    });

    test('AC4: a zero count while the import is held asks nobody and '
        'deletes nothing', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
        seedPendingPlanningForA: false,
      );
      await fixture.coldStartAsA();

      fixture.songWriteGate.hold();
      final importRun = fixture.startImport(importedTitles);
      await _settle();
      expect(fixture.importState, isA<ImportCommitting>());

      await fixture.signInAs(_sessionB);

      expect(
        fixture.container.read(reauthPromptControllerProvider).pending,
        isNull,
      );
      expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
      expect(fixture.auth.state.currentUserId, _userA);
      expect((await fixture.identityStore.read())?.userId, _userA);

      fixture.songWriteGate.release();
      await importRun;
      await _settle();
      expect(await fixture.pendingSongCount(_userA), importedTitles.length);
      expect((await fixture.identityStore.read())?.userId, _userA);
    });

    Future<void> expectWipeRunsAfterImportEnded(_Fixture fixture) async {
      expect(
        fixture.container.read(importRunTrackerProvider).isRunning,
        isFalse,
      );
      await fixture.signInAs(_sessionB);
      expect(
        fixture.container.read(reauthPromptControllerProvider).pending,
        isNull,
        reason: 'a zero count asks nobody',
      );
      expect(fixture.auth.state.status, AppAuthStatus.signedIn);
      expect(fixture.auth.state.currentUserId, _userB);
      expect((await fixture.identityStore.read())?.userId, _userB);
    }

    test('AC9: a cancelled picker does not block the wipe', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
        seedPendingPlanningForA: false,
      );
      await fixture.coldStartAsA();

      await fixture.startImport(importedTitles, cancelPicker: true);
      await _settle();
      expect(fixture.importState, isA<ImportIdle>());

      await expectWipeRunsAfterImportEnded(fixture);
    });

    test(
      'AC9: an import whose every write failed does not block the wipe',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final fixture = await _Fixture.create(
          seedSongsForA: true,
          seedPlanningForA: true,
          seedPendingPlanningForA: false,
        );
        await fixture.coldStartAsA();

        fixture.songWriteGate.failFor(_userA);
        await fixture.startImport(importedTitles);
        await _settle();
        expect(fixture.importState, isA<ImportDone>());
        expect(await fixture.pendingSongCount(_userA), 0);

        await expectWipeRunsAfterImportEnded(fixture);
      },
    );

    test('AC9: an import whose controller was disposed mid-commit does not '
        'block the wipe', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
        seedPendingPlanningForA: false,
      );
      await fixture.coldStartAsA();

      fixture.songWriteGate.hold();
      final importRun = fixture.startImport(importedTitles);
      await _settle();
      expect(fixture.importState, isA<ImportCommitting>());
      expect(
        fixture.container.read(importRunTrackerProvider).isRunning,
        isTrue,
      );

      // The run holds the provider alive; closing the listener and
      // invalidating disposes the controller while the commit is paused.
      fixture.importSubscription!.close();
      fixture.container.invalidate(chordProImportControllerProvider);
      await _settle();

      await expectWipeRunsAfterImportEnded(fixture);

      // The orphaned run resumes into a disposed notifier. Its rows written
      // after the wipe are R10 orphans; only the failure is pinned.
      fixture.songWriteGate.release();
      await expectLater(importRun, throwsStateError);
    });
  });

  // R17 (docs/deferred/2026-10-09-sign-out-guard-residuals.md,
  // docs/specs/2026-10-11-import-run-ownership.md): the duplicate dialog is
  // answered after an await of unbounded length, and the commit read the LIVE
  // catalog context instead of the context the run analysed against. The
  // import is the real ChordProImportController over the real import and song
  // library services; only the platform file picker answers from the test.
  // The first two tests are red on main (the second one is the direction
  // review round 1 of #88 found); the last two pin what must stay possible.
  group('a duplicate resolution never writes into another user\'s catalog '
      '(R17)', () {
    const incomingForA = ['A secret song', 'A import one', 'A import two'];

    test('a: A\'s files, resolved after B signed in, are not queued in B\'s '
        'catalog or sent to B\'s organization', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
        seedPendingPlanningForA: false,
        seedSongsForB: true,
        lookupAnswersFor: const {_userB},
      );
      await fixture.coldStartAsA();
      expect(fixture.catalogContextUserId, _userA);

      // A's import analyses three files; one has a title A already has.
      await fixture.startImport(incomingForA);
      await _settle();
      final awaiting = fixture.importState;
      expect(awaiting, isA<ImportAwaitingDuplicateResolution>());
      expect(
        (awaiting as ImportAwaitingDuplicateResolution).result.duplicates,
        hasLength(1),
      );
      expect(awaiting.successes, hasLength(2));

      // The duplicate dialog stays open while B signs in. A has no unsynced
      // work, so there is no prompt: A's data is wiped and B is current.
      await fixture.signInAs(_sessionB);
      expect(
        fixture.container.read(reauthPromptControllerProvider).pending,
        isNull,
      );
      expect(fixture.auth.state.currentUserId, _userB);
      expect(fixture.catalogContextUserId, _userB);

      await fixture.resolveDuplicates(DuplicateResolution.overwrite);
      await _settle();

      expect(
        await fixture.pendingSongCount(_userB),
        0,
        reason: 'A\'s files must not become B\'s pending work',
      );
      expect(await fixture.pendingSongCount(_userA), 0);
      expect(
        await fixture.syncSongs(userId: _userB, organizationId: _orgB),
        isEmpty,
        reason: 'the sync sends B\'s pending work to B\'s organization',
      );
      expect(fixture.importState, isA<ImportFailed>());
    });

    test('b: B\'s files, resolved after B\'s prompt was cancelled, are not '
        'queued in A\'s catalog', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
        seedSongsForB: true,
        lookupAnswersFor: const {_userB},
      );
      await fixture.coldStartAsA();

      // A has unsynced work, so B's sign-in asks. While the prompt is
      // pending B's catalog context is live (R-C) and B imports into it.
      await fixture.signInAs(_sessionB);
      final prompt = fixture.container.read(reauthPromptControllerProvider);
      expect(prompt.pending, isA<ReauthDifferentUserPrompt>());
      expect(fixture.catalogContextUserId, _userB);

      await fixture.startImport(const [
        'B own song',
        'B import one',
        'B import two',
      ]);
      await _settle();
      final awaiting = fixture.importState;
      expect(awaiting, isA<ImportAwaitingDuplicateResolution>());
      expect(
        (awaiting as ImportAwaitingDuplicateResolution).result.duplicates,
        hasLength(1),
      );
      expect(awaiting.successes, hasLength(2));

      // B cancels; the app is A's offline view again and A's context is live.
      prompt.answer(false);
      await _settle();
      expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
      expect(fixture.auth.state.currentUserId, _userA);
      expect(fixture.catalogContextUserId, _userA);

      await fixture.resolveDuplicates(DuplicateResolution.overwrite);
      await _settle();

      expect(
        await fixture.pendingSongCount(_userA),
        0,
        reason: 'B\'s files must not become A\'s pending work',
      );
      expect(await fixture.pendingSongCount(_userB), 0);
      expect(
        await fixture.syncSongs(userId: _userA, organizationId: _orgA),
        isEmpty,
        reason: 'the sync sends A\'s pending work to A\'s organization',
      );
      expect(fixture.importState, isA<ImportFailed>());
    });

    test(
      'the dialog does not open when the picker straddled the sign-in of B (R18, second shape)',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final fixture = await _Fixture.create(
          seedSongsForA: true,
          seedPlanningForA: true,
          seedSongsForB: true,
          lookupAnswersFor: const {_userB},
        );
        await fixture.coldStartAsA();
        final seen = <ChordProImportState>[];
        final seenSubscription = fixture.container.listen(
          chordProImportControllerProvider,
          (_, next) => seen.add(next),
        );
        addTearDown(seenSubscription.close);

        final pickerAnswer = Completer<void>();
        final importRun = fixture.startImport(
          incomingForA,
          holdPickerUntil: pickerAnswer.future,
        );
        await _settle();
        expect(fixture.importState, isA<ImportPicking>());

        // A has unsynced work, so B's sign-in asks and B's context is live.
        await fixture.signInAs(_sessionB);
        final prompt = fixture.container.read(reauthPromptControllerProvider);
        expect(prompt.pending, isA<ReauthDifferentUserPrompt>());
        expect(fixture.catalogContextUserId, _userB);

        pickerAnswer.complete();
        await importRun;
        await _settle();

        expect(
          seen.whereType<ImportAwaitingDuplicateResolution>(),
          isEmpty,
          reason: 'the dialog must not list A\'s titles to B',
        );
        expect(fixture.importState, isA<ImportFailed>());
        expect(await fixture.pendingSongCount(_userA), 0);
        expect(await fixture.pendingSongCount(_userB), 0);
      },
    );

    test(
      'the dialog does not open when the analysis straddled the sign-in of B (R18, second shape)',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final fixture = await _Fixture.create(
          seedSongsForA: true,
          seedPlanningForA: true,
          seedSongsForB: true,
          lookupAnswersFor: const {_userB},
        );
        await fixture.coldStartAsA();
        final seen = <ChordProImportState>[];
        final seenSubscription = fixture.container.listen(
          chordProImportControllerProvider,
          (_, next) => seen.add(next),
        );
        addTearDown(seenSubscription.close);

        fixture.catalogReadGate.hold();
        final importRun = fixture.startImport(incomingForA);
        await _settle();
        expect(
          fixture.importState,
          isA<ImportAnalysing>(),
          reason: 'the run is blocked in the analysis\'s catalog read',
        );

        await fixture.signInAs(_sessionB);
        final prompt = fixture.container.read(reauthPromptControllerProvider);
        expect(prompt.pending, isA<ReauthDifferentUserPrompt>());
        expect(fixture.catalogContextUserId, _userB);

        fixture.catalogReadGate.release();
        await importRun;
        await _settle();

        expect(
          seen.whereType<ImportAwaitingDuplicateResolution>(),
          isEmpty,
          reason: 'the dialog must not list A\'s titles to B',
        );
        expect(fixture.importState, isA<ImportFailed>());
        expect(await fixture.pendingSongCount(_userA), 0);
        expect(await fixture.pendingSongCount(_userB), 0);
      },
    );

    test('A re-authenticating while the dialog is open still imports into '
        'A\'s catalog', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
        seedPendingPlanningForA: false,
      );
      await fixture.coldStartAsA();
      await fixture.startImport(incomingForA);
      await _settle();
      expect(fixture.importState, isA<ImportAwaitingDuplicateResolution>());

      await fixture.signInAs(_sessionA);
      expect(fixture.auth.state.status, AppAuthStatus.signedIn);
      expect(fixture.catalogContextUserId, _userA);

      await fixture.resolveDuplicates(DuplicateResolution.overwrite);
      await _settle();

      expect(fixture.importState, isA<ImportDone>());
      // Two new songs and the overwritten one.
      expect(await fixture.pendingSongCount(_userA), 3);
    });

    test('B\'s sign-in cancelled before the dialog is answered still imports '
        'A\'s files into A\'s catalog', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
        seedSongsForB: true,
        lookupAnswersFor: const {_userB},
      );
      await fixture.coldStartAsA();
      await fixture.startImport(incomingForA);
      await _settle();
      expect(fixture.importState, isA<ImportAwaitingDuplicateResolution>());

      await fixture.signInAs(_sessionB);
      final prompt = fixture.container.read(reauthPromptControllerProvider);
      expect(prompt.pending, isA<ReauthDifferentUserPrompt>());
      prompt.answer(false);
      await _settle();
      expect(fixture.auth.state.currentUserId, _userA);
      expect(fixture.catalogContextUserId, _userA);

      await fixture.resolveDuplicates(DuplicateResolution.overwrite);
      await _settle();

      expect(fixture.importState, isA<ImportDone>());
      expect(await fixture.pendingSongCount(_userA), 3);
      expect(await fixture.pendingSongCount(_userB), 0);
    });
  });

  // R10 and R16 (same residuals entry): an import that SO7 did not see (it
  // started inside the sign-out's count, or after its warning closed) picks
  // its files while the sign-out sequence runs, and its commit then writes
  // them under the signed-out user.
  group('an import picked during a sign-out writes nothing for the signed-out '
      'user (R10, R16)', () {
    test(
      'files returned by the picker after the sign-out are not written',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final fixture = await _Fixture.create(
          seedSongsForA: true,
          seedPlanningForA: true,
          seedPendingPlanningForA: false,
        );
        await fixture.coldStartAsA();

        final pickerAnswer = Completer<void>();
        final importRun = fixture.startImport(const [
          'Late one',
          'Late two',
        ], holdPickerUntil: pickerAnswer.future);
        await _settle();
        expect(fixture.importState, isA<ImportPicking>());

        // Zero count: no warning. The real command runs to the end while the
        // picker is still open.
        final outcome = await fixture.container
            .read(signOutCommandProvider)
            .run(confirmDiscard: (_) async => true);
        await _settle();
        expect(outcome, SignOutOutcome.signedOut);
        expect(fixture.auth.state.status, AppAuthStatus.signedOut);
        expect(fixture.catalogContextUserId, isNull);

        pickerAnswer.complete();
        await importRun;
        await _settle();

        expect(
          await fixture.pendingSongCount(_userA),
          0,
          reason:
              'the signed-out user\'s data was purged; the import must not '
              'write new rows for them',
        );
        expect(fixture.importState, isA<ImportFailed>());
      },
    );
  });
}

class _Fixture {
  _Fixture._({
    required this.container,
    required this.auth,
    required this.authRepository,
    required this.identityStore,
    required this.planningDatabase,
    required this.songDatabase,
    required this.songStore,
    required this.planningStore,
    required this.catalogReadGate,
    required this.planningReadGate,
    required this.songWriteGate,
    required this.pendingCountGate,
    required this.remote,
  });

  final ProviderContainer container;
  final AppAuthController auth;
  final _ControllableAuthRepository authRepository;
  final DriftLastKnownIdentityStore identityStore;
  final PlanningLocalDatabase planningDatabase;
  final SongCatalogDatabase songDatabase;
  final SongCatalogStore songStore;
  final PlanningLocalStore planningStore;
  final _ReadGate catalogReadGate;
  final _ReadGate planningReadGate;

  /// Pauses the real song writes for user A (the ChordPro import's rows).
  final _ReadGate songWriteGate;

  /// Pauses the different-user count for user A after its real Drift reads
  /// returned, before the resolution acts on it. Only wired when the fixture
  /// was created with `gatePendingCount: true`.
  final _ReadGate pendingCountGate;

  /// Records what a song sync pass would send to the backend, and to which
  /// organization (R17: "the sync uploads them").
  final _RecordingSongRemoteRepository remote;

  /// [lookupAnswersFor] lists the users whose organization lookup (catalog
  /// and planning) answers; for everyone else it hits a dropped connection.
  static Future<_Fixture> create({
    required bool seedSongsForA,
    required bool seedPlanningForA,
    Set<String> lookupAnswersFor = const {},
    Set<String> membershipAnswersFor = const {_userA, _userB},
    bool seedSongsForB = false,
    bool seedPendingPlanningForB = false,
    bool seedPendingPlanningForA = true,
    bool gatePendingCount = false,
  }) async {
    final catalogReadGate = _ReadGate();
    final planningReadGate = _ReadGate();
    final songWriteGate = _ReadGate();
    final pendingCountGate = _ReadGate();
    final remote = _RecordingSongRemoteRepository();
    final songDatabase = SongCatalogDatabase.inMemory();
    addTearDown(songDatabase.close);
    final songStore = _GatedSongCatalogStore(songDatabase, catalogReadGate);
    final planningDatabase = PlanningLocalDatabase.inMemory();
    addTearDown(planningDatabase.close);
    final planningStore = _GatedPlanningLocalStore(
      planningDatabase,
      planningReadGate,
    );
    final identityStore = DriftLastKnownIdentityStore.inMemory();

    if (seedSongsForA) {
      await songStore.replaceActiveSnapshot(
        userId: _userA,
        organizationId: _orgA,
        summaries: const [SongSummary(id: 'song-a', title: 'A secret song')],
        sources: const [
          SongSource(id: 'song-a', source: '{title: A secret song}'),
        ],
        refreshedAt: DateTime.utc(2026, 10, 1, 12),
      );
    }
    if (seedPlanningForA) {
      await planningStore.replaceActiveProjection(
        userId: _userA,
        organizationId: _orgA,
        plans: [
          CachedPlanRecord(
            id: 'plan-a',
            name: 'A secret plan',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 10, 1, 12),
          ),
        ],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 10, 1, 12),
      );
    }
    if (seedSongsForB) {
      await songStore.replaceActiveSnapshot(
        userId: _userB,
        organizationId: _orgB,
        summaries: const [SongSummary(id: 'song-b', title: 'B own song')],
        sources: const [
          SongSource(id: 'song-b', source: '{title: B own song}'),
        ],
        refreshedAt: DateTime.utc(2026, 10, 1, 12),
      );
    }
    if (seedPendingPlanningForB) {
      await planningDatabase
          .into(planningDatabase.cachedPlanningMutations)
          .insert(
            CachedPlanningMutationsCompanion.insert(
              userId: _userB,
              organizationId: _orgB,
              aggregateType: 'plan',
              aggregateId: 'plan-b-edit',
              mutationKind: PlanningMutationKind.planEdit.value,
              syncStatus: PlanningMutationSyncStatus.pending.value,
              orderKey: 1,
              updatedAt: DateTime.utc(2026, 10, 1, 12),
            ),
          );
    }
    // A's unsynced work: a different-user sign-in must ask before wiping it,
    // so the reauth prompt stays pending (ADR-029 D3).
    if (seedPendingPlanningForA) {
      await planningDatabase
          .into(planningDatabase.cachedPlanningMutations)
          .insert(
            CachedPlanningMutationsCompanion.insert(
              userId: _userA,
              organizationId: _orgA,
              aggregateType: 'plan',
              aggregateId: 'plan-a-edit',
              mutationKind: PlanningMutationKind.planEdit.value,
              syncStatus: PlanningMutationSyncStatus.pending.value,
              orderKey: 1,
              updatedAt: DateTime.utc(2026, 10, 1, 12),
            ),
          );
    }
    await identityStore.write(
      const LastKnownIdentity(
        userId: _userA,
        email: _emailA,
        organizationId: _orgA,
      ),
    );

    final authRepository = _ControllableAuthRepository();
    addTearDown(authRepository.dispose);
    // Disposed by the container (appAuthControllerProvider owns it).
    final auth = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
    );

    final lifecycle = LocalDataLifecycle(
      songCatalogStore: songStore,
      planningLocalStore: planningStore,
      identityStore: identityStore,
      noteLastKnownIdentity: auth.noteLastKnownIdentity,
      eventsRecorder: _NoopLocalDataEventsRecorder(),
    );

    final container = ProviderContainer(
      overrides: [
        // Unroutable: any request that slips through fails as connectivity.
        supabaseClientProvider.overrideWithValue(
          SupabaseClient('http://127.0.0.1:9', 'anon-key'),
        ),
        appAuthControllerProvider.overrideWith((_) => auth),
        songCatalogDatabaseProvider.overrideWithValue(songDatabase),
        planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
        songCatalogStoreProvider.overrideWithValue(songStore),
        planningLocalStoreProvider.overrideWithValue(planningStore),
        songMutationStoreProvider.overrideWithValue(
          _GatedSongMutationStore(
            songCatalogStore: songStore,
            planningLocalStore: planningStore,
            gate: songWriteGate,
          ),
        ),
        songMutationRemoteRepositoryProvider.overrideWithValue(remote),
        if (gatePendingCount)
          pendingLocalWorkCounterProvider.overrideWithValue(
            _gatedPendingLocalWorkCounter(
              DriftPendingLocalWorkReader(
                planningDatabase: planningDatabase,
                songDatabase: songDatabase,
              ),
              pendingCountGate,
            ),
          ),
        lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        localDataLifecycleProvider.overrideWithValue(lifecycle),
        appForegroundStateProvider.overrideWithValue(_ForegroundState()),
        // The membership RPC answers for the users in membershipAnswersFor
        // (by default everyone, so the gate opens) ...
        activeOrganizationResolutionProvider.overrideWithValue(() async {
          final userId = auth.state.currentUserId;
          if (userId == null || !membershipAnswersFor.contains(userId)) {
            return const ActiveOrganizationResolution.unknownConnectivityFailure();
          }
          return userId == _userB
              ? const ActiveOrganizationResolution.selected(_orgB)
              : const ActiveOrganizationResolution.selected(_orgA);
        }),
        // ... but the catalog and planning organization lookups only answer
        // for the users in lookupAnswersFor.
        activeOrganizationReaderProvider.overrideWithValue(() async {
          final userId = auth.state.currentUserId;
          if (userId != null && lookupAnswersFor.contains(userId)) {
            return userId == _userB ? _orgB : _orgA;
          }
          throw const SocketException('network is unreachable');
        }),
        catalogSessionVerifierProvider.overrideWithValue(
          () async => CatalogSessionStatus.unverifiableDueToConnectivity,
        ),
        supabaseSongRepositoryProvider.overrideWithValue(
          SupabaseSongRepository.testing(
            fetchCatalogPage:
                ({required organizationId, required after, required limit}) =>
                    throw const SocketException('network is unreachable'),
          ),
        ),
        planningRemoteRefreshRepositoryProvider.overrideWithValue(
          _OfflinePlanningRemoteRefreshRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Production mounts these through the router and the app shell.
    container.read(appAuthListenableProvider);
    container.read(membershipRefreshEffectProvider);
    final subscriptions = [
      container.listen(songCatalogControllerProvider, (_, _) {}),
      container.listen(planningSyncControllerProvider, (_, _) {}),
      container.listen(activeMembershipControllerProvider, (_, _) {}),
    ];
    addTearDown(() {
      for (final subscription in subscriptions) {
        subscription.close();
      }
    });

    return _Fixture._(
      container: container,
      auth: auth,
      authRepository: authRepository,
      identityStore: identityStore,
      planningDatabase: planningDatabase,
      songDatabase: songDatabase,
      songStore: songStore,
      planningStore: planningStore,
      catalogReadGate: catalogReadGate,
      planningReadGate: planningReadGate,
      songWriteGate: songWriteGate,
      pendingCountGate: pendingCountGate,
      remote: remote,
    );
  }

  String? get catalogContextUserId =>
      container.read(activeCatalogContextProvider)?.userId;

  String? get planningUserId =>
      container.read(planningSyncStateProvider).userId;

  String? get activePlanningUserId =>
      container.read(activePlanningContextProvider)?.userId;

  MembershipGateView get gateViewForCurrentUser => container
      .read(activeMembershipControllerProvider)
      .viewFor(hasPendingInvite: false);

  Future<List<String>> readSongTitles() async {
    final songs = await container.read(songLibraryListProvider.future);
    return songs.map((song) => song.title).toList();
  }

  Future<List<String>> readPlanNames() async {
    try {
      final plans = await container.read(planningPlanListProvider.future);
      return plans.map((plan) => plan.name).toList();
    } on StateError {
      // "Planning local data is unavailable": nothing is shown.
      return const [];
    }
  }

  Future<int> pendingPlanningMutationCount(String userId) async {
    final rows = await (planningDatabase.select(
      planningDatabase.cachedPlanningMutations,
    )..where((table) => table.userId.equals(userId))).get();
    return rows.length;
  }

  Future<void> coldStartAsA() async {
    await auth.restoreSession();
    await _settle();
    expect(auth.state.status, AppAuthStatus.sessionExpired);
    expect(auth.state.currentUserId, _userA);
  }

  Future<void> signInAs(AppAuthSession session) async {
    authRepository.emit(session);
    await _settle();
  }

  Future<List<String>> cachedSongTitles({
    required String userId,
    required String organizationId,
  }) async {
    final songs = await songStore.readActiveSummaries(
      userId: userId,
      organizationId: organizationId,
    );
    return songs.map((song) => song.title).toList();
  }

  Future<void> signOut() async {
    await auth.signOut();
    await _settle();
  }

  Future<void> loseSession() async {
    authRepository.emit(null);
    await _settle();
  }

  /// [userId]'s pending song rows, read by the production counter's reader.
  Future<int> pendingSongCount(String userId) {
    return DriftPendingLocalWorkReader(
      planningDatabase: planningDatabase,
      songDatabase: songDatabase,
    ).countSongPendingWork(userId: userId);
  }

  /// Starts a real ChordPro import of [titles] in the current catalog
  /// context. The platform file picker answers with one file per title; the
  /// returned future completes when the run ends.
  ///
  /// [holdPickerUntil] keeps the picker open (the run stays in Picking) until
  /// that future completes.
  Future<void> startImport(
    List<String> titles, {
    bool cancelPicker = false,
    Future<void>? holdPickerUntil,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_filePickerChannel, (call) async {
          await holdPickerUntil;
          if (cancelPicker) return null;
          return [
            for (final (index, title) in titles.indexed)
              {
                'name': 'import-$index.cho',
                'path': null,
                'bytes': Uint8List.fromList(
                  utf8.encode('{title: $title}\n[C]la'),
                ),
                'size': title.length,
              },
          ];
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_filePickerChannel, null),
    );
    importSubscription = container.listen(
      chordProImportControllerProvider,
      (_, _) {},
    );
    addTearDown(importSubscription!.close);
    return container
        .read(chordProImportControllerProvider.notifier)
        .startImport();
  }

  /// The listener keeping the import controller alive; set by [startImport].
  ProviderSubscription<ChordProImportState>? importSubscription;

  ChordProImportState get importState =>
      container.read(chordProImportControllerProvider);

  /// Answers the duplicate dialog the way the song list's host does
  /// (`SongListScreen._resolveImportDuplicates`): the controller is handed
  /// the successes of the awaiting state and one resolution per duplicate,
  /// and nothing else.
  Future<void> resolveDuplicates(DuplicateResolution resolution) {
    final awaiting = importState as ImportAwaitingDuplicateResolution;
    return container
        .read(chordProImportControllerProvider.notifier)
        .commitWithResolutions(
          context: awaiting.context,
          successes: awaiting.successes,
          resolvedDuplicates: [
            for (final duplicate in awaiting.result.duplicates)
              ResolvedDuplicate(duplicate: duplicate, resolution: resolution),
          ],
        );
  }

  /// Runs the real song sync pass for [userId]'s [organizationId] and returns
  /// everything the backend was sent so far.
  Future<List<({String organizationId, String title})>> syncSongs({
    required String userId,
    required String organizationId,
  }) async {
    await container
        .read(songMutationSyncControllerProvider)
        .syncPendingSongs(
          SongMutationContext(userId: userId, organizationId: organizationId),
        );
    return remote.uploads;
  }
}

/// Stands in for the backend of the song sync: records what a pass sends and
/// accepts it.
class _RecordingSongRemoteRepository implements SongMutationRemoteRepository {
  final uploads = <({String organizationId, String title})>[];

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    uploads.add((organizationId: organizationId, title: record.title));
    return record.copyWith(syncStatus: SongSyncStatus.synced, version: 1);
  }

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) => throw UnimplementedError('not used by these tests');

  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError('not used by these tests');
}

const _filePickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
);

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await pumpEventQueue(times: 50);
  }
}

/// Pauses (while held) or fails (after [failFor]) the gated Drift call for
/// user A: a read or a write, depending on where the gate is wired.
class _ReadGate {
  Completer<void>? _held;

  final _failing = <String>{};

  String _heldUser = _userA;

  /// Pauses the gated call for [user] (default A) until [release].
  void hold({String user = _userA}) {
    _held = Completer<void>();
    _heldUser = user;
  }

  /// A mode in which [passFor] throws for [userId] instead of pausing.
  void failFor(String userId) => _failing.add(userId);

  void release() {
    _held?.complete();
    _held = null;
  }

  Future<void> passFor(String userId) async {
    if (_failing.contains(userId)) {
      throw StateError('simulated write failure for $userId');
    }
    final held = _held;
    if (held != null && userId == _heldUser) {
      await held.future;
    }
  }
}

class _GatedSongCatalogStore extends DriftSongCatalogStore {
  _GatedSongCatalogStore(super.database, this._gate);

  final _ReadGate _gate;

  @override
  Future<List<SongSummary>> readActiveSummaries({
    required String userId,
    required String organizationId,
  }) async {
    await _gate.passFor(userId);
    return super.readActiveSummaries(
      userId: userId,
      organizationId: organizationId,
    );
  }
}

class _GatedPlanningLocalStore extends DriftPlanningLocalStore {
  _GatedPlanningLocalStore(super.database, this._gate);

  final _ReadGate _gate;

  @override
  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  }) async {
    await _gate.passFor(userId);
    return super.hasProjection(userId: userId, organizationId: organizationId);
  }
}

class _GatedSongMutationStore extends DriftSongMutationStore {
  const _GatedSongMutationStore({
    required super.songCatalogStore,
    required super.planningLocalStore,
    required this.gate,
  });

  final _ReadGate gate;

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    await gate.passFor(userId);
    return super.upsertSong(userId: userId, record: record);
  }
}

/// The production counter over the production reader; [gate] only pauses
/// after both real reads returned.
PendingLocalWorkCounter _gatedPendingLocalWorkCounter(
  DriftPendingLocalWorkReader reader,
  _ReadGate gate,
) {
  return PendingLocalWorkCounter(
    readPlanningPendingWorkCount: ({required userId}) async {
      final count = await reader.countPlanningPendingWork(userId: userId);
      await gate.passFor(userId);
      return count;
    },
    readSongPendingWorkCount: ({required userId}) async {
      final count = await reader.countSongPendingWork(userId: userId);
      await gate.passFor(userId);
      return count;
    },
  );
}

class _ControllableAuthRepository implements AuthRepository {
  final _sessions = StreamController<AppAuthSession?>.broadcast();

  void emit(AppAuthSession? session) => _sessions.add(session);

  void dispose() => _sessions.close();

  // Cold start offline: the persisted session cannot be restored.
  @override
  Future<AppAuthSession?> restoreSession() async => null;

  @override
  Stream<AppAuthSession?> watchSession() => _sessions.stream;

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {}

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

class _OfflinePlanningRemoteRefreshRepository
    implements PlanningRemoteRefreshRepository {
  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
  }) async {
    throw const SocketException('network is unreachable');
  }
}

class _ForegroundState implements AppForegroundState {
  final _changes = StreamController<bool>.broadcast();

  @override
  bool get isForeground => true;

  @override
  Stream<bool> watchForeground() => _changes.stream;
}

class _NoopLocalDataEventsRecorder implements LocalDataEventsRecorder {
  @override
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordEviction({
    required String target,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordRejectedEmptySnapshot({
    required String userId,
    required String organizationId,
  }) async {}

  @override
  Future<void> recordStorageWriteFailure({String? userId}) async {}

  @override
  Future<void> recordMembershipRevocationMarked({
    required String userId,
  }) async {}

  @override
  Future<void> recordMembershipRevocationCleared({
    required String userId,
  }) async {}

  @override
  Future<void> recordMembershipRevocationPurgeDeclined({
    required String userId,
    required MembershipRevocationPurgeDeclineReason reason,
  }) async {}
}
